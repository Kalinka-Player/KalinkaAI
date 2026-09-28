import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data_model/browse_filters.dart';
import '../../data_model/data_model.dart';
import '../../providers/catalog_section_provider.dart';
import '../../providers/search_session_provider.dart';
import '../../theme/app_theme.dart';
import '../browse_rows_shimmer.dart';
import '../search_cards/browse_item_rows.dart';
import '../shelf_heading.dart';

/// Items a shelf shows when its source did not say.
const _defaultPreviewLimit = 5;

/// A catalog made of several shelves — one per entity kind it holds — each
/// filled by its own browse request.
///
/// The page shows this only while no kind is chosen; choosing one narrows the
/// catalog itself to a flat list, which is the same listing a shelf shows.
/// Shelves load independently, so a slow one never holds up the rest, and a
/// shelf that cannot honour the page's filter is not shown at all.
class CatalogSectionsView extends ConsumerWidget {
  final CatalogPage page;
  final BrowseFilterQuery query;

  /// The page banner and its active-filter chips, scrolling with the shelves.
  final Widget header;

  /// What stands under the header when the query leaves no shelf to show, or
  /// every shelf it reaches comes back with nothing.
  final Widget empty;

  /// Opens one shelf in full, by narrowing the page to that kind.
  final ValueChanged<SearchType> onViewAll;

  const CatalogSectionsView({
    super.key,
    required this.page,
    required this.query,
    required this.header,
    required this.empty,
    required this.onViewAll,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shelves = [
      for (final section in page.sections)
        if (_plan(section, query) case final shelf?) shelf,
    ];
    // Watched here rather than in each shelf, because an empty shelf folds
    // away: with every one empty the page would be a header over nothing.
    final previews = [
      for (final shelf in shelves)
        ref.watch(catalogSectionProvider(shelf.request)),
    ];
    final nothing = previews.every(
      (preview) => preview is AsyncData && preview.requireValue.items.isEmpty,
    );
    if (nothing) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          Expanded(child: empty),
        ],
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: shelves.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) return header;
        return _SectionShelf(
          shelf: shelves[index - 1],
          preview: previews[index - 1],
          onViewAll: onViewAll,
        );
      },
    );
  }
}

/// One shelf the page shows: its section, and what that shelf is asked.
typedef _ShelfPlan = ({
  BrowseItem section,
  Catalog catalog,
  CatalogSectionRequest request,
});

/// Null for a section that is no catalog, and for one the query would reach
/// only in part: a shelf that dropped a constraint would list unfiltered,
/// which reads as filtered and is not, so it stays off the page instead.
_ShelfPlan? _plan(BrowseItem section, BrowseFilterQuery query) {
  final catalog = section.catalog;
  if (catalog == null) return null;
  // Built from what this shelf declared, never the page's: a constraint the
  // shelf cannot honour is dropped here rather than refused by its source.
  final capabilities = BrowseFilterCapabilities.fromSpecs(
    catalog.filters,
    catalogId: section.id,
  );
  if (!query.isHonouredBy(capabilities)) return null;
  return (
    section: section,
    catalog: catalog,
    request: (
      id: section.id,
      filter: query.encoded(capabilities),
      limit: catalog.previewConfig?.itemsCount ?? _defaultPreviewLimit,
    ),
  );
}

class _SectionShelf extends StatelessWidget {
  final _ShelfPlan shelf;
  final AsyncValue<BrowseItemsList> preview;
  final ValueChanged<SearchType> onViewAll;

  const _SectionShelf({
    required this.shelf,
    required this.preview,
    required this.onViewAll,
  });

  @override
  Widget build(BuildContext context) {
    final section = shelf.section;
    final catalog = shelf.catalog;
    final title = section.name ?? catalog.title;
    final type = CatalogPage.typeOf(section);

    return preview.when(
      loading: () =>
          _Shelf(title: title, child: const BrowseRowsShimmer(count: 3)),
      // A shelf that failed says so in its own space; the rest of the page,
      // and the filters that could undo it, stay usable.
      error: (_, __) => _Shelf(
        title: title,
        child: Text(
          'Could not load',
          style: KalinkaTextStyles.trackRowSubtitle.copyWith(
            color: KalinkaColors.textMuted,
          ),
        ),
      ),
      data: (list) {
        if (list.items.isEmpty) return const SizedBox.shrink();
        final trackIds = <String>[
          for (final item in list.items)
            if (item.track != null) item.id,
        ];
        return _Shelf(
          title: title,
          count: list.total,
          onViewAll: type == null || list.total <= list.items.length
              ? null
              : () => onViewAll(type),
          child: BrowseItemRows(
            items: list.items,
            queueContextIds: trackIds.isEmpty ? null : trackIds,
          ),
        );
      },
    );
  }
}

/// One shelf: its heading, then whatever stands in for its items.
class _Shelf extends StatelessWidget {
  final String title;
  final int? count;
  final VoidCallback? onViewAll;
  final Widget child;

  const _Shelf({
    required this.title,
    required this.child,
    this.count,
    this.onViewAll,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ShelfHeading(
            title: title.toUpperCase(),
            count: count,
            onViewAll: onViewAll,
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}
