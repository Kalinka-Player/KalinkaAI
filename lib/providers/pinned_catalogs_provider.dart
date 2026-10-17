import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data_model/browse_filters.dart';
import 'connection_settings_provider.dart';
import 'search_session_provider.dart';

enum HomePreviewType {
  cards('Cards', 'Horizontally scrolling cards'),
  artwork('Artwork', 'Catalog artwork with its title and description'),
  list('List', 'Five items in a vertical list'),
  compact('Compact', 'Small tile tinted with the source colour');

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

class PinnedCatalogsNotifier extends Notifier<List<PinnedCatalog>> {
  Future<void> _writes = Future.value();
  late String _key;

  @override
  List<PinnedCatalog> build() {
    final server = ref.watch(
      connectionSettingsProvider.select((s) => s.baseUrl),
    );
    _key = 'Kalinka.pinnedCatalogs.v1:$server';
    final raw = ref.read(sharedPrefsProvider).getString(_key);
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

  Future<void> pin(PinnedCatalog pin) {
    if (!pin.page.isCatalog) {
      throw ArgumentError('Only catalogs can be pinned');
    }
    if (state.any((p) => p.key == pin.key)) return Future.value();
    return _save([...state, pin]);
  }

  Future<void> unpin(String key) => _save([
    for (final pin in state)
      if (pin.key != key) pin,
  ]);

  Future<void> setPreview(String key, HomePreviewType type) => _save([
    for (final pin in state) pin.key == key ? pin.withPreview(type) : pin,
  ]);

  /// Uses ReorderableListView's insertion index convention.
  Future<void> reorder(int oldIndex, int newIndex) {
    if (oldIndex < 0 ||
        oldIndex >= state.length ||
        newIndex < 0 ||
        newIndex > state.length) {
      return Future.value();
    }
    final next = [...state];
    if (newIndex > oldIndex) newIndex--;
    next.insert(newIndex, next.removeAt(oldIndex));
    return _save(next);
  }

  Future<void> _save(List<PinnedCatalog> next) {
    final previous = state;
    final key = _key;
    final prefs = ref.read(sharedPrefsProvider);
    state = List.unmodifiable(next);
    final optimistic = state;
    final payload = jsonEncode(next.map((p) => p.toJson()).toList());
    final write = _writes.then((_) async {
      if (!await prefs.setString(key, payload)) {
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
    NotifierProvider<PinnedCatalogsNotifier, List<PinnedCatalog>>(
      PinnedCatalogsNotifier.new,
    );

/// Whether the "Pin catalogs to Home" hint was dismissed. Per install, not
/// per server: once learnt, pinning needs no second introduction.
class PinHintDismissedNotifier extends Notifier<bool> {
  static const _key = 'Kalinka.pinHintDismissed';

  @override
  bool build() => ref.read(sharedPrefsProvider).getBool(_key) ?? false;

  void dismiss() {
    state = true;
    ref.read(sharedPrefsProvider).setBool(_key, true).ignore();
  }
}

final pinHintDismissedProvider =
    NotifierProvider<PinHintDismissedNotifier, bool>(
      PinHintDismissedNotifier.new,
    );
