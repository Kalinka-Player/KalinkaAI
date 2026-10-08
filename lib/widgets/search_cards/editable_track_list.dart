import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data_model/data_model.dart';
import '../../providers/collection_edit_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/click_cursor.dart';
import '../../utils/haptics.dart';
import 'action_pill_button.dart';
import 'track_row_support.dart';

/// A collection's tracks while the screen is in edit mode: the same list,
/// with each row draggable by its handle and markable to be dropped.
///
/// Nothing is written here. What the user does is staged against the
/// collection's entry ids and committed by Done, so a session can be walked
/// back whole — and so removing and reordering land as one write rather than
/// as a sequence a dropped connection can halve.
class EditableTrackList extends ConsumerWidget {
  final BrowseItem item;

  const EditableTrackList({super.key, required this.item});

  String get _name => item.playlist?.name ?? item.name ?? 'this collection';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref.watch(collectionEntriesProvider(item.id));

    return entries.when(
      loading: () => const _Note.spinner(),
      error: (e, _) => const _Note('Could not read this collection'),
      data: (list) {
        if (list.items.isEmpty) {
          return const _Note('Nothing in this collection yet');
        }
        // Every row is addressed by its entry id — the id of the track's place
        // in this collection, not of the track, so the same track twice is two
        // rows that can be told apart.
        final ids = [
          for (final entry in list.items) entry.track?.playlistTrackId,
        ];
        if (ids.any((id) => id == null)) {
          return const _Note('These tracks cannot be edited');
        }
        if (list.total > list.items.length) {
          return _Note(
            'Too long to edit here — ${list.total} tracks, '
            'and an edit has to name them all',
          );
        }
        return _Rows(
          collectionId: item.id,
          held: (name: _name, entryIds: [for (final id in ids) id!]),
          items: list.items,
        );
      },
    );
  }
}

class _Rows extends ConsumerWidget {
  final String collectionId;
  final HeldCollection held;
  final List<BrowseItem> items;

  const _Rows({
    required this.collectionId,
    required this.held,
    required this.items,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final edit = ref.watch(
      collectionEditProvider.select((session) => session.of(collectionId)),
    );
    final byEntry = {
      for (var i = 0; i < items.length; i++) held.entryIds[i]: items[i],
    };
    // A staged order was taken before the last refetch, so anything it does
    // not name still shows — at the end, where a stale edit is visible rather
    // than silently dropping a row.
    final staged = edit?.order ?? const <String>[];
    final placed = staged.toSet();
    final rows = [
      for (final id in staged)
        if (byEntry.containsKey(id)) id,
      for (final id in held.entryIds)
        if (!placed.contains(id)) id,
    ];
    final notifier = ref.read(collectionEditProvider.notifier);

    return Column(
      children: [
        _EditHint(
          onReset: (edit?.changes ?? 0) == 0
              ? null
              : () => notifier.reset(collectionId),
        ),
        ReorderableListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          itemCount: rows.length,
          onReorderItem: (from, to) {
            KalinkaHaptics.lightImpact();
            notifier.reorder(collectionId, held, from, to);
          },
          itemBuilder: (context, index) {
            final entryId = rows[index];
            return _EditableTrackRow(
              key: ValueKey(entryId),
              item: byEntry[entryId]!,
              index: index,
              last: index == rows.length - 1,
              removing: edit?.removing.contains(entryId) ?? false,
              moved: edit?.hasMoved(entryId) ?? false,
              onToggle: () =>
                  notifier.toggleRemoval(collectionId, held, entryId),
            );
          },
        ),
      ],
    );
  }
}

/// What the rows below can be done to, and the way back out of it. Reset is
/// dead rather than absent while nothing is staged, so the line does not move
/// under the thumb the moment something is.
class _EditHint extends StatelessWidget {
  final VoidCallback? onReset;

  const _EditHint({this.onReset});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      child: Row(
        children: [
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  const TextSpan(text: 'Drag to reorder · tap '),
                  WidgetSpan(
                    alignment: PlaceholderAlignment.middle,
                    child: Icon(
                      Icons.remove_circle_outline_rounded,
                      size: 14,
                      color: KalinkaColors.textMuted,
                    ),
                  ),
                  const TextSpan(text: ' to remove'),
                ],
              ),
              style: KalinkaTextStyles.trackRowSubtitle.copyWith(
                color: KalinkaColors.textMuted,
              ),
            ),
          ),
          ActionPillButton(
            label: 'Reset',
            enabled: onReset != null,
            onTap: onReset,
            semanticsLabel: 'Undo the changes staged here',
          ),
        ],
      ),
    );
  }
}

