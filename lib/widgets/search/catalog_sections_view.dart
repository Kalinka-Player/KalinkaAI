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
class CatalogSectionsView extends StatefulWidget {
  final CatalogPage page;
  final BrowseFilterQuery query;

  /// Refetches shelves after a collection changes.
  final int revision;

  /// The page banner and its active-filter chips, scrolling with the shelves.
  final Widget header;

  /// Shown when all eligible shelves are empty.
  final Widget empty;

  /// Opens one shelf in full, by narrowing the page to that kind.
  final ValueChanged<SearchType> onViewAll;

  const CatalogSectionsView({
    super.key,
    required this.page,
    required this.query,
    required this.revision,
    required this.header,
    required this.empty,
    required this.onViewAll,
  });

  @override
  State<CatalogSectionsView> createState() => _CatalogSectionsViewState();
}

class _CatalogSectionsViewState extends State<CatalogSectionsView> {
  // Empty shelves take no height, so later shelves load until one has rows
  // or all have reported empty.
  final _empty = <CatalogSectionRequest>{};

  late List<_ShelfPlan> _shelves = _planShelves();

  List<_ShelfPlan> _planShelves() => [
    for (final section in widget.page.sections)
      if (_plan(section, widget.query, widget.revision) case final shelf?)
        shelf,
  ];

  @override
  void didUpdateWidget(CatalogSectionsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.page == oldWidget.page &&
        widget.revision == oldWidget.revision &&
        widget.query.facetsChangedFrom(oldWidget.query).isEmpty) {
      return;
    }
    _shelves = _planShelves();
    _empty.retainAll({for (final shelf in _shelves) shelf.request});
  }

  void _reportEmpty(CatalogSectionRequest request) {
    if (mounted && !_empty.contains(request)) {
      setState(() => _empty.add(request));
    }
  }

  @override
  Widget build(BuildContext context) {
    final shelves = _shelves;
    if (shelves.every((shelf) => _empty.contains(shelf.request))) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          widget.header,
          Expanded(child: widget.empty),
        ],
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: shelves.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) return widget.header;
        return _SectionShelf(
          shelf: shelves[index - 1],
          onViewAll: widget.onViewAll,
          onEmpty: _reportEmpty,
        );
      },
    );
  }
}

typedef _ShelfPlan = ({
  BrowseItem section,
  Catalog catalog,
  CatalogSectionRequest request,
});

/// Null for a section that is no catalog, and for one the query would reach
/// only in part: a shelf that dropped a constraint would list unfiltered,
/// which reads as filtered and is not, so it stays off the page instead.
_ShelfPlan? _plan(BrowseItem section, BrowseFilterQuery query, int revision) {
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
      revision: revision,
    ),
  );
}

class _SectionShelf extends ConsumerWidget {
  final _ShelfPlan shelf;
  final ValueChanged<SearchType> onViewAll;
  final ValueChanged<CatalogSectionRequest> onEmpty;

  const _SectionShelf({
    required this.shelf,
    required this.onViewAll,
    required this.onEmpty,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preview = ref.watch(catalogSectionProvider(shelf.request));
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
        if (list.items.isEmpty) {
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => onEmpty(shelf.request),
          );
          return const SizedBox.shrink();
        }
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
