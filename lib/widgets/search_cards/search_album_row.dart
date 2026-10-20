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

/// Album row: thumbnail, title, artist · year · track count, genre pill.
/// The row and its chevron open the album's page; Play starts it without
/// opening it. Swipe right = add to queue / play next. Long-press enters
/// multi-select mode.
class SearchAlbumRow extends ConsumerStatefulWidget {
  final BrowseItem item;

  const SearchAlbumRow({super.key, required this.item});

  @override
  ConsumerState<SearchAlbumRow> createState() => _SearchAlbumRowState();
}

class _SearchAlbumRowState extends ConsumerState<SearchAlbumRow>
    with LongPressRingMixin {
  Future<void> _addToQueue() async {
    final api = ref.read(kalinkaProxyProvider);
    final name = widget.item.album?.title ?? widget.item.name ?? 'album';
    await runQueueActivity(
      pending: 'Adding to queue…',
      action: () => api.add([widget.item.id]),
      done: (r) {
        final n = r.count ?? widget.item.album?.trackCount;
        return n != null
            ? '$name — $n ${n == 1 ? 'track' : 'tracks'} added to queue'
            : '$name added to queue';
      },
      failed: (e) => 'Failed to add: $e',
    );
  }

  Future<void> _playNext() async {
    final api = ref.read(kalinkaProxyProvider);
    final name = widget.item.album?.title ?? widget.item.name ?? 'album';
    final insertIndex = playNextInsertIndex(ref);
    await runQueueActivity(
      pending: 'Queueing next…',
      action: () => api.add([widget.item.id], index: insertIndex),
      done: (_) => '$name playing next',
      failed: (e) => 'Failed to add: $e',
    );
  }

  @override
  Widget build(BuildContext context) {
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

    final album = widget.item.album;
    final title = album?.title ?? widget.item.name ?? 'Unknown';
    final artist = album?.artist?.name ?? '';
    final trackCount = album?.trackCount;
    final genres = album?.genres ?? const <Genre>[];
    final genre = genres.isEmpty
        ? null
        : genres.map((genre) => genre.name).join(' \u00B7 ');

    final urlResolver = ref.read(urlResolverProvider);
    final imageUrl = widget.item.image?.small ?? widget.item.image?.thumbnail;
    final resolvedImageUrl = imageUrl != null
        ? urlResolver.abs(imageUrl)
        : null;

    // What the second line says of the album, moved to the details column
    // once the row has one; the genre with it.
    final details = [
      if (album?.year != null) '${album!.year}',
      if (trackCount != null)
        '$trackCount ${trackCount == 1 ? 'track' : 'tracks'}',
    ].join(' \u00B7 ');
    String subtitleFor(RowColumns columns) => [
      if (artist.isNotEmpty && !columns.artist) artist,
      if (details.isNotEmpty && !columns.detail) details,
    ].join(' \u00B7 ');

    final row = SwipeToActRow(
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
                // Thumbnail 56x56 with selection overlay
                SizedBox(
                  width: 60,
                  height: 60,
                  child: Stack(
                    children: [
                      // Note: previously wrapped in a Container with
                      // BoxShadow(blurRadius: 6). Each blurred shadow
                      // forced a saveLayer + Gaussian blur shader pass on
                      // the GPU, and several album/playlist rows can be
                      // on screen at once. Tracing showed this was the
                      // dominant scroll-time cost on the zero-state
                      // surface (BASED ON NOW PLAYING packs many
                      // shadow-bearing rows into the first viewport).
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: resolvedImageUrl != null
                            ? Image.network(
                                resolvedImageUrl,
                                width: 60,
                                height: 60,
                                cacheWidth: 180,
                                cacheHeight: 180,
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
                              entityTypeSubtitle('Album', subtitleFor(columns)),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      if (genre != null && !columns.detail) ...[
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: KalinkaColors.surfaceElevated,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(genre, style: KalinkaTextStyles.tagPill),
                        ),
                      ],
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
                        artist: artist,
                        detail: [
                          if (details.isNotEmpty) details,
                          ?genre,
                        ].join(' \u00B7 '),
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
    return MouseRegion(cursor: SystemMouseCursors.click, child: row);
  }
}
