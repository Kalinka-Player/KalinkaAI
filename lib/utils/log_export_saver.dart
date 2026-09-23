import '../providers/log_export_api.dart' show LogArchiveDownload;
import 'log_export_saver_io.dart'
    if (dart.library.js_interop) 'log_export_saver_web.dart'
    as impl;

/// How a save ended, as far as the app can know.
enum SaveOutcome {
  /// The file is complete where the user chose.
  saved,

  /// Handed to the browser, which may still be transferring or asking.
  started,

  /// Sent through the share sheet.
  shared,

  /// The user dismissed the picker; the archive is still on the server.
  cancelled,
}

/// A ready archive, as a saver needs it.
class LogArchive {
  final String filename;

  /// Where a browser fetches it by itself.
  final Uri url;

  /// Receives it in the app.
  final Future<LogArchiveDownload> Function() open;

  const LogArchive({
    required this.filename,
    required this.url,
    required this.open,
  });
}

/// Bytes received so far and, when the server said, how many to expect.
typedef SaveProgress = void Function(int received, int? total);

/// Puts a ready archive where the user wants it, the way this platform does.
///
/// A cancelled picker or a failed transfer leaves no partial file behind
/// where the platform allows, and never touches the archive on the server.
abstract class LogExportSaver {
  /// Whether [share] is offered on this platform.
  bool get canShare;

  Future<SaveOutcome> save(LogArchive archive, {SaveProgress? onProgress});

  Future<SaveOutcome> share(LogArchive archive, {SaveProgress? onProgress});
}

/// The saver for the platform the app runs on.
LogExportSaver platformLogExportSaver() => impl.platformLogExportSaver();
