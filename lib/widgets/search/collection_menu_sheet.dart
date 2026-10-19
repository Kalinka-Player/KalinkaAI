import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data_model/data_model.dart';
import '../../providers/collection_edit_provider.dart';
import '../../providers/collections_provider.dart';
import '../../providers/kalinka_player_api_provider.dart';
import '../../providers/search_session_provider.dart';
import '../../providers/toast_provider.dart';
import '../../theme/app_theme.dart';
import '../kalinka_bottom_sheet.dart';
import '../kalinka_button.dart';
import '../kalinka_dialog.dart';
import '../search_cards/collection_identity.dart';
import 'collection_name_sheet.dart';

/// What can be done to a collection as a whole, rather than to the music in
/// it: rename it, or delete it.
///
/// Both are single writes and neither belongs in the staged editing session —
/// that one is about which tracks a collection holds and in what order, and
/// stages every change until Done. These land as they are chosen, which is
/// why they hang off the collection's own overflow instead.
Future<void> showCollectionMenuSheet(
  BuildContext context,
  WidgetRef ref,
  BrowseItem item,
) async {
  final chosen = await showKalinkaBottomSheet<_CollectionAction>(
    context: context,
    contentBuilder: (_) => _CollectionMenu(item: item),
  );
  // What each choice opens is opened from where the menu was, not from inside
  // the menu: the sheet's own context goes with the sheet.
  if (chosen == null || !context.mounted) return;
  switch (chosen) {
    case _CollectionAction.rename:
      await showRenameCollectionSheet(context, ref, item);
    case _CollectionAction.delete:
      await _deleteCollection(context, ref, item);
  }
}

enum _CollectionAction { rename, delete }

String _nameOf(BrowseItem item) =>
    item.playlist?.name ?? item.name ?? 'this collection';

class _CollectionMenu extends StatelessWidget {
  final BrowseItem item;

  const _CollectionMenu({required this.item});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            kSheetGutter,
            16,
            kSheetGutter,
            14,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('COLLECTION', style: KalinkaTextStyles.sectionLabel),
              const SizedBox(height: 6),
              Text(
                _nameOf(item),
                style: KalinkaTextStyles.cardTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                collectionSummary(item),
                style: KalinkaTextStyles.trackRowSubtitle,
              ),
            ],
          ),
        ),
        const SheetDivider(),
        SheetRow(
          icon: Icons.edit_rounded,
          iconBackground: KalinkaColors.accentSubtle,
          iconColor: KalinkaColors.accentTint,
          label: 'Rename',
          sublabel: 'Give it another name',
          trailing: const SheetChevron(),
          onTap: () => Navigator.pop(context, _CollectionAction.rename),
        ),
        const SheetDivider(),
        SheetRow(
          icon: Icons.delete_outline_rounded,
          iconBackground: KalinkaColors.actionDelete.withValues(alpha: 0.12),
          iconColor: KalinkaColors.actionDelete,
          label: 'Delete',
          sublabel: 'Remove it and everything in it',
          labelColor: KalinkaColors.actionDelete,
          onTap: () => Navigator.pop(context, _CollectionAction.delete),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

/// Confirms, then deletes. The dialog names what goes with it: a collection
/// is its tracks, and nothing keeps them once it is gone.
Future<void> _deleteCollection(
  BuildContext context,
  WidgetRef ref,
  BrowseItem item,
) async {
  final name = _nameOf(item);
  final held = item.playlist?.trackCount ?? 0;
  final go = await showKalinkaDialog<bool>(
    context: context,
    builder: (dialog) => KalinkaDialog(
      side: KalinkaDialogSide.right,
      icon: Icons.delete_outline_rounded,
      iconColor: KalinkaColors.actionDelete,
      title: 'Delete $name?',
      message: held == 0
          ? 'This cannot be undone.'
          : 'Its $held ${held == 1 ? 'track' : 'tracks'} go with it. This '
                'cannot be undone.',
      actions: [
        KalinkaButton(
          label: 'Cancel',
          variant: KalinkaButtonVariant.neutral,
          fullWidth: true,
          onTap: () => Navigator.pop(dialog, false),
        ),
        KalinkaButton(
          label: 'Delete',
          fullWidth: true,
          onTap: () => Navigator.pop(dialog, true),
        ),
      ],
    ),
  );
  if (go != true) return;

  final api = ref.read(kalinkaProxyProvider);
  final toast = ref.read(toastProvider.notifier);
  try {
    await api.deleteCollection(item.id);
    // Anything an editing session had staged for it is staged against a
    // collection that no longer exists.
    ref.read(collectionEditProvider.notifier).reset(item.id);
    ref.read(collectionsRevisionProvider.notifier).bump();
    // Its own page has nothing left to show.
    final session = ref.read(searchSessionProvider);
    if (session.activeView == FindMusicView.catalogs &&
        session.catalogPage.id == item.id) {
      ref.read(searchSessionProvider.notifier).goBack();
    }
    toast.show('$name deleted');
  } catch (e) {
    toast.show('Could not delete $name: $e', isError: true);
  }
}
