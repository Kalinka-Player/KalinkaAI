import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data_model/data_model.dart';
import 'connection_settings_provider.dart';

const _presentationKey = 'Kalinka.listingPresentation.v2';

/// Where choices were kept per kind of item, before each listing had its own.
const _familyPresentationKey = 'Kalinka.listingPresentation';

/// How many listings' choices are kept; the least recently changed go first.
const _remembered = 200;

/// How a listing is laid out: artwork in a grid, or rows.
enum ListingPresentation { grid, list }

/// A listing that can be laid out either way, by the browse item it is.
class ListingLayout {
  /// The browse item the listing is, under which a choice is kept.
  final String id;

  /// What its items are, as its catalog declares; null when it does not.
  final PreviewContentType? contentType;

  /// How it is laid out until a choice is made for it on this device.
  final ListingPresentation byDefault;

  /// The shape of its items' art, as its catalog declares; null when it does
  /// not. Each item's own image decides its card; this sizes the columns.
  final double? itemAspectRatio;

  const ListingLayout(
    this.id, {
    this.contentType,
    required this.byDefault,
    this.itemAspectRatio,
  });

  /// From the preview its catalog declares: image cards and carousels open as
  /// a grid, anything else as rows. Null for a listing of tracks, which only
  /// rows show.
  static ListingLayout? of(String id, Preview? preview) {
    final contentType = preview?.contentType;
    if (contentType == PreviewContentType.track) return null;
    return ListingLayout(
      id,
      contentType: contentType,
      byDefault: switch (preview?.type) {
        PreviewType.imageText ||
        PreviewType.carousel => ListingPresentation.grid,
        _ => ListingPresentation.list,
      },
      itemAspectRatio: validAspectRatio(preview?.aspectRatio),
    );
  }
}

/// The device's Grid/List choice per listing, by browse item id.
class ListingPresentationNotifier
    extends Notifier<Map<String, ListingPresentation>> {
  late SharedPreferences _prefs;

  @override
  Map<String, ListingPresentation> build() {
    _prefs = ref.read(sharedPrefsProvider);
    _prefs.remove(_familyPresentationKey);
    final json = _prefs.getString(_presentationKey);
    if (json == null) return const {};
    try {
      final decoded = jsonDecode(json) as Map<String, dynamic>;
      final names = ListingPresentation.values.asNameMap();
      return {
        for (final MapEntry(:key, :value) in decoded.entries)
          key: ?names[value],
      };
    } catch (_) {
      return const {};
    }
  }

  void set(ListingLayout layout, ListingPresentation presentation) {
    if (state[layout.id] == presentation) return;
    // Re-inserted, so the most recently changed are the ones kept.
    final next = {...state}..remove(layout.id);
    next[layout.id] = presentation;
    while (next.length > _remembered) {
      next.remove(next.keys.first);
    }
    state = next;
    _prefs.setString(
      _presentationKey,
      jsonEncode({
        for (final MapEntry(:key, :value) in next.entries) key: value.name,
      }),
    );
  }
}

final listingPresentationProvider =
    NotifierProvider<
      ListingPresentationNotifier,
      Map<String, ListingPresentation>
    >(ListingPresentationNotifier.new);

/// How [layout] is laid out now, rebuilding only when its own choice changes.
ListingPresentation watchPresentation(WidgetRef ref, ListingLayout layout) =>
    ref.watch(listingPresentationProvider.select((m) => m[layout.id])) ??
    layout.byDefault;
