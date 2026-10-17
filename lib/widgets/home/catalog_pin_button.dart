import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data_model/browse_filters.dart';
import '../../providers/pinned_catalogs_provider.dart';
import '../../providers/browse_genres_provider.dart';
import '../../providers/connection_settings_provider.dart';
import '../../providers/source_modules_provider.dart';
import '../../providers/search_session_provider.dart';
import '../../theme/app_theme.dart';
import '../kalinka_bottom_sheet.dart';
import 'home_preview_choices.dart';

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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!page.isCatalog ||
        ref.watch(builtinSourcesProvider).contains(sourceOfId(page.id!))) {
      return const SizedBox.shrink();
    }
    final vocabulary = page.filterCapabilities.genreVocabulary;
    final genres = vocabulary == null || filter.genreIds.isEmpty
        ? null
        : ref.watch(browseGenresProvider(vocabulary)).value;
    final candidate = PinnedCatalog(
      page: page,
      filter: filter.fittedTo(page.filterCapabilities),
      preview: HomePreviewType.list,
      genreNames: {for (final genre in genres ?? []) genre.id: genre.name},
    );
    final pinned = ref
        .watch(pinnedCatalogsProvider)
        .any((pin) => pin.key == candidate.key);
    return IconButton(
      tooltip: pinned ? 'Unpin catalog' : 'Pin catalog to Home',
      iconSize: 20,
      constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
      isSelected: pinned,
      icon: const Icon(CupertinoIcons.pin),
      selectedIcon: const Icon(CupertinoIcons.pin_slash),
      onPressed: () async {
        final server = ref.read(connectionSettingsProvider).baseUrl;
        final notifier = ref.read(pinnedCatalogsProvider.notifier);
        if (pinned) {
          await saveHomeChange(context, notifier.unpin(candidate.key));
          return;
        }
        final type = await showKalinkaBottomSheet<HomePreviewType>(
          context: context,
          mayFillScreen: true,
          contentBuilder: (context) => SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SheetHeader(
                  title: 'PIN CATALOG',
                  summary: page.title ?? 'Catalog',
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    kSheetGutter,
                    0,
                    kSheetGutter,
                    16,
                  ),
                  child: Text(
                    'Your current filters are saved with this pin.',
                    style: KalinkaTextStyles.trackRowSubtitle,
                  ),
                ),
                const SheetSectionLabel('PREVIEW'),
                HomePreviewChoices(
                  onSelected: (type) => Navigator.pop(context, type),
                ),
              ],
            ),
          ),
        );
        if (type != null &&
            context.mounted &&
            ref.read(connectionSettingsProvider).baseUrl == server) {
          await saveHomeChange(
            context,
            notifier.pin(candidate.withPreview(type)),
          );
        }
      },
    );
  }
}
