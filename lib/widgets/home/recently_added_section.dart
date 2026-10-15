import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/catalog_cards_provider.dart';
import '../../providers/recently_added_provider.dart';
import '../shelf_heading.dart';
import 'preview_shelf.dart';

/// What arrived in the library last, on Home, drawn as its catalog's preview
/// asks. Absent until it has items, so a setup without a library source never
/// sees it come and go.
class RecentlyAddedSection extends ConsumerWidget {
  /// Opens the whole catalog, or one item in it, as a page.
  final OpenCatalog onOpenCatalog;

  const RecentlyAddedSection({super.key, required this.onOpenCatalog});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shelf = ref.watch(recentlyAddedProvider).value;
    if (shelf == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ShelfHeading(
          title: shelf.plan.title.toUpperCase(),
          onViewAll: () => onOpenCatalog(shelf.plan, shelf.provider),
        ),
        const SizedBox(height: 10),
        PreviewShelf(
          items: shelf.items,
          preview: shelf.plan.preview,
          onOpenItem: (item) => onOpenCatalog(
            CatalogCardPlan(
              id: item.id,
              title: item.name ?? '',
              sourceName: shelf.plan.sourceName,
              // An album's page names its artist under the title.
              description: item.album?.artist?.name ?? item.subname,
              totalDurationSeconds: item.album?.duration,
              artPath: item.image?.large ?? item.image?.small,
              sections: item.sections ?? const [],
              canAdd: item.canAdd,
            ),
            shelf.provider,
          ),
        ),
        const SizedBox(height: 26),
      ],
    );
  }
}
