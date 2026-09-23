import 'dart:io' show Directory, File, FileSystemException, Platform;
import 'dart:typed_data' show BytesBuilder, Uint8List;

import 'package:file_selector/file_selector.dart'
    show XTypeGroup, getSaveLocation;
import 'package:flutter/services.dart' show MethodChannel;
import 'package:share_plus/share_plus.dart' show ShareParams, SharePlus, XFile;

import 'log_export_saver.dart';

const _zipMimeType = 'application/zip';

LogExportSaver platformLogExportSaver() =>
    Platform.isAndroid ? AndroidDocumentSaver() : const DesktopFileSaver();

Future<Uint8List> _receiveAll(
  LogArchive archive,
  SaveProgress? onProgress,
) async {
  final download = await archive.open();
  final bytes = BytesBuilder(copy: false);
  await for (final chunk in download.bytes) {
    bytes.add(chunk);
    onProgress?.call(bytes.length, download.length);
  }
  return bytes.takeBytes();
}

/// Android: the system's Save dialog (Storage Access Framework) and the
/// share sheet.
///
/// The picked document is a content URI, not a path, so a platform channel
/// opens and writes it; Dart keeps the HTTP transfer.
class AndroidDocumentSaver implements LogExportSaver {
  AndroidDocumentSaver({
    this.channel = const MethodChannel('org.kalinka.kalinka/documents'),
  });

  final MethodChannel channel;

  @override
  bool get canShare => true;

  @override
  Future<SaveOutcome> save(
    LogArchive archive, {
    SaveProgress? onProgress,
  }) async {
    final uri = await channel.invokeMethod<String>('createDocument', {
      'filename': archive.filename,
      'mimeType': _zipMimeType,
    });
    if (uri == null) return SaveOutcome.cancelled;
    int? handle;
    try {
      // The document first: a response opened and then abandoned would hold
      // the connection, and the server's archive, until it timed out.
      handle = await channel.invokeMethod<int>('openWrite', {'uri': uri});
      final download = await archive.open();
      var received = 0;
      await for (final chunk in download.bytes) {
        await channel.invokeMethod<void>('write', {
          'handle': handle,
          'bytes': chunk is Uint8List ? chunk : Uint8List.fromList(chunk),
        });
        received += chunk.length;
        onProgress?.call(received, download.length);
      }
      await channel.invokeMethod<void>('close', {'handle': handle});
      return SaveOutcome.saved;
    } catch (_) {
      if (handle != null) {
        await channel.invokeMethod<void>('close', {'handle': handle});
      }
      await channel.invokeMethod<void>('delete', {'uri': uri});
      rethrow;
    }
  }

  @override
  Future<SaveOutcome> share(
    LogArchive archive, {
    SaveProgress? onProgress,
  }) async {
    final bytes = await _receiveAll(archive, onProgress);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile.fromData(bytes, mimeType: _zipMimeType)],
        fileNameOverrides: [archive.filename],
      ),
    );
    return SaveOutcome.shared;
  }
}

/// Linux, macOS and Windows: the native Save As dialog, then a transfer into
/// a scratch file, copied into place only once whole. Not beside the chosen
/// file: the macOS sandbox grants that one path and nothing next to it.
class DesktopFileSaver implements LogExportSaver {
  const DesktopFileSaver();

  @override
  bool get canShare => false;

  @override
  Future<SaveOutcome> save(
    LogArchive archive, {
    SaveProgress? onProgress,
  }) async {
    final location = await getSaveLocation(
      suggestedName: archive.filename,
      acceptedTypeGroups: const [
        XTypeGroup(
          label: 'ZIP',
          extensions: ['zip'],
          mimeTypes: [_zipMimeType],
        ),
      ],
    );
    if (location == null) return SaveOutcome.cancelled;
    final scratch = await Directory.systemTemp.createTemp('kalinka-logs-');
    final partial = File('${scratch.path}${Platform.pathSeparator}logs.part');
    try {
      final download = await archive.open();
      final sink = partial.openWrite();
      var received = 0;
      try {
        await for (final chunk in download.bytes) {
          sink.add(chunk);
          received += chunk.length;
          onProgress?.call(received, download.length);
        }
      } finally {
        await sink.close();
      }
      await partial.copy(location.path);
      return SaveOutcome.saved;
    } finally {
      try {
        await scratch.delete(recursive: true);
      } on FileSystemException catch (_) {}
    }
  }

  @override
  Future<SaveOutcome> share(LogArchive archive, {SaveProgress? onProgress}) =>
      throw UnsupportedError('Sharing is offered on Android only');
}
