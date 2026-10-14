import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/indexer_status_provider.dart';
import '../../theme/app_theme.dart';

/// Requests the same folder check the librarian runs periodically.
class LibraryRescanControl extends ConsumerStatefulWidget {
  const LibraryRescanControl({super.key});

  static bool isLibraryPage(String? id) =>
      id == 'kalinka:localfiles:catalog:files' ||
      id == 'kalinka:localfiles:catalog:recent';

  @override
  ConsumerState<LibraryRescanControl> createState() =>
      _LibraryRescanControlState();
}

class _LibraryRescanControlState extends ConsumerState<LibraryRescanControl>
    with IndexerPollHolder<LibraryRescanControl> {
  @override
  Widget build(BuildContext context) {
    final status = ref.watch(indexerStatusProvider);
    final scan = status.scan;
    if (scan?.rescanSupported != true) return const SizedBox.shrink();
    final label = status.requesting
        ? 'Requesting scan…'
        : scan!.scanPending
        ? 'Scan queued…'
        : scan.scanning
        ? 'Checking folders…'
        : 'Rescan library';
    final last = scan!.lastScanAt;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              OutlinedButton.icon(
                onPressed: scan.indexerAvailable && !status.scanBusy
                    ? () => ref.read(indexerStatusProvider.notifier).rescan()
                    : null,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(48, 48),
                  foregroundColor: KalinkaColors.textPrimary,
                  backgroundColor: KalinkaColors.surfaceElevated,
                  side: const BorderSide(color: KalinkaColors.borderDefault),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                icon: const Icon(Icons.refresh, size: 18),
                label: Text(label),
              ),
              Tooltip(
                message: last == null
                    ? 'No completed check yet'
                    : last.toLocal().toString(),
                child: Text(
                  _lastChecked(last),
                  style: KalinkaTextStyles.trackRowSubtitle,
                ),
              ),
            ],
          ),
          if (status.caption case final caption?)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(caption, style: KalinkaTextStyles.trackRowSubtitle),
            ),
          if (!scan.indexerAvailable || status.requestError != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                status.requestError ??
                    'Library checking is currently unavailable.',
                style: KalinkaTextStyles.trackRowSubtitle,
              ),
            ),
        ],
      ),
    );
  }

  String _lastChecked(DateTime? last) {
    if (last == null) return 'Not checked yet';
    final age = DateTime.now().difference(last);
    if (age.inMinutes < 1) return 'Last checked just now';
    if (age.inHours < 1) return 'Last checked ${age.inMinutes} min ago';
    if (age.inDays < 1) return 'Last checked ${age.inHours} hr ago';
    return 'Last checked ${age.inDays} ${age.inDays == 1 ? 'day' : 'days'} ago';
  }
}
