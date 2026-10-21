import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data_model/data_model.dart';
import '../../providers/collection_edit_provider.dart';
import '../../providers/selection_state_provider.dart';
import '../../theme/app_theme.dart';
import '../search/collection_menu_sheet.dart';
import '../tap_highlight.dart';
import 'action_pill_button.dart';
import 'browse_navigation_scope.dart';
import 'collection_identity.dart';
import 'open_chevron_button.dart';
import 'row_columns.dart';
import 'row_play_button.dart';
import 'track_row_support.dart';

/// A collection in a listing: its cover, what it holds, and the way into its
/// own page, where its tracks are played and edited. Play starts it without
/// opening it.
///
/// Long-press takes it into the selection, as every other container row does.
class CollectionRow extends ConsumerStatefulWidget {
  final BrowseItem item;

  const CollectionRow({super.key, required this.item});

  @override
  ConsumerState<CollectionRow> createState() => _CollectionRowState();
}

class _CollectionRowState extends ConsumerState<CollectionRow>
    with LongPressRingMixin {
  void _select() =>
      ref.read(selectionStateProvider.notifier).toggleContainer(widget.item.id);

  @override
  Widget build(BuildContext context) {
    void open() => openBrowsable(context, ref, widget.item);
    // An editing session holds its own gestures; a row only opens then.
    final editing = ref.watch(collectionEditProvider.select((s) => s.active));
    final changes = ref.watch(
      collectionEditProvider.select((s) => s.of(widget.item.id)?.changes ?? 0),
    );
    // Scoped watches so unrelated selection changes don't rebuild the row.
    final selecting = ref.watch(
      selectionStateProvider.select((s) => s.isActive),
    );
    final selected = ref.watch(
      selectionStateProvider.select(
        (s) => s.isContainerSelected(widget.item.id),
      ),
    );
    final partial = ref.watch(
      selectionStateProvider.select(
        (s) => s.isContainerPartial(widget.item.id),
      ),
    );
    final empty = (widget.item.playlist?.trackCount ?? 0) == 0;

    return CollectionFace(
      item: widget.item,
      listed: true,
      selected: selected && !editing,
      partial: partial,
      pressProgress: longPressing ? longPressProgress : 0,
      onTap: selecting && !editing ? _select : open,
      onSelectPressStart: selecting || editing
          ? null
          : () => startLongPressRing(_select),
      onSelectPressStop: selecting || editing ? null : cancelLongPressRing,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (editing && changes > 0) _ChangesChip(count: changes),
          if (!empty && !selecting && widget.item.canAdd)
            RowPlayButton(item: widget.item),
          OpenChevronButton(
            name: widget.item.playlist?.name ?? widget.item.name,
            onTap: open,
          ),
        ],
      ),
    );
  }
}

/// What a collection has staged, said on its row so a session's changes can
/// be found without unrolling every collection. Amber rather than berry:
/// nothing has happened yet, and amber is what this app already uses for
/// something waiting to be applied.
class _ChangesChip extends StatelessWidget {
  final int count;

  const _ChangesChip({required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(right: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: KalinkaColors.statusPendingSurface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: KalinkaColors.statusPending.withValues(alpha: 0.5),
        ),
      ),
      child: Text(
        count == 1 ? '1 CHANGE' : '$count CHANGES',
        style: KalinkaFonts.mono(
          fontSize: KalinkaTypography.baseSize - 3,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
          color: KalinkaColors.statusPendingLight,
        ),
      ),
    );
  }
}

/// Opens what can be done to the collection itself rather than to its music:
/// renaming it, and deleting it. It sits at the trailing end of the
/// collection page's actions, apart from Play all and Enqueue for that reason.
class CollectionMenuButton extends ConsumerWidget {
  final BrowseItem item;

