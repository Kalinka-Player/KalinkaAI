import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/catalog_cards_provider.dart';
import '../../providers/recently_added_provider.dart';
import '../shelf_heading.dart';
import 'preview_shelf.dart';

/// What arrived in the library last, on Home, drawn as its catalog's preview
/// asks. Absent until it has items, so a setup without a library source never
/// sees it come and go.
class RecentlyAddedSection extends ConsumerStatefulWidget {
  /// Opens the whole catalog, or one item in it, as a page.
  final OpenCatalog onOpenCatalog;

  const RecentlyAddedSection({super.key, required this.onOpenCatalog});

  @override
  ConsumerState<RecentlyAddedSection> createState() =>
      _RecentlyAddedSectionState();
}

class _RecentlyAddedSectionState extends ConsumerState<RecentlyAddedSection>
    with AutomaticKeepAliveClientMixin {
  // Kept while scrolled off, so coming back does not rebuild the rail.
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final onOpenCatalog = widget.onOpenCatalog;
    final async = ref.watch(recentlyAddedProvider);
    // A dependency reload can retain the previous value. Its artwork paths
    // must not be resolved against the newly selected server while loading.
    final shelf = async.isReloading || async.hasError ? null : async.value;
    if (shelf == null) {
      if (!async.isLoading) return const SizedBox.shrink();
      // Held back until the catalog is known to exist, so a setup without
      // one never sees a placeholder come and go.
      final groupsAsync = ref.watch(catalogCardGroupsProvider);
      final groups = groupsAsync.isReloading ? null : groupsAsync.value;
      final recent = groups == null ? null : recentCatalogIn(groups);
      if (recent == null) return const SizedBox.shrink();
      return _section(
        ShelfHeading(title: recent.plan.title.toUpperCase()),
        PreviewShelfShimmer(preview: recent.plan.preview),
      );
    }
    return _section(
      ShelfHeading(
        title: shelf.plan.title.toUpperCase(),
        onViewAll: () => onOpenCatalog(shelf.plan, shelf.provider),
      ),
      PreviewShelf(
        items: shelf.items,
        preview: shelf.plan.preview,
        storageId: shelf.plan.id,
        onOpenItem: (item) => onOpenCatalog(
          CatalogCardPlan(
            id: item.id,
            title: item.name ?? '',
            sourceName: shelf.plan.sourceName,
            // An album's page names its artist under the title.
            description: item.album?.artist?.name ?? item.subname,
            totalDurationSeconds: item.album?.duration,
            artPath: item.image?.large ?? item.image?.small,
            filters: item.catalog?.filters ?? const [],
            sections: item.sections ?? const [],
            canAdd: item.canAdd,
          ),
          shelf.provider,
        ),
      ),
    );
  }

  Widget _section(Widget heading, Widget body) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      heading,
      const SizedBox(height: 10),
      body,
      const SizedBox(height: 26),
    ],
  );
}
