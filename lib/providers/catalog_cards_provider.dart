import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data_model/data_model.dart';

/// Opens a catalog page: which catalog, the source label to attribute it to,
/// and — for a listing entered by one of its rows — the row to land on.
typedef OpenCatalog = void Function(
  CatalogCardPlan plan,
  String provider, {
  String? focusItemId,
});

/// One advertisement card: a browsable category in a source's root catalog.
class CatalogCardPlan {
  final String id;
  final String title;
  final String? description;
  final int? totalDurationSeconds;
  final String sourceName;
  final PreviewContentType? contentType;

  /// Semantic icon id from the catalog's preview_config (e.g. "popular",
  /// "new_releases"); the card maps it to a glyph, falling back to contentType.
  final String? icon;

  /// What the catalog claims to be, as its source declared it.
  final CatalogRole? role;

  /// How the source asked for the catalog to be previewed.
  final Preview? preview;

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
    this.totalDurationSeconds,
    this.contentType,
    this.icon,
    this.role,
    this.preview,
    this.artPath,
    this.filters = const [],
    this.sections = const [],
    this.canEdit = false,
    this.folderLayout = false,
    this.canAdd = false,
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

/// Bumped when Home starts over on another server. As a watched dependency it
/// RELOADS Home's catalog providers — they drop to shimmer until fresh data
/// arrives — whereas invalidation-driven refetches (reconnect, a refresh) hold
/// the previous value, so Home never flickers mid-session.
class CatalogCardsReload extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state++;
}

final catalogCardsReloadProvider = NotifierProvider<CatalogCardsReload, int>(
  CatalogCardsReload.new,
);
