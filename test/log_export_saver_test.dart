import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kalinka/providers/log_export_api.dart';
import 'package:kalinka/utils/log_export_saver.dart';
import 'package:kalinka/utils/log_export_saver_io.dart';

const _channel = MethodChannel('org.kalinka.kalinka/documents');

/// Records every call on the documents channel; the picker answers [picked].
List<MethodCall> _fakeDocuments({String? picked}) {
  final calls = <MethodCall>[];
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_channel, (call) async {
        calls.add(call);
        return switch (call.method) {
          'createDocument' => picked,
          'openWrite' => 7,
          _ => null,
        };
      });
  addTearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null),
  );
  return calls;
}

LogArchive _archive(Stream<List<int>> bytes, {void Function()? opened}) =>
    LogArchive(
      filename: 'kalinka-logs.zip',
      url: Uri.parse('http://kalinka/server/logs/export/download'),
      open: () async {
        opened?.call();
        return LogArchiveDownload(length: 6, bytes: bytes);
      },
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a dismissed picker downloads nothing and leaves the archive', () async {
    final calls = _fakeDocuments(picked: null);
    var opened = false;

    final outcome = await AndroidDocumentSaver().save(
      _archive(const Stream.empty(), opened: () => opened = true),
    );

    expect(outcome, SaveOutcome.cancelled);
    expect(opened, isFalse);
    expect(calls.map((c) => c.method), ['createDocument']);
    expect(calls.single.arguments, {
      'filename': 'kalinka-logs.zip',
      'mimeType': 'application/zip',
    });
  });

  test('the picked document receives every chunk, then is closed', () async {
    final calls = _fakeDocuments(picked: 'content://docs/1');
    final progress = <int>[];

    final outcome = await AndroidDocumentSaver().save(
      _archive(
        Stream.fromIterable([
          [1, 2, 3],
          [4, 5, 6],
        ]),
      ),
      onProgress: (received, _) => progress.add(received),
    );

    expect(outcome, SaveOutcome.saved);
    expect(calls.map((c) => c.method), [
      'createDocument',
      'openWrite',
      'write',
      'write',
      'close',
    ]);
    expect(progress, [3, 6]);
  });

  test('a transfer that fails removes the half-written document', () async {
    final calls = _fakeDocuments(picked: 'content://docs/1');

    await expectLater(
      AndroidDocumentSaver().save(
        _archive(
          Stream.fromIterable([
            [1, 2, 3],
          ]).followedBy(Stream.error(const LogExportUnreachableException())),
        ),
      ),
      throwsA(isA<LogExportUnreachableException>()),
    );

    expect(calls.map((c) => c.method), [
      'createDocument',
      'openWrite',
      'write',
      'close',
      'delete',
    ]);
    expect(calls.last.arguments, {'uri': 'content://docs/1'});
  });
}

extension on Stream<List<int>> {
  Stream<List<int>> followedBy(Stream<List<int>> next) async* {
    yield* this;
    yield* next;
  }
}
