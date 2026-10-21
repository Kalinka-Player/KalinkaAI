import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data_model/data_model.dart';
import '../../providers/selection_state_provider.dart';
import '../../providers/toast_provider.dart';
import '../../providers/url_resolver.dart';
import '../../theme/app_theme.dart';
import '../modifier_click.dart';
import '../procedural_album_art.dart';
import '../source_badge.dart';
import '../tap_highlight.dart';
import 'browse_navigation_scope.dart';
import 'open_chevron_button.dart';
import 'row_columns.dart';
import 'track_row_support.dart';

/// Luma-weighted grayscale for the artist avatar while multi-select is
/// active — artists aren't selectable, so they drop to black & white.
const ColorFilter _grayscaleFilter = ColorFilter.matrix(<double>[
  0.2126, 0.7152, 0.0722, 0, 0, //
  0.2126, 0.7152, 0.0722, 0, 0, //
  0.2126, 0.7152, 0.0722, 0, 0, //
  0, 0, 0, 1, 0,
]);

/// Artist row: round portrait, name, album count. The row and its chevron
/// open the artist's page.
class SearchArtistRow extends ConsumerStatefulWidget {
  final BrowseItem item;

  const SearchArtistRow({super.key, required this.item});

  @override
  ConsumerState<SearchArtistRow> createState() => _SearchArtistRowState();
}

class _SearchArtistRowState extends ConsumerState<SearchArtistRow> {
  @override
  Widget build(BuildContext context) {
    void open() => openBrowsable(context, ref, widget.item);
    // Artists aren't a playable unit, so they sit out multi-select: the row
    // greys out (B&W avatar, dimmed) and ignores taps while it's active.
    final selectionMode = ref.watch(
      selectionStateProvider.select((s) => s.isActive),
    );

    final artist = widget.item.artist;
    final name = artist?.name ?? widget.item.name ?? 'Unknown';
    final albumCount = artist?.albumCount;

    final urlResolver = ref.read(urlResolverProvider);
    final imageUrl = widget.item.image?.small;
    final resolvedImageUrl = imageUrl != null
        ? urlResolver.abs(imageUrl)
        : null;

    final statsParts = <String>[];
    if (albumCount != null) {
      statsParts.add('$albumCount ${albumCount == 1 ? 'album' : 'albums'}');
    }
    final stats = statsParts.join(' \u00B7 ');

    final row = ModifierClick(
      onModifiedClick: () => showSafeToast('Artists can’t be multi-selected'),
      child: GestureDetector(
        onTap: selectionMode ? null : open,
        onLongPress: () {
          showSafeToast('Artists can’t be multi-selected');
        },
        behavior: HitTestBehavior.opaque,
        child: RowColumnsScope(
          builder: (context, columns) => AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            // Right 0 keeps the chevron on the shared right-edge line.
            padding: const EdgeInsets.only(top: 10, bottom: 10, left: 3),
            child: AnimatedOpacity(
              opacity: selectionMode ? 0.45 : 1.0,
              duration: const Duration(milliseconds: 180),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 60),
                child: Row(
                  children: [
                    // Circular avatar, sized like the album thumbnail
                    // Note: previously wrapped in a Container with
                    // BoxShadow(blurRadius: 14). The 14px blur is GPU-
                    // expensive (~5x cost of a 6px blur) and forces a
                    // saveLayer per artist row. Removed to keep scroll smooth
                    // when the BASED ON NOW PLAYING section surfaces several
                    // artist rows in the first viewport.
                    _GrayscaleWhen(
                      active: selectionMode,
                      child: SizedBox(
                        width: 60,
                        height: 60,
                        child: ClipOval(
                          child: resolvedImageUrl != null
                              ? Image(
                                  // ResizeImage.fit preserves aspect ratio at decode
                                  // time. The Image.network shortcut wraps with the
                                  // default ResizeImagePolicy.exact, which squashes
                                  // non-square artist photos into 180x180 — visible
                                  // as stretching even after BoxFit.cover.
                                  image: ResizeImage(
                                    NetworkImage(resolvedImageUrl),
                                    width: 180,
                                    height: 180,
                                    policy: ResizeImagePolicy.fit,
                                  ),
                                  width: 60,
                                  height: 60,
                                  fit: BoxFit.cover,
                                  gaplessPlayback: true,
                                  filterQuality: FilterQuality.low,
                                  errorBuilder: (_, _, _) => ProceduralAlbumArt(
                                    trackId: widget.item.id,
                                    size: 60,
                                  ),
                                )
                              : ProceduralAlbumArt(
                                  trackId: widget.item.id,
                                  size: 60,
                                ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Name (with source badge) + stats
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          ...matchBadge(widget.item),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Flexible(
                                child: Text(
                                  name,
                                  style: KalinkaTextStyles.trackRowTitle
                                      .copyWith(fontWeight: FontWeight.w600),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              if (!columns.source &&
                                  sourceBadgeVisible(ref, widget.item.id)) ...[
                                SourceBadge(entityId: widget.item.id),
                                const SizedBox(width: 6),
                              ],
                              Expanded(
                                child: Text.rich(
                                  entityTypeSubtitle(
                                    'Artist',
                                    columns.detail ? '' : stats,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    RowColumnCells(
                      columns: columns,
                      detail: stats,
                      sourceOf: widget.item.id,
                    ),
                    RowTrailing(
                      columns: columns,
                      child: IgnorePointer(
                        ignoring: selectionMode,
                        child: OpenChevronButton(name: name, onTap: open),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    return HoverHighlight(enabled: !selectionMode, child: row);
  }
}

/// Applies the grayscale filter only when [active] — skips the ColorFiltered
/// saveLayer cost in the common (non-selection) case.
class _GrayscaleWhen extends StatelessWidget {
  final bool active;
  final Widget child;

  const _GrayscaleWhen({required this.active, required this.child});

  @override
  Widget build(BuildContext context) {
    if (!active) return child;
    return ColorFiltered(colorFilter: _grayscaleFilter, child: child);
  }
}