  const CollectionMenuButton({super.key, required this.item});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ActionPillButton(
      icon: Icons.more_horiz_rounded,
      semanticsLabel:
          'More for ${item.playlist?.name ?? item.name ?? 'this collection'}',
      onTap: () => showCollectionMenuSheet(context, ref, item),
    );
  }
}

/// A collection on Home: tapping it opens the collection's page; the play
/// button starts it without going anywhere.
class CollectionShelfRow extends ConsumerWidget {
  final BrowseItem item;

  const CollectionShelfRow({super.key, required this.item});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final empty = (item.playlist?.trackCount ?? 0) == 0;
    void open() => openBrowsable(context, ref, item);

    return CollectionFace(
      item: item,
      onTap: open,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Nothing to start when there is nothing in it.
          if (!empty && item.canAdd) RowPlayButton(item: item),
          OpenChevronButton(
            name: item.playlist?.name ?? item.name,
            onTap: open,
          ),
        ],
      ),
    );
  }
}

/// The look of a collection wherever it is listed: cover, name, the sources
/// it draws on and the line that says what it holds. Only what sits at its
/// right end and what a gesture does differ between the two places one
/// appears.
class CollectionFace extends ConsumerWidget {
  final BrowseItem item;
  final Widget trailing;
  final VoidCallback onTap;

  /// Drawn as taken by the selection, and [partial] where some of its tracks
  /// have since been dropped from it.
  final bool selected;
  final bool partial;

  /// How far the long press that would select it has run, 0 when none is.
  final double pressProgress;

  /// Begins and abandons that press. Null where the row cannot be selected.
  final VoidCallback? onSelectPressStart;
  final VoidCallback? onSelectPressStop;

  /// An action drawn beside the name, where the row carries one.
  final Widget? nameAction;

  /// Keeps a listing's columns, empty, so its lines run unbroken past it.
  final bool listed;

  const CollectionFace({
    super.key,
    required this.item,
    required this.trailing,
    required this.onTap,
    this.selected = false,
    this.partial = false,
    this.pressProgress = 0,
    this.onSelectPressStart,
    this.onSelectPressStop,
    this.nameAction,
    this.listed = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final row = Semantics(
      button: true,
      label: item.playlist?.name ?? item.name ?? 'Unknown',
      child: GestureDetector(
        onTap: onTap,
        onLongPressStart: onSelectPressStart == null
            ? null
            : (_) => onSelectPressStart!(),
        onLongPressEnd: onSelectPressStop == null
            ? null
            : (_) => onSelectPressStop!(),
        onLongPressCancel: onSelectPressStop,
        behavior: HitTestBehavior.opaque,
        child: RowColumnsScope(
          builder: (context, measured) {
            final columns = listed ? measured : RowColumns.none;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              // The 3px the edge takes comes out of the inset, so selecting does
              // not nudge the row sideways.
              padding: EdgeInsets.only(
                top: 10,
                bottom: 10,
                left: selected ? 0 : 3,
              ),
              decoration: BoxDecoration(
                color: selected
                    ? KalinkaColors.accent.withValues(alpha: 0.07)
                    : Colors.transparent,
                border: selected
                    ? const Border(
                        left: BorderSide(color: KalinkaColors.accent, width: 3),
                      )
                    : null,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: CollectionIdentity(
                      item: item,
                      chosen: selected,
                      nameAction: nameAction,
                      coverMark: selected
                          ? (partial ? Icons.remove : Icons.check)
                          : null,
                      pressProgress: pressProgress,
                      columns: columns,
                    ),
                  ),
                  const SizedBox(width: 6),
                  RowColumnCells(
                    columns: columns,
                    detail: collectionSummary(item),
                    sourceCell: Row(
                      children: collectionSources(
                        item.catalog?.sources ?? const <String>[],
                      ),
                    ),
                  ),
                  RowTrailing(columns: columns, child: trailing),
                ],
              ),
            );
          },
        ),
      ),
    );
    return HoverHighlight(child: row);
  }
}
