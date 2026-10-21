import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/browse_detail_provider.dart';
import '../../providers/collection_edit_provider.dart';
import '../../providers/collections_provider.dart';
import '../../providers/kalinka_player_api_provider.dart';
import '../../providers/selection_state_provider.dart';
import '../../providers/toast_provider.dart';
import '../../theme/app_theme.dart';
import '../kalinka_button.dart';
import '../kalinka_dialog.dart';
import '../search_cards/action_pill_button.dart';
import 'collection_name_sheet.dart';

/// What the Collections screen does to the listing itself: make another one.
/// Each collection is edited on its own page.
///
/// New takes the outline berry that Play all takes over a plain Enqueue. Not
/// a fill: a fill marks where a decision lands, and for New that is Create,
/// inside the sheet this opens — spending berry on the doorway as well would
/// flatten the two into one step.
class CollectionsActions extends ConsumerWidget {
  const CollectionsActions({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: kKalinkaActionRowPadding,
      child: Align(
        alignment: Alignment.centerLeft,
        child: ActionPillButton(
          label: 'New',
          icon: Icons.add,
          accent: true,
          onTap: () => showNewCollectionSheet(context, ref),
          semanticsLabel: 'New collection',
        ),
      ),
    );
  }
}

/// Starts editing collections: their tracks become draggable and markable to
/// be dropped, and nothing is written until Done.
void beginCollectionEditing(WidgetRef ref) {
  // Two ways of marking rows at once would fight over the same tap.
  ref.read(selectionStateProvider.notifier).exitSelectionMode();
  ref.read(collectionEditProvider.notifier).begin();
}

/// Back while editing leaves editing, not the page: with nothing staged it
/// ends quietly, and anything staged is asked about first. False when the
/// user chose to keep editing.
Future<bool> leaveCollectionEditing(BuildContext context, WidgetRef ref) async {
  final changes = ref.read(collectionEditProvider).changes;
  if (changes > 0 && !await _confirmDiscard(context, changes)) return false;
  ref.read(collectionEditProvider.notifier).end();
  return true;
}

Future<bool> _confirmDiscard(BuildContext context, int changes) async {
  final go = await showKalinkaDialog<bool>(
    context: context,
    builder: (dialog) => KalinkaDialog(
      side: KalinkaDialogSide.browsing,
      icon: Icons.undo_rounded,
      iconColor: KalinkaColors.statusPending,
      title: 'Discard ${_changes(changes)}?',
      message:
          'None of it has been written yet, and leaving now writes none '
          'of it.',
      actions: [
        KalinkaButton(
          label: 'Keep editing',
          variant: KalinkaButtonVariant.neutral,
          fullWidth: true,
          onTap: () => Navigator.pop(dialog, false),
        ),
        KalinkaButton(
          label: 'Discard',
          fullWidth: true,
          onTap: () => Navigator.pop(dialog, true),
        ),
      ],
    ),
  );
  return go == true;
}

/// The running session: the way out without writing, what is staged, and the
/// one control that writes it. Done carries the screen's single berry fill —
/// editing is a decision surface, and this is where the decision lands.
class CollectionEditingBar extends ConsumerStatefulWidget {
  const CollectionEditingBar({super.key});

  @override
  ConsumerState<CollectionEditingBar> createState() =>
      _CollectionEditingBarState();
}

