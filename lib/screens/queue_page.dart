import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/app_state_provider.dart';
import '../providers/connection_state_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/queue_actions.dart';
import '../widgets/queue_zone.dart';
import '../widgets/search_cards/track_row_support.dart'
    show formatTotalDuration;
import '../widgets/slide_in_panel.dart';

/// The queue as a page of its own over Home, sliding in from the right like
/// the settings pages: what plays now, what follows, and what has played.
class QueuePage extends StatelessWidget {
  final VoidCallback onClose;
  final ValueChanged<bool>? onCoverageChanged;

  /// False while a panel opened over this one owns the system back.
  final bool handlesBack;

  /// Opens the queue menu: a sheet on phone, the panel tray on tablet.
  final VoidCallback onOpenMenu;

  final VoidCallback? onFindMusic;
  final double bottomPadding;
  final bool isTablet;

  const QueuePage({
    super.key,
    required this.onClose,
    required this.onOpenMenu,
    this.onCoverageChanged,
    this.handlesBack = true,
    this.onFindMusic,
    this.bottomPadding = 16,
    this.isTablet = false,
  });

  @override
  Widget build(BuildContext context) {
    return SlideInPanel(
      onClose: onClose,
      onCoverageChanged: onCoverageChanged,
      handlesBack: handlesBack,
      child: Material(
        color: KalinkaColors.background,
        child: Column(
          children: [
            _QueueHeader(onOpenMenu: onOpenMenu),
            Expanded(
              child: QueueZone(
                bottomPadding: bottomPadding,
                isTablet: isTablet,
                onOpenManagementTray: onOpenMenu,
                showMenuButton: false,
                onFindMusic: onFindMusic,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QueueHeader extends ConsumerWidget {
  final VoidCallback onOpenMenu;

  const _QueueHeader({required this.onOpenMenu});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queue = ref.watch(
      playQueueStateStoreProvider.select(
        (s) => (tracks: s.trackList, index: s.playbackState.index ?? 0),
      ),
    );
    final connection = ref.watch(connectionStateProvider);
    // As the queue's own menu: nothing to act on while the server is away.
    final offline =
        connection == ConnectionStatus.reconnecting ||
        connection == ConnectionStatus.offline ||
        connection == ConnectionStatus.none;

    final tracks = queue.tracks;
    final remaining = tracks.sublist(queue.index.clamp(0, tracks.length));
    final seconds = remaining.fold<int>(0, (sum, t) => sum + t.duration);
    final count = switch (remaining.length) {
      0 => tracks.isEmpty ? 'Empty' : 'Nothing left to play',
      1 => '1 track',
      final n => '$n tracks',
    };
    final summary = seconds > 0
        ? '$count · ${formatTotalDuration(seconds)}'
        : count;

    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 6, 8, 10),
        child: Row(
          children: [
            IconButton(
              tooltip: 'Back',
              onPressed: () => SlideInPanel.closeOf(context),
              icon: const Icon(
                Icons.arrow_back,
                size: 22,
                color: KalinkaColors.textPrimary,
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Semantics(
                    header: true,
                    child: Text(
                      'Your queue',
                      style: KalinkaFonts.display(
                        fontSize: KalinkaTypography.baseSize + 12,
                        fontWeight: FontWeight.w600,
                        color: KalinkaColors.textPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    summary,
                    style: KalinkaTextStyles.trackCountBadge,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (!offline) ...[
              if (tracks.isNotEmpty)
                IconButton(
                  tooltip: 'Save as collection',
                  onPressed: () => saveQueueToCollection(context, ref),
                  icon: const Icon(
                    Icons.playlist_add_rounded,
                    size: 22,
                    color: KalinkaColors.textSecondary,
                  ),
                ),
              IconButton(
                tooltip: 'Queue options',
                onPressed: onOpenMenu,
                icon: const Icon(
                  Icons.more_vert,
                  size: 20,
                  color: KalinkaColors.textSecondary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
