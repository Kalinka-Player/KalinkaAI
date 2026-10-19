import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data_model/data_model.dart';
import '../../providers/kalinka_player_api_provider.dart';
import '../../providers/selection_state_provider.dart';
import '../../providers/toast_provider.dart';
import '../../providers/url_resolver.dart';
import '../../theme/app_theme.dart';
import '../../utils/play_next.dart';
import '../procedural_album_art.dart';
import '../source_badge.dart';
import '../swipe_to_act_row.dart';
import 'browse_navigation_scope.dart';
import 'long_press_ring_painter.dart';
import 'open_chevron_button.dart';
import 'row_columns.dart';
import 'row_play_button.dart';
import 'track_row_support.dart';

/// A source's playlist: the album row's shape with a playlist mark on the art.
/// The row and its chevron open the playlist's page; Play starts it without
/// opening it. Swipe right = add to queue / play next. Long-press enters
/// multi-select mode.
class SearchPlaylistRow extends ConsumerStatefulWidget {
  final BrowseItem item;

  const SearchPlaylistRow({super.key, required this.item});

  @override
  ConsumerState<SearchPlaylistRow> createState() => _SearchPlaylistRowState();
}

class _SearchPlaylistRowState extends ConsumerState<SearchPlaylistRow>
    with LongPressRingMixin {
  Future<void> _addToQueue() async {
    final api = ref.read(kalinkaProxyProvider);
    final title = widget.item.playlist?.name ?? widget.item.name ?? 'playlist';
    await runQueueActivity(
      pending: 'Adding to queue…',
      action: () => api.add([widget.item.id]),
      done: (r) {
        final n = r.count ?? widget.item.playlist?.trackCount;
        return n != null
            ? '$title — $n ${n == 1 ? 'track' : 'tracks'} added to queue'
            : '$title added to queue';
      },
      failed: (e) => 'Failed to add: $e',
    );
  }

  Future<void> _playNext() async {
    final api = ref.read(kalinkaProxyProvider);
    final title = widget.item.playlist?.name ?? widget.item.name ?? 'playlist';
    final insertIndex = playNextInsertIndex(ref);
    await runQueueActivity(
      pending: 'Queueing next…',
      action: () => api.add([widget.item.id], index: insertIndex),
      done: (_) => '$title playing next',
      failed: (e) => 'Failed to add: $e',
    );
  }

  @override
  Widget build(BuildContext context) {
    final urlResolver = ref.read(urlResolverProvider);

    // Scoped watches so unrelated selection changes don't rebuild the row.
    final selectionMode = ref.watch(
      selectionStateProvider.select((s) => s.isActive),
    );
    final isSelected = ref.watch(
      selectionStateProvider.select(
        (s) => s.isContainerSelected(widget.item.id),
      ),
    );
    final isPartial = ref.watch(
      selectionStateProvider.select(
        (s) => s.isContainerPartial(widget.item.id),
      ),
    );

    final playlist = widget.item.playlist;
    final title = playlist?.name ?? widget.item.name ?? 'Unknown';
    final trackCount = playlist?.trackCount;
    final description = playlist?.description ?? '';

    final subtitleParts = <String>[
      if (trackCount != null)
        '$trackCount ${trackCount == 1 ? 'track' : 'tracks'}',
      if (description.isNotEmpty) description,
    ];
    final subtitle = subtitleParts.join(' \u00B7 ');
    final imageUrl =
        widget.item.image?.small ??
        widget.item.image?.thumbnail ??
        widget.item.image?.large;
    final resolvedImageUrl = imageUrl != null
        ? urlResolver.abs(imageUrl)
        : null;

    return SwipeToActRow(
      enabled: !selectionMode,
      onAddToQueue: _addToQueue,
      onPlayNext: _playNext,
      child: GestureDetector(
        onTap: () {
          if (selectionMode) {
            ref
                .read(selectionStateProvider.notifier)
                .toggleContainer(widget.item.id);
          } else {
            openBrowsable(context, ref, widget.item);
          }
        },
        onLongPressStart: selectionMode
            ? null
            : (_) => startLongPressRing(
                () => ref
                    .read(selectionStateProvider.notifier)
                    .toggleContainer(widget.item.id),
              ),
        onLongPressEnd: selectionMode ? null : (_) => cancelLongPressRing(),
        onLongPressCancel: selectionMode ? null : cancelLongPressRing,
        behavior: HitTestBehavior.opaque,
        child: RowColumnsScope(
          builder: (context, columns) => AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: EdgeInsets.only(
              top: 8,
              bottom: 8,
              left: selectionMode && isSelected ? 0 : 3,
              right: 0,
            ),
            decoration: BoxDecoration(
              color: selectionMode && isSelected
                  ? KalinkaColors.accent.withValues(alpha: 0.07)
                  : Colors.transparent,
              border: selectionMode && isSelected
                  ? const Border(
                      left: BorderSide(color: KalinkaColors.accent, width: 3),
                    )
                  : null,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Thumbnail 56x56 with mosaic overlay
                SizedBox(
                  width: 56,
                  height: 56,
                  child: Stack(
                    children: [
                      // Note: previously wrapped in a Container with
                      // BoxShadow(blurRadius: 6). Removed for the same
                      // GPU/saveLayer reason as the album row — see
                      // comment in search_album_row.dart.
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Stack(
                          children: [
                            if (resolvedImageUrl != null)
                              Image.network(
                                resolvedImageUrl,
                                fit: BoxFit.cover,
                                width: 56,
                                height: 56,
                                cacheWidth: 168,
                                cacheHeight: 168,
                                gaplessPlayback: true,
                                filterQuality: FilterQuality.low,
                                errorBuilder: (context, error, stackTrace) {
                                  return ProceduralAlbumArt(
                                    trackId: widget.item.id,
                                    size: 56,
                                  );
                                },
                              )
                            else
                              ProceduralAlbumArt(
                                trackId: widget.item.id,
                                size: 56,
                              ),
                            // Playlist marker badge — bottom-right corner
                            const Positioned(
                              right: 3,
                              bottom: 3,
                              child: CornerGlyph(Icons.queue_music),
                            ),
                          ],
                        ),
                      ),
                      // Long-press ring
                      if (longPressing && longPressProgress > 0)
                        Positioned.fill(
                          child: CustomPaint(
                            painter: LongPressRingPainter(
                              progress: longPressProgress,
                              color: KalinkaColors.accent,
                            ),
                          ),
                        ),
                      // Selection overlay
                      if (selectionMode && isSelected)
                        Positioned.fill(
                          child: Container(
                            decoration: BoxDecoration(
                              color: KalinkaColors.accent.withValues(
                                alpha: 0.4,
                              ),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              isPartial ? Icons.remove : Icons.check,
                              color: Colors.white,
                              size: 24,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                // Info column
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ...matchBadge(widget.item),
                      Text(
                        title,
                        style: KalinkaTextStyles.trackRowTitle.copyWith(
                          color: selectionMode && isSelected
                              ? KalinkaColors.accentTint
                              : null,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      // Its details move to their column, its badge to the
                      // source's, as the row widens.
                      if (subtitle.isNotEmpty &&
                          (!columns.detail ||
                              !columns.source &&
                                  sourceBadgeVisible(ref, widget.item.id)))
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            if (!columns.source &&
                                sourceBadgeVisible(ref, widget.item.id)) ...[
                              SourceBadge(entityId: widget.item.id),
                              const SizedBox(width: 6),
                            ],
                            Expanded(
                              child: Text(
                                columns.detail ? '' : subtitle,
                                style: KalinkaTextStyles.trackRowSubtitle,
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
                if (columns.any)
                  SizedBox(
                    height: 60,
                    child: Center(
                      child: RowColumnCells(
                        columns: columns,
                        detail: subtitle,
                        sourceOf: widget.item.id,
                      ),
                    ),
                  ),
                RowTrailing(
                  columns: columns,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (widget.item.canAdd && !selectionMode)
                        RowPlayButton(item: widget.item),
                      OpenChevronButton(
                        name: title,
                        onTap: () => openBrowsable(context, ref, widget.item),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
