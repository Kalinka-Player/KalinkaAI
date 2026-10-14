import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kalinka/data_model/data_model.dart';
import 'package:kalinka/providers/app_state_provider.dart';
import 'package:kalinka/providers/connection_settings_provider.dart';
import 'package:kalinka/providers/connection_state_provider.dart';
import 'package:kalinka/providers/indexer_status_provider.dart';
import 'package:kalinka/providers/kalinka_player_api_provider.dart';
import 'package:kalinka/providers/search_session_provider.dart';
import 'package:kalinka/providers/source_modules_provider.dart';
import 'package:kalinka/theme/app_theme.dart';
import 'package:kalinka/widgets/search/catalog_page_view.dart';
import 'package:kalinka/widgets/search/library_rescan_control.dart';

IndexerStatus _status({
  double? last = 1000.25,
  bool pending = false,
  bool scanning = false,
  bool available = true,
  bool enriching = false,
}) => IndexerStatus.fromJson({
  'localfiles': {
    'indexing': {
      'total': 0,
      'done': 0,
      'pending': 0,
      'in_progress': 0,
      'failed': 0,
      'coverage_pct': 0,
      'rescan_supported': true,
      'available': available,
      'scan_pending': pending,
      'scanning': scanning,
      'last_scan_at': last,
    },
    if (enriching) 'enrichment': {'total': 100, 'done': 73, 'pending': 27},
  },
});

class _Api implements KalinkaPlayerProxy {
  IndexerStatus status = _status();
  int requests = 0;
  int polls = 0;
  int browses = 0;
  Future<void> Function()? onRescan;
  Future<IndexerStatus> Function()? onPoll;
  List<BrowseItem> items = [];

  @override
  Future<void> rescanLibrary() async {
    requests++;
    await onRescan?.call();
  }

  @override
  Future<IndexerStatus> getIndexerStatus({List<String>? sources}) async {
    polls++;
    return onPoll == null ? status : await onPoll!();
  }

  @override
  Future<BrowseItemsList> browse(
    String id, {
    int offset = 0,
    int limit = 10,
    String? filter,
  }) async {
    browses++;
    return BrowseItemsList(
      offset,
      limit,
      items.length,
      items.skip(offset).take(limit).toList(),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class _Connected extends ConnectionStateNotifier {
  @override
  ConnectionStatus build() => ConnectionStatus.connected;
}

class _Adapter implements HttpClientAdapter {
  int code = 202;
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return ResponseBody.fromString(
      jsonEncode({'status': 'accepted'}),
      code,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late SharedPreferences prefs;
  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'Kalinka.host': 'server.test',
      'Kalinka.port': 8000,
    });
    prefs = await SharedPreferences.getInstance();
  });

