import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kalinka/data_model/log_export.dart';
import 'package:kalinka/providers/connection_settings_provider.dart';
import 'package:kalinka/providers/connection_state_provider.dart';
import 'package:kalinka/providers/log_export_api.dart';
import 'package:kalinka/providers/playback_time_provider.dart';
import 'package:kalinka/screens/log_export_screen.dart';
import 'package:kalinka/utils/log_export_saver.dart';

class _Api implements LogExportApi {
  _Api(this.current);

  LogExportStatus current;
  Duration? lookback;
  bool? includeLocalRenderer;

  @override
  Future<LogExportStatus> status() async => current;

  @override
  Future<LogExportStatus> start({
    required Duration lookback,
    required bool includeLocalRenderer,
  }) async {
    this.lookback = lookback;
    this.includeLocalRenderer = includeLocalRenderer;
    return current = LogExportStatus(
      state: LogExportState.preparing,
      availableSources: current.availableSources,
    );
  }

  @override
  Future<void> withdraw() async {}

  @override
  Future<LogArchiveDownload> download() async =>
      LogArchiveDownload(length: 1, bytes: Stream.value([0]));

  @override
  Uri get downloadUrl =>
      Uri.parse('http://kalinka/server/logs/export/download');
}

class _Saver implements LogExportSaver {
  _Saver({required this.canShare});

  @override
  final bool canShare;
  int saves = 0;
  int shares = 0;

  @override
  Future<SaveOutcome> save(
    LogArchive archive, {
    SaveProgress? onProgress,
  }) async {
    saves++;
    return SaveOutcome.saved;
  }

  @override
  Future<SaveOutcome> share(
    LogArchive archive, {
    SaveProgress? onProgress,
  }) async {
    shares++;
    return SaveOutcome.shared;
  }
}

class _Connected extends ConnectionStateNotifier {
  @override
  ConnectionStatus build() => ConnectionStatus.connected;
}

class _Resumed extends AppLifecycleNotifier {
  @override
  AppLifecycleState build() => AppLifecycleState.resumed;
}

final _ready = LogExportStatus(
  state: LogExportState.ready,
  availableSources: const [LogSource.server],
  download: LogExportDownload(
    filename: 'kalinka-logs-20260923T100000Z.zip',
    sizeBytes: 96412,
    expiresAt: DateTime.utc(2026, 9, 23, 10, 30),
  ),
  warnings: const [
    LogExportNote(
      source: LogSource.server,
      code: 'history_shorter',
      message: 'The server\'s logs only go back to 2026-09-23T08:00:00Z.',
    ),
  ],
);

Future<void> _open(WidgetTester tester, _Api api, _Saver saver) async {
  tester.view.physicalSize = const Size(1080, 2400);
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        logExportApiProvider.overrideWithValue(api),
        connectionStateProvider.overrideWith(_Connected.new),
        appLifecycleProvider.overrideWith(_Resumed.new),
      ],
      child: MaterialApp(home: LogExportScreen(saver: () => saver)),
    ),
  );
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _close(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump();
}

void main() {
  testWidgets('offers the period and the local renderer, then prepares', (
    tester,
  ) async {
    final api = _Api(
      const LogExportStatus(
        state: LogExportState.none,
        availableSources: [LogSource.server, LogSource.localRenderer],
      ),
    );
    await _open(tester, api, _Saver(canShare: false));

    expect(find.text('Include renderer logs from this server'), findsOneWidget);
    expect(
      find.textContaining('may contain file and track names'),
      findsOneWidget,
    );

    await tester.tap(find.text('7 days'));
    await tester.pump();
    await tester.tap(find.text('Prepare logs'));
    await tester.pump();

    expect(api.lookback, const Duration(days: 7));
    expect(api.includeLocalRenderer, isFalse);
    expect(find.text('Collecting logs…'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    await _close(tester);
  });

  testWidgets('no renderer choice on a server that does not offer one', (
    tester,
  ) async {
    await _open(
      tester,
      _Api(const LogExportStatus(state: LogExportState.none)),
      _Saver(canShare: false),
    );

    expect(find.text('Include renderer logs from this server'), findsNothing);
    expect(find.text('Prepare logs'), findsOneWidget);
    await _close(tester);
  });

  testWidgets('a ready archive shows its size and notes, and downloads', (
    tester,
  ) async {
    final saver = _Saver(canShare: false);
    await _open(tester, _Api(_ready), saver);

    expect(find.text('Download ZIP · 94 KB'), findsOneWidget);
    expect(find.textContaining('only go back to'), findsOneWidget);
    expect(find.text('Share'), findsNothing);

    await tester.tap(find.text('Download ZIP · 94 KB'));
    await tester.pump();

    expect(saver.saves, 1);
    await _close(tester);
  });

  testWidgets('share is offered where the platform can share', (tester) async {
    final saver = _Saver(canShare: true);
    await _open(tester, _Api(_ready), saver);

    await tester.tap(find.text('Share'));
    await tester.pump();

    expect(saver.shares, 1);
    await _close(tester);
  });

  testWidgets('a failed export shows why and offers to try again', (
    tester,
  ) async {
    await _open(
      tester,
      _Api(
        const LogExportStatus(
          state: LogExportState.failed,
          availableSources: [LogSource.server],
          errorCode: 'collection_timeout',
          errorMessage: 'Collecting the logs took too long.',
        ),
      ),
      _Saver(canShare: false),
    );

    expect(find.text('Collecting the logs took too long.'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    await _close(tester);
  });

  test('sizes read the way a download button shows them', () {
    expect(formatByteSize(512), '512 B');
    expect(formatByteSize(96412), '94 KB');
    expect(formatByteSize(3 * 1024 * 1024 + 200 * 1024), '3.2 MB');
  });
}
