import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/search_session_provider.dart';
import '../../theme/app_theme.dart';
import '../search_cards/action_pill_button.dart';
import 'container_page_actions.dart';
import 'drive_folder_actions.dart';

/// What can be done from the folder shown: play or enqueue everything in it,
/// and, at the far end, go up to the folder enclosing it — away from Play
/// all, which replaces the queue.
class FolderPageActions extends ConsumerWidget {
  final CatalogPage page;
  final CatalogPage listing;

  /// A filter narrows the listing; see [ContainerPageActions.narrowed].
  final bool narrowed;
  final bool alignRight;

  const FolderPageActions({
    super.key,
    required this.page,
    required this.listing,
    required this.narrowed,
    this.alignRight = false,
  });

  static bool anyFor(CatalogPage page, CatalogPage listing) =>
      !identical(listing, page) || listing.canAdd || listing.onStorage;

  /// Reserve the widest library label and optional eject control before its
  /// storage location arrives, so loading cannot move the toolbar controls.
  static double widthFor(
    BuildContext context,
    CatalogPage page,
    CatalogPage listing, {
    bool iconOnly = false,
  }) {
    final widths = [
      if (listing.canAdd) ...[
        iconOnly
            ? kKalinkaPillTarget
            : ActionPillButton.widthOf(context, 'Play all'),
        iconOnly
            ? kKalinkaPillTarget
            : ActionPillButton.widthOf(context, 'Enqueue'),
      ],
      if (listing.onStorage) ...[
        if (iconOnly)
          kKalinkaPillTarget
        else ...[
          ActionPillButton.widthOf(context, 'Add to library'),
          kKalinkaPillTarget,
        ],
      ],
      if (!identical(listing, page)) kKalinkaPillTarget,
    ];
    return widths.fold(0.0, (sum, width) => sum + width) +
        8 * (widths.length - 1).clamp(0, widths.length);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final others =
            (listing.onStorage ? kKalinkaPillTarget + 8 : 0) +
            (!identical(listing, page) ? kKalinkaPillTarget + 8 : 0);
        final compact =
            ActionPillButton.widthOf(context, 'Play all') +
                ActionPillButton.widthOf(context, 'Enqueue') +
                8 +
                others >
            constraints.maxWidth;
        final row = Row(
          children: [
            if (listing.canAdd)
              Wrap(
                spacing: 8,
                children: ContainerPageActions.queueChips(
                  id: listing.id!,
                  name: listing.title,
                  narrowed: narrowed,
                  iconOnly: compact,
                ),
              ),
            if (listing.onStorage && listing.id != null) ...[
              if (listing.canAdd) const SizedBox(width: 8),
              // Given the room left, to fold its pills into one where it is short.
              Expanded(
                child: DriveFolderActions(
                  entityId: listing.id!,
                  title: listing.title ?? 'this folder',
                ),
              ),
            ] else
              const Spacer(),
            if (!identical(listing, page)) ...[
              if (listing.canAdd || listing.onStorage) const SizedBox(width: 8),
              Tooltip(
                message: 'Up one folder',
                child: ActionPillButton(
                  icon: Icons.drive_folder_upload_outlined,
                  circular: true,
                  semanticsLabel: 'Up one folder',
                  onTap: () {
                    ref
                        .read(searchSessionProvider.notifier)
                        .showEnclosingFolder();
                  },
                ),
              ),
            ],
          ],
        );
        // One shape either way, so the chips keep their state, such as
        // Enqueue's receipt, as the actions move between header and bar.
        return Align(
          alignment: Alignment.centerRight,
          child: SizedBox(
            width: alignRight
                ? math.min(
                    constraints.maxWidth,
                    widthFor(context, page, listing, iconOnly: compact),
                  )
                : constraints.maxWidth,
            child: row,
          ),
        );
      },
    );
  }
}