  ProviderContainer containerFor(_Api api) {
    final container = ProviderContainer(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        kalinkaProxyProvider.overrideWithValue(api),
        sourceModulesProvider.overrideWith((ref) => const <ModuleInfo>[]),
        connectionStateProvider.overrideWith(_Connected.new),
        playerStateProvider.overrideWithValue(PlaybackState.empty),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  Future<ProviderContainer> pump(
    WidgetTester tester,
    _Api api, {
    String? pageId,
    List<BrowseItem> sections = const [],
    Size size = const Size(375, 812),
    double textScale = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final container = containerFor(api);
    if (pageId != null) {
      container
          .read(searchSessionProvider.notifier)
          .openCatalog(
            id: pageId,
            title: 'Music folders',
            folderLayout: pageId.endsWith(':files'),
            sections: sections,
          );
    }
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.dark(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(textScale),
              disableAnimations: true,
            ),
            child: child!,
          ),
          home: Scaffold(
            body: pageId == null
                ? const LibraryRescanControl()
                : Consumer(
                    builder: (context, ref, _) => CatalogPageView(
                      page: ref.watch(searchSessionProvider).catalogPage,
                      onBackToCatalogs: () {},
                    ),
                  ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  test(
    'API posts to the agreed endpoint and rejects an unsuccessful response',
    () async {
      final adapter = _Adapter();
      final api = KalinkaPlayerProxyImpl(
        client: Dio(BaseOptions(baseUrl: 'http://server.test'))
          ..httpClientAdapter = adapter,
      );
      await api.rescanLibrary();
      expect(adapter.requests.single.method, 'POST');
      expect(adapter.requests.single.path, '/indexer/rescan');
      expect(adapter.requests.single.data, isNull);
      adapter.code = 503;
      await expectLater(api.rescanLibrary(), throwsA(isA<DioException>()));
    },
  );

  test('old pipeline status still parses without scan metadata', () {
    final status = IndexerStatus.fromJson({
      'localfiles': {
        'indexing': {'total': 2, 'pending': 1},
      },
    });
    expect(status.modules['localfiles']!['indexing']!.rescanSupported, isFalse);
    expect(status.modules['localfiles']!['indexing']!.lastScanAt, isNull);
    expect(
      _status()
          .modules['localfiles']!['indexing']!
          .lastScanAt!
          .millisecondsSinceEpoch,
      1000250,
    );
  });

  test('an accepted request stays busy until acknowledged and duplicate taps coalesce', () async {
    final api = _Api();
    final container = containerFor(api);
    final notifier = container.read(indexerStatusProvider.notifier);
    await notifier.refresh();
    final gate = Completer<void>();
    api.onRescan = () => gate.future;
    final request = notifier.rescan();
    await notifier.refresh();
    await notifier.rescan();
    expect(api.requests, 1);
    expect(container.read(indexerStatusProvider).requesting, isTrue);
    api.status = _status(pending: true);
    gate.complete();
    await request;
    expect(container.read(indexerStatusProvider).requesting, isFalse);
    expect(container.read(indexerStatusProvider).scanBusy, isTrue);
    api.status = _status(last: 1001.5);
    await notifier.refresh();
    expect(container.read(indexerStatusProvider).scanBusy, isFalse);
    expect(container.read(indexerStatusProvider).libraryRevision, 1);
    await notifier.refresh();
    expect(container.read(indexerStatusProvider).libraryRevision, 1);
  });

  test(
    'a scan failing between polls leaves the rescan button usable',
    () async {
      final api = _Api();
      final container = containerFor(api);
      final notifier = container.read(indexerStatusProvider.notifier);
      await notifier.refresh();
      await notifier.rescan();
      expect(container.read(indexerStatusProvider).scanBusy, isFalse);
      expect(container.read(indexerStatusProvider).libraryRevision, 0);
      await notifier.rescan();
      expect(api.requests, 2);
    },
  );

  test(
    'a scan finishing before the first poll still refreshes the library',
    () async {
      final api = _Api()..status = _status(last: null);
      final container = containerFor(api);
      final notifier = container.read(indexerStatusProvider.notifier);
      await notifier.refresh();
      api.onRescan = () async {
        api.status = _status(last: 1002);
      };
      await notifier.rescan();
      expect(container.read(indexerStatusProvider).libraryRevision, 1);
      expect(container.read(indexerStatusProvider).scanBusy, isFalse);
    },
  );

  test(
    'a failed poll retains scan state, and worker failure clears busy state',
    () async {
      final api = _Api()..status = _status(scanning: true);
      final container = containerFor(api);
      final notifier = container.read(indexerStatusProvider.notifier);
      await notifier.refresh();
      api.onPoll = () async => throw Exception('offline');
      await notifier.refresh();
      expect(container.read(indexerStatusProvider).scanBusy, isTrue);
      expect(container.read(indexerStatusProvider).libraryRevision, 0);
      api.onPoll = null;
      api.status = _status(available: false);
      await notifier.refresh();
      expect(container.read(indexerStatusProvider).scanBusy, isFalse);
      expect(container.read(indexerStatusProvider).libraryRevision, 0);
    },
  );

  test(
    'late responses from the previous server cannot update this server',
    () async {
      final api = _Api();
      final container = containerFor(api);
      final notifier = container.read(indexerStatusProvider.notifier);
      await notifier.refresh();
      final gate = Completer<void>();
      api.onRescan = () => gate.future;
      final request = notifier.rescan();
      container
          .read(connectionSettingsProvider.notifier)
          .setDeviceEphemeral('Other', 'other.test', 8000);
      await container.pump();
      gate.complete();
      await request;
      expect(container.read(indexerStatusProvider).scan, isNull);
      expect(container.read(indexerStatusProvider).requesting, isFalse);
    },
  );

  for (final (id, withSections) in [
    ('kalinka:localfiles:catalog:files', false),
    ('kalinka:localfiles:catalog:recent', false),
    ('kalinka:localfiles:catalog:recent', true),
  ]) {
    testWidgets('rescan refreshes empty $id (sections: $withSections)', (
      tester,
    ) async {
      final api = _Api()..status = _status(enriching: true);
      final container = await pump(
        tester,
        api,
        pageId: id,
        sections: [
          if (withSections)
            BrowseItem(
              id: 'kalinka:localfiles:catalog:recent_tracks',
              name: 'Tracks',
              canBrowse: true,
              canAdd: true,
              catalog: Catalog(
                id: 'kalinka:localfiles:catalog:recent_tracks',
                title: 'Tracks',
                previewConfig: Preview(type: PreviewType.imageText),
              ),
            ),
        ],
      );
      expect(find.text('Rescan library'), findsOneWidget);
      final button = find.widgetWithText(TextButton, 'Rescan library');
      final lastChecked = tester.getRect(find.textContaining('Last checked'));
      final enrichment = tester.getRect(find.text('Enrichment · 73%'));
      final action = tester.getRect(button);
      expect(action.left, greaterThan(lastChecked.right));
      expect(enrichment.left, lastChecked.left);
      expect(enrichment.top, greaterThan(lastChecked.bottom));
      expect(action.height, greaterThanOrEqualTo(48));
      expect(tester.widget<TextButton>(button).onPressed, isNotNull);
      final before = api.browses;
      api.onRescan = () async {
        api.status = _status(last: 1005);
        api.items = [
          BrowseItem(
            id: 'kalinka:localfiles:catalog:folder.new',
            name: 'New music',
            canBrowse: true,
            canAdd: false,
            catalog: Catalog(
              id: 'kalinka:localfiles:catalog:folder.new',
              title: 'New music',
              previewConfig: Preview(type: PreviewType.folder),
            ),
          ),
        ];
      };
      await tester.tap(find.text('Rescan library'));
      await tester.pumpAndSettle();
      expect(api.requests, 1);
      expect(api.browses, greaterThan(before));
      expect(find.text('New music'), findsOneWidget);
      expect(container.read(searchSessionProvider).catalogPage.id, id);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('other catalogs have no rescan action', (tester) async {
    await pump(tester, _Api(), pageId: 'kalinka:jamendo:catalog:recent');
    expect(find.byType(LibraryRescanControl), findsNothing);
  });

  testWidgets('an older server hides the unsupported action', (tester) async {
    await pump(tester, _Api()..status = const IndexerStatus({}));
    expect(find.text('Rescan library'), findsNothing);
  });

  testWidgets('request failures are visible and allow retry', (tester) async {
    final api = _Api()..onRescan = (() async => throw Exception('offline'));
    await pump(tester, api);
    await tester.tap(find.text('Rescan library'));
    await tester.pumpAndSettle();
    expect(
      find.text('Couldn’t request a scan. Please try again.'),
      findsOneWidget,
    );
    api.onRescan = () async {
      api.status = _status(pending: true);
    };
    await tester.tap(find.text('Rescan library'));
    await tester.pumpAndSettle();
    expect(find.text('Scan queued…'), findsOneWidget);
    expect(
      find.text('Couldn’t request a scan. Please try again.'),
      findsNothing,
    );
    expect(api.requests, 2);
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'Scan queued…'))
          .onPressed,
      isNull,
    );
  });

  for (final size in [
    const Size(320, 812),
    const Size(375, 812),
    const Size(812, 375),
  ]) {
    testWidgets('control fits $size with large text and reduced motion', (
      tester,
    ) async {
      await pump(
        tester,
        _Api()..status = _status(scanning: true),
        size: size,
        textScale: 2.5,
      );
      expect(find.text('Checking folders…'), findsOneWidget);
      final button = find.widgetWithText(TextButton, 'Checking folders…');
      final action = tester.getRect(button);
      final lastChecked = tester.getRect(find.textContaining('Last checked'));
      expect(action.top, greaterThan(lastChecked.bottom));
      expect(action.right, closeTo(size.width - 16, 0.1));
      expect(action.left, greaterThanOrEqualTo(16));
      expect(action.height, greaterThanOrEqualTo(48));
      expect(tester.takeException(), isNull);
      expect(tester.widget<TextButton>(button).onPressed, isNull);
    });
  }

  testWidgets('scan polls promptly, then stops when its surface closes', (
    tester,
  ) async {
    final api = _Api()..status = _status(scanning: true);
    await pump(tester, api);
    final before = api.polls;
    await tester.pump(const Duration(seconds: 5));
    expect(api.polls, greaterThan(before));
    await tester.pumpWidget(const SizedBox());
    final closed = api.polls;
    await tester.pump(const Duration(seconds: 40));
    expect(api.polls, closed);
  });
}
