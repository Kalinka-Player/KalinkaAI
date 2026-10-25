import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data_model/browse_filters.dart';
import 'box_control_provider.dart';
import 'connection_settings_provider.dart';
import 'search_session_provider.dart';

enum HomePreviewType {
  cards('Cards', 'Horizontally scrolling covers'),
  artwork('Artwork', 'Catalog image, title and description'),
  list('List', 'Five items in a vertical list'),
  compact('Compact', 'Small tile in the source colour');

  final String label;
  final String description;
  const HomePreviewType(this.label, this.description);
}

/// A catalog and an exact filter selection. Different selections can be pinned
/// independently; preview layout is a local presentation preference.
class PinnedCatalog {
  final CatalogPage page;
  final BrowseFilterQuery filter;
  final HomePreviewType preview;
  final Map<String, String> genreNames;

  const PinnedCatalog({
    required this.page,
    required this.filter,
    required this.preview,
    this.genreNames = const {},
  });

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
    'previewVersion': 2,
    'genreNames': genreNames,
  };

  factory PinnedCatalog.fromJson(Map<String, dynamic> json) => PinnedCatalog(
    page: CatalogPage.fromJson(Map<String, dynamic>.from(json['page'] as Map)),
    filter: BrowseFilterQuery.fromJson(
      Map<String, dynamic>.from(json['filter'] as Map),
    ),
    genreNames: Map<String, String>.from(json['genreNames'] as Map? ?? {}),
    preview: json['previewVersion'] == null
        ? switch (json['preview']) {
            // The original Artwork mode rendered a horizontal item rail.
            'artwork' => HomePreviewType.cards,
            'compact' => HomePreviewType.compact,
            _ => HomePreviewType.list,
          }
        : HomePreviewType.values.asNameMap()[json['preview']] ??
              HomePreviewType.list,
  );
}

/// Home's pins for the connected server; null until the server has said who
/// it is, so one server's pins never show on another.
class PinnedCatalogsNotifier extends Notifier<List<PinnedCatalog>?> {
  Future<void> _writes = Future.value();
  ServerStorageKey? _key;

  @override
  List<PinnedCatalog>? build() {
    final key = _key = ref.watch(serverStorageKeyProvider);
    if (key == null) return null;
    final prefs = ref.read(sharedPrefsProvider);
    final raw =
        prefs.getString(key.pinnedCatalogs) ?? _adoptAddressPins(prefs, key);
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
          if (pin.page.isCatalog && seen.add(pin.key)) pins.add(pin);
        } catch (_) {
          // One stale entry must not discard the user's remaining pins.
        }
      }
      return List.unmodifiable(pins);
    } catch (_) {
      return const [];
    }
  }

  /// The pins kept under this address before servers were told apart by id,
  /// moved to [key] the first time the server here is known.
  String? _adoptAddressPins(SharedPreferences prefs, ServerStorageKey key) {
    if (!key.isServerId) return null;
    return moveStoredString(
      prefs,
      from: ServerStorageKey.ofAddress(
        ref.read(connectionSettingsProvider).baseUrl,
      ).pinnedCatalogs,
      to: key.pinnedCatalogs,
    );
  }

  /// No change is kept before the server is known: it could be another's.
  Future<void> _serverNotKnown() =>
      Future.error(StateError('The server is not known yet'));

  Future<void> pin(PinnedCatalog pin) {
    if (!pin.page.isCatalog) {
      throw ArgumentError('Only catalogs can be pinned');
    }
    final pins = state;
    if (pins == null) return _serverNotKnown();
    if (pins.any((p) => p.key == pin.key)) return Future.value();
    return _save([...pins, pin]);
  }

  Future<void> unpin(String key) {
    final pins = state;
    if (pins == null) return _serverNotKnown();
    return _save([
      for (final pin in pins)
        if (pin.key != key) pin,
    ]);
  }

  Future<void> setPreview(String key, HomePreviewType type) {
    final pins = state;
    if (pins == null) return _serverNotKnown();
    return _save([
      for (final pin in pins) pin.key == key ? pin.withPreview(type) : pin,
    ]);
  }

  /// Uses ReorderableListView's insertion index convention.
  Future<void> reorder(int oldIndex, int newIndex) {
    final pins = state;
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
