/// Where a server's log export stands, as `GET /server/logs/export` reports.
enum LogExportState { none, preparing, ready, failed }

/// The log sources a server can include in an export.
abstract final class LogSource {
  static const server = 'server';

  /// The renderer installed on the server's own machine; offered only when
  /// the server lists it.
  static const localRenderer = 'local_renderer';
}

/// The ready archive: what it will be saved as, how big, and until when.
class LogExportDownload {
  final String filename;
  final int sizeBytes;
  final DateTime expiresAt;

  const LogExportDownload({
    required this.filename,
    required this.sizeBytes,
    required this.expiresAt,
  });

  factory LogExportDownload.fromJson(Map<String, dynamic> json) =>
      LogExportDownload(
        filename: json['filename'] as String,
        sizeBytes: (json['size_bytes'] as num).toInt(),
        expiresAt: DateTime.parse(json['expires_at'] as String),
      );
}

/// Something the user should know about a ready archive — history shorter
/// than asked for, older records dropped, a source that could not be read.
class LogExportNote {
  final String source;
  final String code;
  final String message;

  const LogExportNote({
    required this.source,
    required this.code,
    required this.message,
  });

  factory LogExportNote.fromJson(Map<String, dynamic> json) => LogExportNote(
    source: json['source'] as String,
    code: json['code'] as String,
    message: json['message'] as String,
  );
}

/// A server's one log export.
///
/// [download] is set only when [state] is ready, [errorMessage] only when it
/// failed.
class LogExportStatus {
  final LogExportState state;
  final List<String> availableSources;
  final LogExportDownload? download;
  final List<LogExportNote> warnings;
  final String? errorCode;
  final String? errorMessage;

  const LogExportStatus({
    required this.state,
    this.availableSources = const [],
    this.download,
    this.warnings = const [],
    this.errorCode,
    this.errorMessage,
  });

  static const none = LogExportStatus(state: LogExportState.none);

  bool get offersLocalRenderer =>
      availableSources.contains(LogSource.localRenderer);

  factory LogExportStatus.fromJson(Map<String, dynamic> json) {
    final error = json['error'] as Map?;
    final download = json['download'] as Map?;
    return LogExportStatus(
      state: LogExportState.values.firstWhere(
        (s) => s.name == json['state'],
        orElse: () => LogExportState.none,
      ),
      availableSources: [
        for (final s in (json['available_sources'] as List? ?? const []))
          s as String,
      ],
      download: download == null
          ? null
          : LogExportDownload.fromJson(download.cast<String, dynamic>()),
      warnings: [
        for (final w in (json['warnings'] as List? ?? const []))
          LogExportNote.fromJson((w as Map).cast<String, dynamic>()),
      ],
      errorCode: error?['code'] as String?,
      errorMessage: error?['message'] as String?,
    );
  }
}
