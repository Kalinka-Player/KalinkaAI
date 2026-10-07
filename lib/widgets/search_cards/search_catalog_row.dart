import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data_model/data_model.dart';
import '../../providers/browse_detail_provider.dart';
import '../../providers/row_expansion_provider.dart';
import '../../theme/app_theme.dart';
import '../procedural_album_art.dart';
import 'browse_item_rows.dart';
import 'expand_chevron_button.dart';
import 'track_row_support.dart';

/// Catalog row for search results: a browsable sub-catalog with no cover of
/// its own. Presented like a playlist — a glyph over generated art — expanding
/// to its children, each dispatched back through [BrowseItemRows].
class SearchCatalogRow extends ConsumerWidget {
  final BrowseItem item;

  const SearchCatalogRow({super.key, required this.item});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Shares the album/playlist expansion set — ids are unique, so no clash.
    final isExpanded = ref.watch(
      rowExpansionProvider.select((s) => s.unrolled.contains(item.id)),
    );
    final title = item.catalog?.title ?? item.name ?? 'Unknown';
    final description = item.catalog?.description ?? '';

    void toggle() =>
        ref.read(rowExpansionProvider.notifier).toggleUnrolled(item.id);

    return Column(
      children: [
        GestureDetector(
          onTap: toggle,
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: EdgeInsets.only(
              top: 8,
              bottom: 8,
              left: isExpanded ? 0 : 3,
              right: 0,
            ),
            decoration: BoxDecoration(
              color: isExpanded
                  ? KalinkaColors.surfaceRaised
                  : Colors.transparent,
              border: isExpanded
                  ? Border(
                      left: BorderSide(
                        color: KalinkaColors.accent.withValues(alpha: 0.40),
                        width: 3,
                      ),
                    )
                  : null,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 60,
                  height: 60,
                  child: Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: ProceduralAlbumArt(trackId: item.id, size: 60),
                      ),
                      const Positioned(
                        right: 3,
                        bottom: 3,
                        child: CornerGlyph(Icons.queue_music),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        title,
                        style: KalinkaTextStyles.trackRowTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (description.isNotEmpty)
                        Text(
                          description,
                          style: KalinkaTextStyles.trackRowSubtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                ExpandChevronButton(isExpanded: isExpanded, onTap: toggle),
              ],
            ),
          ),
        ),
        AnimatedCrossFade(
          firstChild: const SizedBox.shrink(),
          secondChild: isExpanded
              ? _CatalogExpansion(catalogId: item.id)
              : const SizedBox.shrink(),
          crossFadeState: isExpanded
              ? CrossFadeState.showSecond
              : CrossFadeState.showFirst,
          duration: const Duration(milliseconds: 200),
          firstCurve: Curves.easeOut,
          secondCurve: Curves.easeOut,
          sizeCurve: Curves.easeOut,
        ),
      ],
    );
  }
}

/// The catalog's children, each dispatched by [BrowseItemRows].
class _CatalogExpansion extends ConsumerWidget {
  final String catalogId;

  const _CatalogExpansion({required this.catalogId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final browseAsync = ref.watch(browseDetailProvider(catalogId));

    return Padding(
      padding: const EdgeInsets.only(left: 16),
      child: browseAsync.when(
        data: (list) {
          if (list.items.isEmpty) {
            return Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                'Nothing here',
                style: KalinkaTextStyles.trackRowSubtitle,
              ),
            );
          }
          return BrowseItemRows(items: list.items);
        },
        loading: () => const Padding(
          padding: EdgeInsets.all(16),
          child: Center(
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ),
        error: (e, _) => Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            'Failed to load',
            style: KalinkaTextStyles.trackRowSubtitle,
          ),
        ),
      ),
    );
  }
}
