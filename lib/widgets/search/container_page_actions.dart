import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data_model/data_model.dart';
import '../../providers/collection_edit_provider.dart';
import '../../providers/search_session_provider.dart';
import '../../theme/app_theme.dart';
import '../search_cards/action_pill_button.dart';
import '../search_cards/collection_row.dart';
import 'collections_edit_bar.dart';
import 'track_group_actions.dart';

/// What a playlist's or a collection's page does with the whole of it: Play
/// all and Enqueue, and for a collection, editing its tracks and the menu that
/// renames or deletes it. While collections are being edited, the editing bar
/// takes the row over.
class ContainerPageActions extends ConsumerWidget {
  final CatalogPage page;

  /// How many tracks it holds, as its source said; null until known.
  final int? total;

  const ContainerPageActions({super.key, required this.page, this.total});

  /// A collection: a playlist the server will edit for you.
  static bool isCollection(CatalogPage page) => page.isPlaylist && page.canEdit;

  /// The item the page stands for, made up from the page when it was opened
  /// without one.
  static BrowseItem itemOf(CatalogPage page) =>
      page.item ??
      BrowseItem(
        id: page.id!,
        name: page.title,
        canBrowse: true,
        canAdd: page.canAdd,
        canEdit: page.canEdit,
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final item = itemOf(page);
    final collection = isCollection(page);
    final editing =
        collection && ref.watch(collectionEditProvider.select((s) => s.active));
    final empty = total == 0;
    final name = item.playlist?.name ?? item.name ?? page.title;

    return Padding(
      padding: kKalinkaActionRowPadding,
      child: editing
          ? const CollectionEditingBar()
          : Row(
              children: [
                Expanded(
                  child: Wrap(
                    spacing: 8,
                    children: [
                      if (item.canAdd && !empty) ...[
                        PlayAllChip(trackIds: [item.id], trackCount: total),
                        AddAllChip(
                          trackIds: [item.id],
                          trackCount: total,
                          name: name,
                        ),
                      ],
                      if (collection)
                        ActionPillButton(
                          label: 'Edit',
                          // Not tune_rounded: that is the filters glyph.
                          icon: Icons.edit_note_rounded,
                          enabled: !empty && total != null,
                          semanticsLabel: 'Edit $name',
                          onTap: () => beginCollectionEditing(ref),
                        ),
                    ],
                  ),
                ),
                if (collection) CollectionMenuButton(item: item),
              ],
            ),
    );
  }
}