class _CollectionEditingBarState extends ConsumerState<CollectionEditingBar> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final changes = ref.watch(collectionEditProvider.select((s) => s.changes));

    return Row(
      children: [
        KalinkaButton(
          label: 'Cancel',
          variant: KalinkaButtonVariant.neutral,
          size: KalinkaButtonSize.compact,
          enabled: !_busy,
          onTap: _cancel,
        ),
        Expanded(
          child: Column(
            children: [
              Text('EDITING', style: KalinkaTextStyles.sectionLabel),
              const SizedBox(height: 2),
              Text(
                changes == 0
                    ? 'No changes yet'
                    : '$changes ${changes == 1 ? 'change' : 'changes'} staged',
                style: KalinkaTextStyles.trackRowSubtitle.copyWith(
                  color: changes == 0
                      ? KalinkaColors.textMuted
                      : KalinkaColors.statusPendingLight,
                ),
              ),
            ],
          ),
        ),
        KalinkaButton(
          label: 'Done',
          size: KalinkaButtonSize.compact,
          enabled: !_busy,
          onTap: _done,
        ),
      ],
    );
  }

  /// Leaving without writing. Nothing staged leaves silently; anything staged
  /// is asked about, because there is nowhere to get it back from.
  Future<void> _cancel() => leaveCollectionEditing(context, ref);

  /// Writes every collection that has something staged, one write each.
  ///
  /// A reorder is applied without asking — a move can be moved back — but
  /// removals are named and confirmed first: nothing keeps what a collection
  /// drops.
  Future<void> _done() async {
    final notifier = ref.read(collectionEditProvider.notifier);
    final changed = ref.read(collectionEditProvider).changed.toList();
    if (changed.isEmpty) {
      notifier.end();
      return;
    }
    final losing = [
      for (final entry in changed)
        if (entry.value.removing.isNotEmpty) entry.value,
    ];
    if (losing.isNotEmpty && !await _confirmRemoval(losing)) return;
    setState(() => _busy = true);
    final api = ref.read(kalinkaProxyProvider);
    final toast = ref.read(toastProvider.notifier);
    var removed = 0;
    var moved = 0;
    final unwritten = <String>{};
    String? trouble;

    for (final entry in changed) {
      final edit = entry.value;
      try {
        final outcome = await api.editCollection(
          entry.key,
          remove: edit.removing.toList(),
          order: edit.surviving,
        );
        // What went is the server's to report; what moved is the user's own
        // count, since the server counts every place a removal shifted.
        removed += outcome.removed;
        moved += edit.moved.length;
        ref.invalidate(collectionEntriesProvider(entry.key));
        ref.invalidate(browseDetailProvider(entry.key));
      } on CollectionChangedException {
        unwritten.add(entry.key);
        trouble = '${edit.name} changed while you were editing it';
      } catch (e) {
        unwritten.add(entry.key);
        trouble = 'Could not save ${edit.name}: $e';
      }
    }
    ref.read(collectionsRevisionProvider.notifier).bump();

    if (unwritten.isEmpty) {
      notifier.end();
      toast.show(_report(changed.length, removed, moved));
      return;
    }
    // What did not land stays staged, so it is still there to retry or drop.
    notifier.keepOnly(unwritten);
    toast.show(trouble!, isError: true);
    if (mounted) setState(() => _busy = false);
  }

  Future<bool> _confirmRemoval(List<CollectionEdit> losing) async {
    final tracks = losing.fold<int>(0, (n, e) => n + e.removing.length);
    final from = [
      for (final edit in losing) '${edit.removing.length} from ${edit.name}',
    ];
    final go = await showKalinkaDialog<bool>(
      context: context,
      builder: (dialog) => KalinkaDialog(
        side: KalinkaDialogSide.browsing,
        icon: Icons.remove_circle_outline_rounded,
        iconColor: KalinkaColors.actionDelete,
        title: 'Remove $tracks ${tracks == 1 ? 'track' : 'tracks'}?',
        message: '${from.join(' · ')}. This cannot be undone.',
        actions: [
          KalinkaButton(
            label: 'Cancel',
            variant: KalinkaButtonVariant.neutral,
            fullWidth: true,
            onTap: () => Navigator.pop(dialog, false),
          ),
          KalinkaButton(
            label: 'Remove',
            fullWidth: true,
            onTap: () => Navigator.pop(dialog, true),
          ),
        ],
      ),
    );
    return go == true;
  }
}

String _changes(int count) => '$count ${count == 1 ? 'change' : 'changes'}';

/// What the session came to, in one line.
String _report(int collections, int removed, int moved) {
  final what = [
    if (removed > 0) '$removed ${removed == 1 ? 'track' : 'tracks'} removed',
    if (moved > 0) '$moved moved',
  ];
  final where = collections == 1 ? '1 collection' : '$collections collections';
  return what.isEmpty ? 'Saved $where' : 'Saved $where · ${what.join(', ')}';
}