/// One track under an editing session: what it is, whether it is leaving, and
/// where it now sits.
///
/// A row marked to go keeps its place until Done — putting it back puts it
/// back where it was — and dims rather than disappearing, so nothing shifts
/// under the finger that marked it.
class _EditableTrackRow extends StatelessWidget {
  final BrowseItem item;
  final int index;
  final bool last;
  final bool removing;
  final bool moved;
  final VoidCallback onToggle;

  const _EditableTrackRow({
    super.key,
    required this.item,
    required this.index,
    required this.last,
    required this.removing,
    required this.moved,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final track = item.track;
    final title = track?.title ?? item.name ?? 'Unknown';
    final artist = track?.performer?.name ?? '';
    final album = track?.album?.title ?? '';
    final subtitle = [artist, album].where((s) => s.isNotEmpty).join(' · ');
    final duration = formatTrackDuration(
      track?.duration != null ? track!.duration * 1000 : null,
    );
    // A moved row is marked, a row that is leaving is not: it is going, so
    // where it sits has stopped being a thing to say about it.
    final marked = moved && !removing;

    return Container(
      decoration: BoxDecoration(
        color: marked ? KalinkaColors.statusPendingSurface : null,
        border: Border(
          left: BorderSide(
            color: marked ? KalinkaColors.statusPending : Colors.transparent,
            width: 2,
          ),
          bottom: last
              ? BorderSide.none
              : const BorderSide(color: KalinkaColors.borderSubtle),
        ),
      ),
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          _RemoveToggle(removing: removing, name: title, onTap: onToggle),
          Expanded(
            child: Opacity(
              opacity: removing ? 0.45 : 1.0,
              child: Row(
                children: [
                  TrackThumb(item: item),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          style: KalinkaTextStyles.trackRowTitle.copyWith(
                            decoration: removing
                                ? TextDecoration.lineThrough
                                : null,
                            decorationColor: KalinkaColors.textMuted,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (subtitle.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            subtitle,
                            style: KalinkaTextStyles.trackRowSubtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (duration != null) ...[
                    const SizedBox(width: 8),
                    Text(duration, style: KalinkaTextStyles.trackRowSubtitle),
                  ],
                ],
              ),
            ),
          ),
          // Nothing to place a row that is leaving, but its width stays so the
          // rows beside it keep their column.
          removing
              ? const SizedBox(width: 48, height: 44)
              : _DragHandle(index: index, marked: marked),
        ],
      ),
    );
  }
}

/// Marks a track to be dropped when the session lands, and takes it back. It
/// is not a tick box: sixty ticked boxes meaning *keep* would be the wrong way
/// round, and a tick that removes fights every other tick in the app.
class _RemoveToggle extends StatelessWidget {
  final bool removing;
  final String name;
  final VoidCallback onTap;

  const _RemoveToggle({
    required this.removing,
    required this.name,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: removing ? 'Keep $name' : 'Remove $name',
      child: MouseRegion(
        cursor: clickCursor(interactive: true),
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: SizedBox(
            width: 44,
            height: 44,
            child: Center(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: removing
                      ? KalinkaColors.actionDeleteSurface
                      : Colors.transparent,
                  border: Border.all(
                    color: removing
                        ? KalinkaColors.actionDelete
                        : KalinkaColors.borderDefault,
                  ),
                ),
                child: Icon(
                  removing ? Icons.undo_rounded : Icons.remove_rounded,
                  size: 16,
                  color: removing
                      ? KalinkaColors.actionDeleteLight
                      : KalinkaColors.textMuted,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DragHandle extends StatelessWidget {
  final int index;

  /// Drawn in the staged amber where this is a row the user moved.
  final bool marked;

  const _DragHandle({required this.index, required this.marked});

  @override
  Widget build(BuildContext context) {
    return ReorderableDragStartListener(
      index: index,
      child: MouseRegion(
        cursor: SystemMouseCursors.grab,
        child: SizedBox(
          width: 48,
          height: 44,
          child: Center(
            child: Icon(
              Icons.drag_handle,
              size: 20,
              color: marked
                  ? KalinkaColors.statusPendingLight
                  : KalinkaColors.textMuted,
            ),
          ),
        ),
      ),
    );
  }
}

/// What stands where the rows would be.
class _Note extends StatelessWidget {
  final String? text;

  const _Note(this.text);

  const _Note.spinner() : text = null;

  @override
  Widget build(BuildContext context) {
    final text = this.text;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: text == null
          ? const Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          : Text(text, style: KalinkaTextStyles.trackRowSubtitle),
    );
  }
}
