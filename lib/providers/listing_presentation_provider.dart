import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data_model/data_model.dart';
import 'connection_settings_provider.dart';

const _presentationKey = 'Kalinka.listingPresentation';

/// How a listing of one kind of item is laid out: artwork in a grid, or rows.
enum ListingPresentation { grid, list }

/// Listings whose Grid/List choice is remembered together. A choice made on
/// one album catalog holds for every album catalog; filters and Home previews
/// keep their own settings.
enum ListingFamily {
  albums(ListingPresentation.grid),
  artists(ListingPresentation.grid),
  playlists(ListingPresentation.list);

  final ListingPresentation byDefault;

  const ListingFamily(this.byDefault);

  /// The family a listing of [kind] belongs to; null for mixed or unknown
  /// listings, which keep their rows.
  static ListingFamily? of(PreviewContentType? kind) => switch (kind) {
    PreviewContentType.album => albums,
    PreviewContentType.artist => artists,
    PreviewContentType.playlist => playlists,
    _ => null,
  };
}

/// The device's Grid/List choice per [ListingFamily].
class ListingPresentationNotifier
    extends Notifier<Map<ListingFamily, ListingPresentation>> {
  late SharedPreferences _prefs;

  @override
  Map<ListingFamily, ListingPresentation> build() {
    _prefs = ref.read(sharedPrefsProvider);
    final json = _prefs.getString(_presentationKey);
    if (json == null) return const {};
    try {
      final decoded = jsonDecode(json) as Map<String, dynamic>;
      return {
        for (final family in ListingFamily.values)
          family: ?ListingPresentation.values.asNameMap()[decoded[family.name]],
      };
    } catch (_) {
      return const {};
    }
  }

  ListingPresentation of(ListingFamily family) =>
      state[family] ?? family.byDefault;

  void set(ListingFamily family, ListingPresentation presentation) {
    if (of(family) == presentation) return;
    state = {...state, family: presentation};
    _prefs.setString(
      _presentationKey,
      jsonEncode({
        for (final MapEntry(:key, :value) in state.entries)
          key.name: value.name,
      }),
    );
  }
}

final listingPresentationProvider =
    NotifierProvider<
      ListingPresentationNotifier,
      Map<ListingFamily, ListingPresentation>
    >(ListingPresentationNotifier.new);
