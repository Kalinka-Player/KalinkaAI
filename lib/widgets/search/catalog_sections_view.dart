import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data_model/browse_filters.dart';
import '../../data_model/data_model.dart';
import '../../providers/catalog_section_provider.dart';
import '../../providers/search_session_provider.dart';
import '../../theme/app_theme.dart';
import '../browse_rows_shimmer.dart';
import '../home/preview_shelf.dart';
import '../search_cards/browse_item_rows.dart';
import '../search_cards/browse_navigation_scope.dart';
import '../shelf_heading.dart';
import 'browse_visit_scope.dart';

/// Items a shelf shows when its source did not say.
const _defaultPreviewLimit = 5;

/// How many tracks a shelf of them lists before View All.
const _trackPreviewLimit = 5;

/// The fewest covers a rail of them asks for: it scrolls, and builds only
/// the cards in view.
const _coverPreviewLimit = 12;

/// Albums, artists and playlists, which a shelf shows as covers.
bool _coverKind(BrowseType type) =>
    type == BrowseType.album ||
    type == BrowseType.artist ||
    type == BrowseType.playlist;

/// Whether a shelf of [catalog] shows covers on a sideways rail, as a pinned
/// Cards preview does, rather than rows: by what it holds, whatever layout
/// its source suggests. Where the catalog does not say, its first item does;
/// null until that has loaded.
bool? _coverShelf(Catalog catalog, [List<BrowseItem>? items]) =>
    switch (catalog.previewConfig?.contentType) {
      PreviewContentType.album ||
      PreviewContentType.artist ||
      PreviewContentType.playlist => true,
      PreviewContentType.track || PreviewContentType.catalog => false,
      _ =>
        items == null || items.isEmpty
            ? null
            : _coverKind(items.first.browseType),
    };

/// How many rows a shelf shows: what its source asked for, tracks at most
/// [_trackPreviewLimit].
int _rowLimit(Catalog catalog, [List<BrowseItem>? items]) {
  final asked = catalog.previewConfig?.itemsCount ?? _defaultPreviewLimit;
  final declared = catalog.previewConfig?.contentType;
  final tracks =
      declared == PreviewContentType.track ||
      ((declared == null || declared == PreviewContentType.unknown) &&
          items != null &&
          items.isNotEmpty &&
          items.first.browseType == BrowseType.track);
  return tracks ? math.min(asked, _trackPreviewLimit) : asked;
}

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

  /// Content below the pinned header, scrolling with the shelves.
  final Widget header;
  final Widget? sliverHeader;

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
    this.sliverHeader,
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
      ?_plan(section, widget.query, widget.revision),
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
    if (widget.sliverHeader != null) {
      final empty = shelves.every((shelf) => _empty.contains(shelf.request));
      return CustomScrollView(
        slivers: [
          widget.sliverHeader!,
          SliverToBoxAdapter(child: widget.header),
          SliverPadding(
            padding: const EdgeInsets.only(bottom: 24),
            sliver: empty
                ? SliverToBoxAdapter(child: widget.empty)
                : SliverList.builder(
                    itemCount: shelves.length,
                    itemBuilder: (context, index) => _SectionShelf(
                      shelf: shelves[index],
                      onViewAll: widget.onViewAll,
                      onEmpty: _reportEmpty,
                    ),
                  ),
          ),
        ],
      );
    }
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
      // Enough for a rail wherever it may be one; rows are trimmed to their
      // own limit once loaded.
      limit: _coverShelf(catalog) == false
          ? _rowLimit(catalog)
          : math.max(_rowLimit(catalog), _coverPreviewLimit),
      revision: revision,
    ),
  );
}

/// A page's shelves stacked in place, for a page whose own listing follows
/// them in the same scroll. An empty shelf takes no room; none offers View
/// all, which would narrow a listing these shelves are not.
class SectionShelves extends StatelessWidget {
  final List<BrowseItem> sections;

  const SectionShelves({super.key, required this.sections});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final section in sections)
          if (_plan(section, const BrowseFilterQuery(), 0) case final shelf?)
            _SectionShelf(shelf: shelf, onViewAll: null, onEmpty: (_) {}),
      ],
    );
  }
}

class _SectionShelf extends ConsumerWidget {
  final _ShelfPlan shelf;
  final ValueChanged<SearchType>? onViewAll;
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
    final navigation = BrowseNavigationScope.maybeOf(context);
    final visit = visitOf(context, ref);
    void openSection() {
      final page = CatalogPage.fromItem(
        section,
        provider: visit.catalogPage.provider,
      );
      final filter = visit.catalogFilter.fittedTo(page.filterCapabilities);
      ref.read(searchSessionProvider.notifier).openPage(page, filter: filter);
    }

    Preview covers(int count) => Preview(
      type: PreviewType.imageText,
      itemsCount: count,
      cardSize: catalog.previewConfig?.cardSize,
    );

    return preview.when(
      loading: () => _Shelf(
        title: title,
        // A shelf that does not say what it holds waits on a spinner rather
        // than shimmer in a shape it may not take.
        child: switch (_coverShelf(catalog)) {
          true => PreviewShelfShimmer(preview: covers(shelf.request.limit)),
          false => const BrowseRowsShimmer(count: 3),
          null => const LoadingSpinner(),
        },
      ),
      // A shelf that failed says so in its own space; the rest of the page,
      // and the filters that could undo it, stay usable.
      error: (_, _) => _Shelf(
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
        final cover = _coverShelf(catalog, list.items) ?? false;
        // Rows are a short list; View All has the rest.
        final shown = cover
            ? list.items
            : list.items.take(_rowLimit(catalog, list.items)).toList();
        final trackIds = <String>[
          for (final item in shown)
            if (item.track != null) item.id,
        ];
        return _Shelf(
          title: title,
          count: list.total,
          onViewAll: navigation != null && section.canBrowse
              ? openSection
              : type == null || onViewAll == null || list.total <= shown.length
              ? null
              : () => onViewAll!(type),
          child: cover
              ? PreviewShelf(
                  items: shown,
                  preview: covers(shown.length),
                  storageId: section.id,
                  onOpenItem: (item) => openBrowsable(context, ref, item),
                )
              : BrowseItemRows(
                  items: shown,
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
      padding: const EdgeInsets.fromLTRB(16, 21, 16, 0),
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
