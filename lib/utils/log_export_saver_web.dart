import 'package:web/web.dart' as web;

import 'log_export_saver.dart';

LogExportSaver platformLogExportSaver() => const _BrowserSaver();

/// Leaves the transfer to the browser: a plain attachment download, never
/// fetched into the page, so the browser's own download UI and save prompt
/// handle it.
class _BrowserSaver implements LogExportSaver {
  const _BrowserSaver();

  @override
  bool get canShare => false;

  @override
  Future<SaveOutcome> save(
    LogArchive archive, {
    SaveProgress? onProgress,
  }) async {
    // `download` only helps a same-origin link; Content-Disposition is what
    // names the file everywhere else.
    final link = web.HTMLAnchorElement()
      ..href = archive.url.toString()
      ..download = archive.filename;
    web.document.body?.append(link);
    link.click();
    link.remove();
    return SaveOutcome.started;
  }

  @override
  Future<SaveOutcome> share(LogArchive archive, {SaveProgress? onProgress}) =>
      throw UnsupportedError('Sharing is not offered in a browser');
}
