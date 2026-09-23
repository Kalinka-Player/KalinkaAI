import 'dart:async' show Completer;

import 'package:fake_async/fake_async.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kalinka/data_model/log_export.dart';
import 'package:kalinka/providers/log_export_api.dart';
import 'package:kalinka/providers/log_export_provider.dart';
import 'package:kalinka/providers/playback_time_provider.dart';
import 'package:kalinka/utils/log_export_saver.dart';

LogExportStatus _status(LogExportState state) => LogExportStatus(
  state: state,
  availableSources: const [LogSource.server],
  download: state == LogExportState.ready
      ? LogExportDownload(
          filename: 'kalinka-logs.zip',
          sizeBytes: 4,
          expiresAt: DateTime.utc(2026, 9, 23, 10, 30),
        )
      : null,
);

/// Answers status reads from [answers], one per read, repeating the last.
class _FakeApi implements LogExportApi {
  _FakeApi(this.answers);

  final List<Object> answers;
  int reads = 0;
  int starts = 0;
  int withdrawals = 0;
  Object? downloadAnswer;

  Future<LogExportStatus> _answer(Object answer) async {
    if (answer is LogExportStatus) return answer;
    throw answer;
  }

  @override
  Future<LogExportStatus> status() {
    final answer = answers[reads.clamp(0, answers.length - 1)];
    reads++;
    return _answer(answer);
  }

  @override
  Future<LogExportStatus> start({
    required Duration lookback,
    required bool includeLocalRenderer,
  }) async {
    starts++;
    return _status(LogExportState.preparing);
  }

  @override
  Future<void> withdraw() async => withdrawals++;

  @override
  Future<LogArchiveDownload> download() async {
    final answer = downloadAnswer;
    if (answer != null) throw answer;
    return LogArchiveDownload(length: 4, bytes: Stream.value([1, 2, 3, 4]));
  }

  @override
  Uri get downloadUrl =>
      Uri.parse('http://kalinka/server/logs/export/download');
}

class _Lifecycle extends AppLifecycleNotifier {
  @override
  AppLifecycleState build() => AppLifecycleState.resumed;

  void set(AppLifecycleState next) => state = next;
}

class _Saver implements LogExportSaver {
  final received = <int>[];

  @override
  bool get canShare => false;

  @override
  Future<SaveOutcome> save(
    LogArchive archive, {
    SaveProgress? onProgress,
  }) async {
    final download = await archive.open();
    await for (final chunk in download.bytes) {
      received.addAll(chunk);
      onProgress?.call(received.length, download.length);
    }
    return SaveOutcome.saved;
  }

  @override
  Future<SaveOutcome> share(LogArchive archive, {SaveProgress? onProgress}) =>
      throw UnimplementedError();
}

/// Reports some progress, waits for [gate], then reports the rest.
class _GatedSaver implements LogExportSaver {
  final gate = Completer<void>();

  @override
  bool get canShare => false;

  @override
  Future<SaveOutcome> save(
    LogArchive archive, {
    SaveProgress? onProgress,
  }) async {
    onProgress?.call(1, 2);
    await gate.future;
    onProgress?.call(2, 2);
    return SaveOutcome.saved;
  }

  @override
  Future<SaveOutcome> share(LogArchive archive, {SaveProgress? onProgress}) =>
      throw UnimplementedError();
}

ProviderContainer _container(_FakeApi api) {
  final container = ProviderContainer(
    overrides: [
      logExportApiProvider.overrideWithValue(api),
      appLifecycleProvider.overrideWith(_Lifecycle.new),
    ],
  );
  container.listen(logExportProvider, (_, _) {});
  return container;
}

