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
    final details = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Tooltip(
          message: last == null
              ? 'No completed check yet'
              : last.toLocal().toString(),
          child: Text(
            _lastChecked(last),
            style: KalinkaTextStyles.trackRowSubtitle,
          ),
        ),
        if (status.caption case final caption?)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(caption, style: KalinkaTextStyles.trackRowSubtitle),
          ),
      ],
    );
    final action = TextButton.icon(
      onPressed: scan.indexerAvailable && !status.scanBusy
          ? () => ref.read(indexerStatusProvider.notifier).rescan()
          : null,
      style:
          TextButton.styleFrom(
            minimumSize: const Size(48, 48),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            foregroundColor: KalinkaColors.textPrimary,
            disabledForegroundColor: KalinkaColors.textMuted,
            backgroundColor: Colors.transparent,
            textStyle: KalinkaFonts.sans(
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
            shape: const StadiumBorder(),
          ).copyWith(
            side: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.focused)
                  ? const BorderSide(color: KalinkaColors.textPrimary, width: 2)
                  : BorderSide.none,
            ),
            overlayColor: WidgetStateProperty.resolveWith(
              (states) =>
                  states.any(
                    {
                      WidgetState.hovered,
                      WidgetState.pressed,
                      WidgetState.focused,
                    }.contains,
                  )
                  ? KalinkaColors.surfaceOverlay
                  : null,
            ),
          ),
      icon: const ExcludeSemantics(child: Icon(Icons.refresh, size: 18)),
      label: Text(label),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;
              if (constraints.maxWidth < 320 * textScale) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    details,
                    const SizedBox(height: 4),
                    Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: action,
                    ),
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(child: details),
                  const SizedBox(width: 12),
                  action,
                ],
              );
            },
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
