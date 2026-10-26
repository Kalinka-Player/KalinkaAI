import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data_model/browse_filters.dart';
import '../../providers/pinned_catalogs_provider.dart';
import '../../providers/box_control_provider.dart';
import '../../providers/browse_genres_provider.dart';
import '../../providers/source_modules_provider.dart';
import '../../providers/search_session_provider.dart';
import '../../theme/app_theme.dart';
import '../kalinka_bottom_sheet.dart';
import '../tap_highlight.dart';
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
    final pins = ref.watch(pinnedCatalogsProvider);
    final pinned = pins?.any((pin) => pin.key == candidate.key) ?? false;
    final confirmed = ref.watch(
      serverStorageKeyProvider.select((key) => key?.confirmed ?? false),
    );
    Future<void> toggle() async {
      final server = ref.read(serverStorageKeyProvider);
      final notifier = ref.read(pinnedCatalogsProvider.notifier);
      if (pinned) {
        await saveHomeChange(context, notifier.unpin(candidate.key));
        return;
      }
      final type = await showKalinkaBottomSheet<HomePreviewType>(
        context: context,
        mayFillScreen: true,
        contentBuilder: (context) => ConstrainedBox(
          // A short decision sheet, even on a tall tablet. Enlarged text
          // and short windows scroll within the available space.
          constraints: const BoxConstraints(maxHeight: 560),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(kSheetGutter, 12, 12, 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Pin to Home',
                              style: KalinkaTextStyles.settingsPageTitle,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              page.title ?? 'Catalog',
                              style: KalinkaTextStyles.trayRowSublabel,
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Close',
                        style: kalinkaIconButtonStyle,
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(
                          Icons.close_rounded,
                          color: KalinkaColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    kSheetGutter,
                    0,
                    kSheetGutter,
                    12,
                  ),
                  child: Text(
                    'Your current filters are saved with this pin.',
                    style: KalinkaTextStyles.trackRowSubtitle,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    kSheetGutter,
                    0,
                    kSheetGutter,
                    8,
                  ),
                  child: Text(
                    'Choose a preview',
                    style: KalinkaTextStyles.trayRowLabel,
                  ),
                ),
                HomePreviewChoices(
                  sourceColor:
                      ref
                          .read(sourceDisplayInfoProvider)[sourceOfId(page.id!)]
                          ?.color ??
                      KalinkaColors.accent,
                  onSelected: (type) => Navigator.pop(context, type),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: kSheetGutter,
                    vertical: 12,
                  ),
                  child: Text(
                    'Tap a layout to pin it.',
                    textAlign: TextAlign.center,
                    style: KalinkaTextStyles.trayRowSublabel,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      if (type != null &&
          context.mounted &&
          ref.read(serverStorageKeyProvider) == server) {
        await saveHomeChange(
          context,
          notifier.pin(candidate.withPreview(type)),
        );
      }
    }

    return IconButton(
      tooltip: pinned ? 'Unpin catalog' : 'Pin catalog to Home',
      iconSize: 20,
      constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
      isSelected: pinned,
      icon: const Icon(CupertinoIcons.pin),
      selectedIcon: const Icon(CupertinoIcons.pin_slash),
      onPressed: confirmed ? toggle : null,
    );
  }
}
