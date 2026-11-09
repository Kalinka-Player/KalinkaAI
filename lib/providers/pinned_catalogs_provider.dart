import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data_model/browse_filters.dart';
import '../data_model/data_model.dart';
import 'box_control_provider.dart';
import 'connection_settings_provider.dart';
import 'search_session_provider.dart';

enum HomePreviewType {
  automatic('Automatic', 'Choose a preview to suit the content'),
  // Keep the stored name "preview" compatible with existing prototype pins.
  preview(
    'Small preview',
    'Equal-sized album covers or a short list of tracks',
  ),
  large('Large preview', 'Large album cards or a featured catalogue collage'),
  cards('Cards', 'Horizontally scrolling covers'),
  artwork('Artwork', 'Catalog image, title and description'),
  list('List', 'Five items in a vertical list'),
  compact('Shortcut only', 'A small shortcut to the original destination');

  final String label;
  final String description;
  const HomePreviewType(this.label, this.description);

  static const choices = [automatic, preview, large, compact];
  bool get adaptive => this == automatic || this == preview || this == large;
  HomePreviewType get choice => choices.contains(this) ? this : automatic;
}

/// What Home can pin: a catalog, or an artist for their releases.
bool pinnableToHome(CatalogPage page) => page.isCatalog || page.isArtist;

/// A catalog and an exact filter selection, or an artist. Different
/// selections can be pinned independently; preview layout is a local
/// presentation preference.
class PinnedCatalog {
  final CatalogPage page;
  final BrowseFilterQuery filter;
  final HomePreviewType preview;
  final Map<String, String> genreNames;
  final String? homeName;

  const PinnedCatalog({
    required this.page,
    required this.filter,
    required this.preview,
    this.genreNames = const {},
    this.homeName,
  });

  String get title => homeName?.trim().isNotEmpty == true
      ? homeName!.trim()
      : page.title ?? 'Catalog';

  bool get shortcut =>
      preview == HomePreviewType.compact ||
      (preview == HomePreviewType.automatic &&
          page.preview?.type == PreviewType.none);

  /// A user choice can request the collage without changing source metadata.
  /// Single albums use large cards; non-album contents keep their ordered rows.
  bool get largePreview =>
      preview == HomePreviewType.large ||
      (preview == HomePreviewType.automatic &&
          page.preview?.cardSize == CardSize.large);

  String get key {
    final json = filter.toJson();
    for (final field in ['genreIds', 'sources']) {
      if (json[field] case final List<String> values) {
        json[field] = [...values]..sort();
      }
    }
    return '${page.id}|${jsonEncode(json)}';
  }

  PinnedCatalog withPreview(HomePreviewType value) => PinnedCatalog(
    page: page,
    filter: filter,
    preview: value,
    genreNames: genreNames,
    homeName: homeName,
  );

  PinnedCatalog withHomeName(String? value) => PinnedCatalog(
    page: page,
    filter: filter,
    preview: preview,
    genreNames: genreNames,
    homeName: value?.trim().isEmpty == true ? null : value?.trim(),
  );

  String get description => [
    if (page.provider?.isNotEmpty == true) page.provider!,
    if (filterDescription.isNotEmpty) filterDescription,
  ].join(' · ');

  String get filterDescription => [
    if (filter.text.isNotEmpty) '“${filter.text}”',
    if (filter.genreIds.isNotEmpty)
      filter.genreIds.map((id) => genreNames[id] ?? id).join(', '),
    if (filter.type != null) filter.type!.name,
  ].join(' · ');

  Map<String, dynamic> toJson() => {
    'page': page.toJson(),
    'filter': filter.toJson(),
    'preview': preview.name,
    'previewVersion': 3,
    if (homeName != null) 'homeName': homeName,
    'genreNames': genreNames,
  };

  factory PinnedCatalog.fromJson(Map<String, dynamic> json) => PinnedCatalog(
    page: CatalogPage.fromJson(Map<String, dynamic>.from(json['page'] as Map)),
    filter: BrowseFilterQuery.fromJson(
      Map<String, dynamic>.from(json['filter'] as Map),
    ),
    genreNames: Map<String, String>.from(json['genreNames'] as Map? ?? {}),
    homeName: json['homeName'] as String?,
    // Existing folder pins gain album recognition. Explicit compact choices
    // remain shortcuts; destinations, filters and order are unchanged.
    preview: json['previewVersion'] != 3
        ? json['preview'] == 'compact'
              ? HomePreviewType.compact
              : HomePreviewType.automatic
        : HomePreviewType.values.asNameMap()[json['preview']] ??
              HomePreviewType.automatic,
  );
}

