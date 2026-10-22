import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data_model/data_model.dart';

import '../../providers/catalog_cards_provider.dart';
import '../../providers/collections_provider.dart';
import '../../providers/connection_state_provider.dart';
import '../../providers/source_modules_provider.dart';
import '../../theme/app_theme.dart';
import '../collection_art_tile.dart';
import '../home/home_layout.dart';
import '../kalinka_button.dart';
import 'collection_name_sheet.dart';
import '../search_cards/browse_item_rows.dart';
import '../search_cards/collection_row.dart';
import '../shelf_heading.dart';

/// Your collections on the Discover root: a heading with the count, the
/// first few as rows, and View All into the rest. Absent until there is one,
/// and where the server has no collections source.
///
/// Each row opens its collection's own page; View All opens the listing.
class CollectionsSection extends ConsumerWidget {
  /// Opens the Collections screen, where View All leads.
  final OpenCatalog onOpenCatalog;

  /// The room left under it, before the next section.
  final double gapAfter;

  const CollectionsSection({
    super.key,
    required this.onOpenCatalog,
    this.gapAfter = kHomeSectionGap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(connectionStateProvider, (prev, next) {
      if (next == ConnectionStatus.connected &&
          prev != ConnectionStatus.connected) {
        ref.invalidate(collectionsShelfProvider);
      }
    });

    final shelfAsync = ref.watch(collectionsShelfProvider);
    final loadingSources = ref.watch(
      sourceModulesProvider.select(
        (sources) => sources.isLoading && !sources.hasValue,
      ),
    );
    // Nothing until there are collections to show; not promoted for now.
    if (loadingSources) return const SizedBox.shrink();

    return shelfAsync.when(
      loading: SizedBox.shrink,
      // A shelf that failed to load is not worth a message on the root; the
      // catalogs below still work, and the next reload tries again.
      error: (_, _) => const SizedBox.shrink(),
      data: (shelf) {
        if (shelf == null || shelf.isEmpty) return const SizedBox.shrink();
        return _section(
          heading: ShelfHeading(
            title: shelf.plan.title.toUpperCase(),
            count: shelf.total,
            subtitle: shelf.plan.description,
            onViewAll: shelf.items.length < shelf.total
                ? () => onOpenCatalog(shelf.plan, shelf.plan.title)
                : null,
          ),
          body: _CollectionColumns(items: shelf.items),
        );
      },
    );
  }

  Widget _section({required Widget heading, required Widget body}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        heading,
        const SizedBox(height: kHomeHeadingGap),
        body,
        SizedBox(height: gapAfter),
      ],
    );
  }
}

/// What stands where the collections will be: the tile a collection gets
/// before it has a cover, a line on what one is, and the action that makes
/// one.
class CollectionsEmptyCard extends ConsumerWidget {
  const CollectionsEmptyCard({super.key});

  /// The tile at its roomiest; it shrinks with the card down to [_minTile].
  @visibleForTesting
  static const tileSize = 128.0;
  static const _minTile = 84.0;

  /// Below this the button no longer fits beside the tile, so it moves under
  /// the row. The tile stays next to the words either way — stacking those
  /// turns the card into a banner that owns the screen.
  static const _inlineButtonWidth = 380.0;

  /// How wide the button is allowed to grow beside the tile — a CTA stretched
  /// across a desktop-width card reads as a banner.
  static const _maxButtonWidth = 260.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: KalinkaColors.surfaceRaised,
        border: Border.all(color: KalinkaColors.borderSubtle, width: 1),
        borderRadius: BorderRadius.circular(16),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final tight = width < _inlineButtonWidth;
          final tile = CollectionArtTile(
            seed: 'collections',
            size: (width * 0.30).clamp(tight ? _minTile : 104.0, tileSize),
            radius: 14,
          );
          // Full width either way, so the label ellipsizes instead of
          // bursting the card when a translation or a large text scale runs
          // past the room the words have.
          final button = KalinkaButton(
            label: 'CREATE COLLECTION',
            leading: const Icon(Icons.add, size: 18),
            size: tight ? KalinkaButtonSize.compact : KalinkaButtonSize.normal,
            fullWidth: true,
            onTap: () => showNewCollectionSheet(context, ref),
          );
          final words = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'No collections yet',
                style: tight
                    ? KalinkaTextStyles.emptyQueueTitle.copyWith(
                        fontSize: KalinkaTypography.baseSize + 8,
                      )
                    : KalinkaTextStyles.emptyQueueTitle,
              ),
              const SizedBox(height: 6),
              Text(
                'Mix tracks from any source into your own ordered lists.',
                style: tight
                    ? KalinkaTextStyles.emptyQueueSubtitle.copyWith(
                        fontSize: KalinkaTypography.baseSize + 2,
                      )
                    : KalinkaTextStyles.emptyQueueSubtitle,
              ),
              if (!tight) ...[
                const SizedBox(height: 16),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: _maxButtonWidth),
                  child: button,
                ),
              ],
            ],
          );

          final row = Row(
            children: [
              tile,
              SizedBox(width: tight ? 14 : 20),
              Expanded(child: words),
            ],
          );
          if (!tight) return row;
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [row, const SizedBox(height: 14), button],
          );
        },
      ),
    );
  }
}

const _compactGap = 16.0;

/// Compact rows two or three across, [_compactGap] apart, where each keeps
/// room for its art, name, detail and actions; one column otherwise.
int compactColumnsFor(double width, double scale) =>
    ((width + _compactGap) / (360 * scale + _compactGap)).floor().clamp(1, 3);

/// Collections in compact rows: one under another on a narrow pane, two or
/// three across a wide one in reading order, so a lone collection keeps a
/// row's width instead of stretching across the pane.
class _CollectionColumns extends StatelessWidget {
  final List<BrowseItem> items;

  const _CollectionColumns({required this.items});

  static const _gap = _compactGap;

  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = compactColumnsFor(constraints.maxWidth, scale);
        if (columns == 1) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < items.length; i++) ...[
                if (i > 0)
                  Padding(
                    padding: EdgeInsets.only(
                      left: BrowseItemRows.textInsetOf(items[i - 1]),
                    ),
                    child: const Divider(
                      color: KalinkaColors.borderSubtle,
                      thickness: 1,
                      height: 1,
                    ),
                  ),
                CollectionShelfRow(item: items[i]),
              ],
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < items.length; i += columns)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var c = 0; c < columns; c++) ...[
                    if (c > 0) const SizedBox(width: _gap),
                    Expanded(
                      child: i + c < items.length
                          ? CollectionShelfRow(item: items[i + c])
                          : const SizedBox.shrink(),
                    ),
                  ],
                ],
              ),
          ],
        );
      },
    );
  }
}
