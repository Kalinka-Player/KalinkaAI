import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data_model/browse_filters.dart';
import '../../providers/artist_relations_provider.dart';
import '../../providers/pinned_catalogs_provider.dart';
import '../../providers/box_control_provider.dart';
import '../../providers/browse_genres_provider.dart';
import '../../providers/source_modules_provider.dart';
import '../../providers/search_session_provider.dart';

Future<void> saveHomeChange(BuildContext context, Future<void> change) async {
  try {
    await change;
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save Home. Please try again.')),
      );
    }
  }
}

class CatalogPinButton extends ConsumerWidget {
  final CatalogPage page;
  final BrowseFilterQuery filter;

  const CatalogPinButton({super.key, required this.page, required this.filter});

  /// Centred in the button's 48dp target.
  static const iconSize = 20.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!pinnableToHome(page) ||
        ref.watch(builtinSourcesProvider).contains(sourceOfId(page.id!))) {
      return const SizedBox.shrink();
    }
    final kind = page.isArtist ? 'artist' : 'catalog';
    final vocabulary = page.filterCapabilities.genreVocabulary;
    final genres = vocabulary == null || filter.genreIds.isEmpty
        ? null
        : ref.watch(browseGenresProvider(vocabulary)).value;
    // The portrait the artist's header shows, where the page came without
    // one, for Home's Artwork preview.
    final portrait = page.isArtist && page.artPath == null
        ? imagePathOf(page.item?.image) ??
              ref.watch(artistPortraitProvider(page.id!)).value
        : null;
    final candidate = PinnedCatalog(
      page: portrait == null
          ? page
          : CatalogPage.fromJson({...page.toJson(), 'artPath': portrait}),
      filter: filter.fittedTo(page.filterCapabilities),
      preview: HomePreviewType.automatic,
      genreNames: {for (final genre in genres ?? []) genre.id: genre.name},
    );
    final pins = ref.watch(pinnedCatalogsProvider);
    final pinned = pins?.any((pin) => pin.key == candidate.key) ?? false;
    final confirmed = ref.watch(
      serverStorageKeyProvider.select((key) => key?.confirmed ?? false),
    );
    Future<void> toggle() async {
      final notifier = ref.read(pinnedCatalogsProvider.notifier);
      await saveHomeChange(
        context,
        pinned ? notifier.unpin(candidate.key) : notifier.pin(candidate),
      );
    }

    return IconButton(
      tooltip: pinned ? 'Unpin $kind' : 'Pin $kind to Home',
      iconSize: iconSize,
      constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
      isSelected: pinned,
      icon: const Icon(CupertinoIcons.pin),
      selectedIcon: const Icon(CupertinoIcons.pin_slash),
      onPressed: confirmed ? toggle : null,
    );
  }
}