/// Home's pins for the connected server; null until it is known which server
/// that is, so one server's pins never show on another. Changed only once the
/// server has said so on this connection.
class PinnedCatalogsNotifier extends Notifier<List<PinnedCatalog>?> {
  Future<void> _writes = Future.value();
  ServerStorageKey? _key;

  @override
  List<PinnedCatalog>? build() {
    final key = _key = ref.watch(serverStorageKeyProvider);
    if (key == null) return null;
    final raw = ref.read(sharedPrefsProvider).getString(key.pinnedCatalogs);
    if (raw == null) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      final pins = <PinnedCatalog>[];
      final seen = <String>{};
      for (final json in decoded) {
        try {
          final pin = PinnedCatalog.fromJson(
            Map<String, dynamic>.from(json as Map),
          );
          if (pinnableToHome(pin.page) && seen.add(pin.key)) {
            pins.add(pin);
          }
        } catch (_) {
          // One stale entry must not discard the user's remaining pins.
        }
      }
      return List.unmodifiable(pins);
    } catch (_) {
      return const [];
    }
  }

  /// The pins, while the server has said on this connection that they are its.
  List<PinnedCatalog>? get _editable {
    // Read first: it rebuilds with the current key if that has changed.
    final pins = state;
    return _key?.confirmed == true ? pins : null;
  }

  /// No change is kept before the server has answered: it could be another's.
  Future<void> _serverNotKnown() =>
      Future.error(StateError('The server has not said who it is'));

  Future<void> pin(PinnedCatalog pin) {
    if (!pinnableToHome(pin.page)) {
      throw ArgumentError('Only catalogs and artists can be pinned');
    }
    final pins = _editable;
    if (pins == null) return _serverNotKnown();
    if (pins.any((p) => p.key == pin.key)) return Future.value();
    return _save([...pins, pin]);
  }

  Future<void> unpin(String key) {
    final pins = _editable;
    if (pins == null) return _serverNotKnown();
    return _save([
      for (final pin in pins)
        if (pin.key != key) pin,
    ]);
  }

  Future<void> setPreview(String key, HomePreviewType type) {
    final pins = _editable;
    if (pins == null) return _serverNotKnown();
    return _save([
      for (final pin in pins) pin.key == key ? pin.withPreview(type) : pin,
    ]);
  }

  Future<void> setHomeName(String key, String? name) {
    final pins = _editable;
    if (pins == null) return _serverNotKnown();
    return _save([
      for (final pin in pins) pin.key == key ? pin.withHomeName(name) : pin,
    ]);
  }

  /// Uses ReorderableListView's insertion index convention.
  Future<void> reorder(int oldIndex, int newIndex) {
    final pins = _editable;
    if (pins == null) return _serverNotKnown();
    if (oldIndex < 0 ||
        oldIndex >= pins.length ||
        newIndex < 0 ||
        newIndex > pins.length) {
      return Future.value();
    }
    final next = [...pins];
    if (newIndex > oldIndex) newIndex--;
    next.insert(newIndex, next.removeAt(oldIndex));
    return _save(next);
  }

  Future<void> _save(List<PinnedCatalog> next) {
    final previous = state;
    final key = _key!;
    final prefs = ref.read(sharedPrefsProvider);
    state = List.unmodifiable(next);
    final optimistic = state;
    final payload = jsonEncode(next.map((p) => p.toJson()).toList());
    final write = _writes.then((_) async {
      if (!await prefs.setString(key.pinnedCatalogs, payload)) {
        throw StateError('Could not save Home');
      }
    });
    _writes = write.catchError((Object _) {});
    return write.catchError((Object error, StackTrace stack) {
      if (ref.mounted && _key == key && identical(state, optimistic)) {
        state = previous;
      }
      Error.throwWithStackTrace(error, stack);
    });
  }
}

final pinnedCatalogsProvider =
    NotifierProvider<PinnedCatalogsNotifier, List<PinnedCatalog>?>(
      PinnedCatalogsNotifier.new,
    );

/// A few shortcuts retain the search-led landing, with their tiles underneath.
final homeHasPreviewsProvider = Provider<bool>((ref) {
  final pins = ref.watch(pinnedCatalogsProvider);
  return pins != null &&
      pins.isNotEmpty &&
      (pins.length > 4 || pins.any((pin) => !pin.shortcut));
});