void main() {
  test(
    'reads the export when opened, then polls only while it is prepared',
    () {
      fakeAsync((async) {
        final api = _FakeApi([
          _status(LogExportState.preparing),
          _status(LogExportState.preparing),
          _status(LogExportState.ready),
        ]);
        final container = _container(api);
        async.flushMicrotasks();
        expect(container.read(logExportProvider).preparing, isTrue);

        async.elapse(const Duration(seconds: 2));
        expect(
          container.read(logExportProvider).status!.state,
          LogExportState.ready,
        );
        final readsWhenReady = api.reads;

        async.elapse(const Duration(seconds: 10));
        expect(api.reads, readsWhenReady);
        container.dispose();
      });
    },
  );

  test('no polling in the background, and a fresh read on return', () {
    fakeAsync((async) {
      final api = _FakeApi([_status(LogExportState.preparing)]);
      final container = _container(api);
      async.flushMicrotasks();
      final lifecycle =
          container.read(appLifecycleProvider.notifier) as _Lifecycle;

      lifecycle.set(AppLifecycleState.paused);
      final readsWhenPaused = api.reads;
      async.elapse(const Duration(seconds: 10));
      expect(api.reads, readsWhenPaused);

      lifecycle.set(AppLifecycleState.resumed);
      async.flushMicrotasks();
      expect(api.reads, readsWhenPaused + 1);
      container.dispose();
    });
  });

  test('an export seen preparing that reads as none was interrupted', () {
    fakeAsync((async) {
      final api = _FakeApi([
        _status(LogExportState.preparing),
        _status(LogExportState.none),
      ]);
      final container = _container(api);
      async.flushMicrotasks();

      async.elapse(const Duration(seconds: 1));

      final view = container.read(logExportProvider);
      expect(view.status!.state, LogExportState.none);
      expect(view.interrupted, isTrue);
      container.dispose();
    });
  });

  test('a silent server is waited for, not reported as a failure', () {
    fakeAsync((async) {
      final api = _FakeApi([
        _status(LogExportState.preparing),
        const LogExportUnreachableException(),
        _status(LogExportState.preparing),
      ]);
      final container = _container(api);
      async.flushMicrotasks();

      async.elapse(const Duration(seconds: 1));
      var view = container.read(logExportProvider);
      expect(view.waitingForServer, isTrue);
      expect(view.actionError, isNull);
      expect(view.preparing, isTrue);

      async.elapse(const Duration(seconds: 1));
      view = container.read(logExportProvider);
      expect(view.waitingForServer, isFalse);
      container.dispose();
    });
  });

  test('cancelling returns to no export without calling it interrupted', () {
    fakeAsync((async) {
      final api = _FakeApi([_status(LogExportState.preparing)]);
      final container = _container(api);
      async.flushMicrotasks();

      container.read(logExportProvider.notifier).withdraw();
      async.flushMicrotasks();

      final view = container.read(logExportProvider);
      expect(api.withdrawals, 1);
      expect(view.status!.state, LogExportState.none);
      expect(view.interrupted, isFalse);
      container.dispose();
    });
  });

  test('saving re-reads the export and does nothing once it has expired', () {
    fakeAsync((async) {
      final api = _FakeApi([
        _status(LogExportState.ready),
        _status(LogExportState.none),
      ]);
      final container = _container(api);
      async.flushMicrotasks();
      final saver = _Saver();
      SaveOutcome? outcome = SaveOutcome.saved;

      container
          .read(logExportProvider.notifier)
          .save(saver)
          .then((o) => outcome = o);
      async.flushMicrotasks();

      expect(outcome, isNull);
      expect(saver.received, isEmpty);
      expect(
        container.read(logExportProvider).status!.state,
        LogExportState.none,
      );
      container.dispose();
    });
  });

  test('saving a ready archive hands it to the saver', () {
    fakeAsync((async) {
      final api = _FakeApi([_status(LogExportState.ready)]);
      final container = _container(api);
      async.flushMicrotasks();
      final saver = _Saver();
      SaveOutcome? outcome;

      container
          .read(logExportProvider.notifier)
          .save(saver)
          .then((o) => outcome = o);
      async.flushMicrotasks();

      expect(outcome, SaveOutcome.saved);
      expect(saver.received, [1, 2, 3, 4]);
      final view = container.read(logExportProvider);
      expect(view.busy, isFalse);
      expect(view.transfer, isNull);
      container.dispose();
    });
  });

  test('leaving the screen mid-save lets the save finish', () {
    fakeAsync((async) {
      final container = ProviderContainer(
        overrides: [
          logExportApiProvider.overrideWithValue(
            _FakeApi([_status(LogExportState.ready)]),
          ),
          appLifecycleProvider.overrideWith(_Lifecycle.new),
        ],
      );
      final screen = container.listen(logExportProvider, (_, _) {});
      async.flushMicrotasks();
      final saver = _GatedSaver();
      SaveOutcome? outcome;

      container
          .read(logExportProvider.notifier)
          .save(saver)
          .then((o) => outcome = o);
      async.flushMicrotasks();
      screen.close();
      async.elapse(const Duration(milliseconds: 1));
      expect(container.exists(logExportProvider), isFalse);

      saver.gate.complete();
      async.flushMicrotasks();

      expect(outcome, SaveOutcome.saved);
      container.dispose();
    });
  });

  test('an archive gone mid-save turns back into Prepare logs', () {
    fakeAsync((async) {
      final api = _FakeApi([
        _status(LogExportState.ready),
        _status(LogExportState.ready),
        _status(LogExportState.none),
      ])..downloadAnswer = LogExportException.notReady;
      final container = _container(api);
      async.flushMicrotasks();

      container.read(logExportProvider.notifier).save(_Saver());
      async.flushMicrotasks();

      expect(
        container.read(logExportProvider).status!.state,
        LogExportState.none,
      );
      container.dispose();
    });
  });

  test('a server that predates log export says so', () {
    fakeAsync((async) {
      final container = _container(
        _FakeApi([const LogExportUnsupportedException()]),
      );
      async.flushMicrotasks();

      expect(container.read(logExportProvider).unsupported, isTrue);
      container.dispose();
    });
  });
}
