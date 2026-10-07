import 'dart:async' show Timer;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data_model/data_model.dart';
import 'kalinka_player_api_provider.dart';
import 'source_modules_provider.dart';

const _kRefreshInterval = Duration(hours: 12);

// Server art is generated lazily, so the first browse after a cold cache has no
// art yet. Re-fetch a bounded number of times to pick it up, then fall back to
// the slow refresh.
const _kArtPollInterval = Duration(seconds: 4);
const _kMaxArtPolls = 8;

const _kMaxCardsPerSource = 8;

// `_pollDriven` tells a self-scheduled poll apart from a fresh invalidation
// (start/reconnect/refresh) so the attempt counter resets on the latter.
int _artPolls = 0;
bool _pollDriven = false;

/// Opens a catalog page: which catalog, the source label to attribute it to,
/// and — for a listing entered by one of its rows — the row to land on.
typedef OpenCatalog =
    void Function(CatalogCardPlan plan, String provider, {String? focusItemId});

/// One advertisement card: a browsable category in a source's root catalog.
class CatalogCardPlan {
  final String id;
  final String title;
  final String? description;
  final String sourceName;
  final PreviewContentType? contentType;

  /// Semantic icon id from the catalog's preview_config (e.g. "popular",
  /// "new_releases"); the card maps it to a glyph, falling back to contentType.
  final String? icon;

  /// Unresolved background path (resolved against the base URL at render time).
  /// Null until the server has generated the art; the card is black until then.
  final String? artPath;

  /// What the shelf behind this card can be filtered by, as its source
  /// declared it. Carried from here into the page so the page never has to
  /// guess what its source supports.
  final List<FilterSpec> filters;

  /// The shelves behind this card, when its catalog is made of several — one
  /// per entity kind. Carried from here into the page, so opening the card
  /// costs no extra round trip to learn what it holds.
  final List<BrowseItem> sections;

  /// The server takes writes that change what this catalog holds, as the
  /// shelf itself claimed. Carried into the page, which is where the actions
  /// that make those writes live.
  final bool canEdit;

  /// The catalog is a folder of a file-backed source, browsed under a
  /// breadcrumb rather than as rows.
  final bool folderLayout;

  /// Adding the catalog's id to the queue adds tracks.
  final bool canAdd;

  const CatalogCardPlan({
    required this.id,
    required this.title,
    required this.sourceName,
    this.description,
    this.contentType,
    this.icon,
    this.artPath,
    this.filters = const [],
    this.sections = const [],
    this.canEdit = false,
    this.folderLayout = false,
    this.canAdd = false,
  });
}

/// All planned cards for one input source, in backend order.
class CatalogCardGroup {
  final String sourceName;
  final String sourceTitle;
  final List<CatalogCardPlan> cards;

  /// Whether this source offers the user's own content, as it claimed with
  /// [CatalogRole.library]. Orders the groups; see [catalogCardGroupsProvider].
  final bool ownLibrary;

  const CatalogCardGroup({
    required this.sourceName,
    required this.sourceTitle,
    required this.cards,
    this.ownLibrary = false,
  });
}

/// The server-rendered art behind [item], unresolved, or null until the
/// server has produced it.
String? artPathOf(BrowseItem item) {
  final image = item.catalog?.image;
  if (image == null) return null;
  final path = image.large ?? image.small ?? image.thumbnail;
  return (path != null && path.isNotEmpty) ? path : null;
}

/// Bumped on each Find Music open. As a watched dependency it RELOADS the
/// cards provider — the grid drops to shimmer until fresh plans arrive —
/// whereas invalidation-driven refetches (art polls, reconnect) are REFRESHES
/// that hold the previous cards, so the grid never flickers mid-session.
class CatalogCardsReload extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state++;
}

final catalogCardsReloadProvider = NotifierProvider<CatalogCardsReload, int>(
  CatalogCardsReload.new,
);

/// The card plans, grouped by source, each carrying its background URL from the
/// browse response — the whole payload the cards need, no second per-card fetch.
final catalogCardGroupsProvider = FutureProvider<List<CatalogCardGroup>>((
  ref,
) async {
  ref.watch(catalogCardsReloadProvider);
  if (!_pollDriven) _artPolls = 0;
  _pollDriven = false;

  // The server's own sources hold the user's own lists; those are shown as
  // such above, not offered here as catalogs to explore.
  final builtin = ref.watch(builtinSourcesProvider);

  final api = ref.read(kalinkaProxyProvider);
  final root = await api.browse('', limit: 20);

  final groups = <CatalogCardGroup>[];
  for (final module in root.items) {
    if (!module.canBrowse) continue;

    final sourceName =
        sourceOfId(module.id) ?? module.name?.toLowerCase() ?? '';
    if (sourceName.isEmpty || builtin.contains(sourceName)) continue;

    final children = await api.browse(module.id, limit: 20);
    final cards = <CatalogCardPlan>[];
    var ownLibrary = false;
    for (final item in children.items) {
      final catalog = item.catalog;
      if (catalog == null || !item.canBrowse) continue;
      if (catalog.role == CatalogRole.hideOnHome) continue;
      if (catalog.role == CatalogRole.library) ownLibrary = true;

      cards.add(
        CatalogCardPlan(
          id: item.id,
          title: item.name ?? catalog.title,
          description: catalog.description ?? item.subname,
          sourceName: sourceName,
          contentType: catalog.previewConfig?.contentType,
          icon: catalog.previewConfig?.icon,
          artPath: artPathOf(item),
          filters: catalog.filters,
          sections: item.sections ?? const [],
          folderLayout: item.browseType == BrowseType.folder,
          canAdd: item.canAdd,
        ),
      );
      if (cards.length >= _kMaxCardsPerSource) break;
    }

    if (cards.isNotEmpty) {
      groups.add(
        CatalogCardGroup(
          sourceName: sourceName,
          sourceTitle: module.name ?? sourceName,
          cards: cards,
          ownLibrary: ownLibrary,
        ),
      );
    }
  }

  // Your own music first, then everything else by name. The server lists
  // sources alphabetically by their internal key, which buries the local
  // library under whatever sorts before it. Which source that is comes from
  // the source's own CatalogRole.library claim, so no source is named here.
  groups.sort((a, b) {
    if (a.ownLibrary != b.ownLibrary) return a.ownLibrary ? -1 : 1;
    return a.sourceTitle.toLowerCase().compareTo(b.sourceTitle.toLowerCase());
  });

  final missingArt = groups.any(
    (group) => group.cards.any((card) => card.artPath == null),
  );
  final Duration delay;
  if (missingArt && _artPolls < _kMaxArtPolls) {
    _artPolls++;
    _pollDriven = true;
    delay = _kArtPollInterval;
  } else {
    delay = _kRefreshInterval;
  }
  final timer = Timer(delay, ref.invalidateSelf);
  ref.onDispose(timer.cancel);

  return groups;
});
