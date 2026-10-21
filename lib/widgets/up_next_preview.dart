import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data_model/data_model.dart';
import '../data_model/kalinka_ws_api.dart';
import '../providers/app_state_provider.dart';
import '../providers/connection_state_provider.dart';
import '../providers/kalinka_ws_api_provider.dart';
import '../providers/shell_nav_provider.dart';
import '../providers/url_resolver.dart';
import '../theme/app_theme.dart';
import '../utils/playback_utils.dart';
import 'away.dart';
import 'column_separator.dart';
import 'procedural_album_art.dart';
import 'queue_columns.dart';
import 'tap_highlight.dart';

const _horizontalInset = 12.0;
const _artworkSize = 40.0;
const _artworkGap = 10.0;

// These are navigation/playback shortcuts, so interaction stays neutral.
// Keep keyboard focus visible as well as pointer hover and press.
final _previewOverlay = WidgetStateProperty.resolveWith<Color?>((states) {
  if (states.contains(WidgetState.disabled)) return Colors.transparent;
  if (states.contains(WidgetState.focused)) {
    return KalinkaColors.surfaceOverlay;
  }
  return kalinkaOverlay.resolve(states) ?? Colors.transparent;
});

/// Uses the space remaining after the player's measured artwork and controls.
/// Scrolling cannot reveal extra rows: capacity is based on the full viewport
/// minus the content before this sliver, independent of the scroll offset.
class SliverUpNextPreview extends ConsumerWidget {
  final bool canOpenQueue;

  /// Only as many rows as the viewport has room for under what precedes it;
  /// otherwise up to five, scrolled to below the fold.
  final bool fitToSpace;

  const SliverUpNextPreview({
    super.key,
    required this.canOpenQueue,
    this.fitToSpace = true,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queue = ref.watch(
      playQueueStateStoreProvider.select(
        (s) => (
          tracks: s.trackList,
          index: s.playbackState.index ?? 0,
          exclusive: s.playbackControl.isExclusive,
        ),
      ),
    );
    final start = queue.index + 1;
    if (queue.exclusive || queue.index < 0 || queue.tracks.isEmpty) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }
    // At the end of the queue it says so, as the queue's own Up Next does.
    final total = math.max(0, queue.tracks.length - start);
    // The same notion of away as the rest of the player.
    final away = ref.watch(
      connectionStateProvider.select((s) => s.isInterrupted),
    );
    final scaler = MediaQuery.textScalerOf(context);
    // Use explicit line heights, preserving text scaling and a 48dp target.
    final rowHeight = math.max(
      56.0,
      scaler.scale(14) * 1.25 + scaler.scale(12) * 1.25 + 18,
    );
    final headerHeight = math.max(48.0, scaler.scale(12) * 1.4 + 16);
    final headingMetrics = TextPainter(
      text: TextSpan(
        text: 'UP NEXT · $total',
        style: KalinkaTextStyles.sectionHeader.copyWith(
          fontSize: 12,
          height: 1.4,
        ),
      ),
      textDirection: Directionality.of(context),
      textScaler: scaler,
      maxLines: 1,
    )..layout();
    final headingWidth =
        headingMetrics.width + (canOpenQueue ? 48 : 20) + _horizontalInset * 2;
    headingMetrics.dispose();
    // The queue's own columns, judged by the rows that can show.
    final hasAlbums = queue.tracks
        .skip(start)
        .take(5)
        .any((track) => track.album?.title.trim().isNotEmpty ?? false);

    return SliverLayoutBuilder(
      builder: (context, constraints) {
        final remaining =
            constraints.viewportMainAxisExtent -
            constraints.precedingScrollExtent;
        final columns = QueueColumns(
          width: constraints.crossAxisExtent,
          textScale: (scaler.scale(14) / 14).clamp(1.0, double.infinity),
          hasAlbums: hasAlbums,
        );
        final legend = total > 0 && columns.showAlbum;
        final capacity = fitToSpace
            ? ((remaining -
                          headerHeight -
                          (legend ? columns.legendHeight : 0) -
                          16) /
                      rowHeight)
                  .floor()
            : 5;
        if (capacity < 1 || constraints.crossAxisExtent < headingWidth) {
          return const SliverToBoxAdapter(child: SizedBox.shrink());
        }
        final count = math.min(5, math.min(total, capacity));
        return SliverToBoxAdapter(
          child: AwayDim(
            away: away,
            child: Padding(
              key: const ValueKey('now-playing-up-next'),
              padding: const EdgeInsets.only(bottom: 16),
              child: Column(
                children: [
                  SizedBox(
                    height: headerHeight,
                    child: _UpNextHeading(
                      total: total,
                      canOpenQueue: canOpenQueue,
                    ),
                  ),
                  if (legend)
                    QueueColumnLegend(
                      columns: columns,
                      start: _horizontalInset + _artworkSize + _artworkGap,
                      handle: false,
                    ),
                  if (total == 0)
                    SizedBox(
                      height: rowHeight,
                      child: Center(
                        child: Text(
                          'Queue is empty',
                          style: KalinkaTextStyles.queueItemArtist,
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  for (var i = 0; i < count; i++)
                    SizedBox(
                      height: rowHeight,
                      child: _UpcomingTrack(
                        key: ValueKey('up-next-track-${start + i}'),
                        track: queue.tracks[start + i],
                        index: start + i,
                        enabled: !away,
                        columns: columns,
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _UpNextHeading extends ConsumerWidget {
  final int total;
  final bool canOpenQueue;

  const _UpNextHeading({required this.total, required this.canOpenQueue});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final heading = Row(
      children: [
        Text(
          'UP NEXT',
          style: KalinkaTextStyles.sectionHeader.copyWith(
            fontSize: 12,
            height: 1.4,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '· $total',
          style: KalinkaTextStyles.trackCountBadge.copyWith(
            fontSize: 12,
            height: 1.4,
          ),
        ),
        const SizedBox(width: 12),
        const Expanded(child: Divider(color: KalinkaColors.borderSubtle)),
        if (canOpenQueue) ...[
          const SizedBox(width: 8),
          const Icon(
            Icons.chevron_right,
            size: 20,
            color: KalinkaColors.textMuted,
          ),
        ],
      ],
    );
    if (!canOpenQueue) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: _horizontalInset),
        child: heading,
      );
    }
    return Tooltip(
      message: 'View queue',
      child: MergeSemantics(
        child: Semantics(
          label: 'View queue, $total upcoming tracks',
          child: TextButton(
            onPressed: () =>
                ref.read(playerViewProvider.notifier).show(PlayerView.queue),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: _horizontalInset),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ).copyWith(overlayColor: _previewOverlay),
            child: ExcludeSemantics(child: heading),
          ),
        ),
      ),
    );
  }
}

/// A queue row in brief: no handle, but the queue's album and time columns
/// where the queue would show them.
class _UpcomingTrack extends ConsumerWidget {
  final Track track;
  final int index;
  final bool enabled;
  final QueueColumns columns;

  const _UpcomingTrack({
    super.key,
    required this.track,
    required this.index,
    required this.enabled,
    required this.columns,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final image = track.album?.image;
    final url = image?.small ?? image?.thumbnail ?? image?.large;
    final resolved = url == null
        ? null
        : ref.watch(urlResolverProvider).abs(url);
    final canPlay = enabled && !track.unavailable;
    final artist = track.performer?.name ?? 'Unknown Artist';
    final secondary = KalinkaTextStyles.queueItemArtist.copyWith(
      fontSize: 12,
      height: 1.25,
    );
    final time = Text(
      formatClock(Duration(seconds: track.duration)),
      maxLines: 1,
      style: KalinkaTextStyles.queueItemDuration.copyWith(
        fontSize: 12,
        height: 1.25,
      ),
    );
    return MergeSemantics(
      child: Semantics(
        label:
            '${track.title}, $artist${track.unavailable ? ', unavailable' : ''}',
        button: true,
        enabled: canPlay,
        child: Tooltip(
          message: '${track.title} — $artist',
          excludeFromSemantics: true,
          child: TextButton(
            onPressed: canPlay
                ? () => ref
                      .read(kalinkaWsApiProvider)
                      .sendQueueCommand(QueueCommand.play(index: index))
                : null,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(
                horizontal: _horizontalInset,
                vertical: 8,
              ),
              alignment: Alignment.centerLeft,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ).copyWith(overlayColor: _previewOverlay),
            child: ExcludeSemantics(
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: SizedBox(
                      width: _artworkSize,
                      height: _artworkSize,
                      child: resolved == null
                          ? ProceduralAlbumArt(
                              trackId: track.id,
                              size: _artworkSize,
                            )
                          : Image.network(
                              resolved,
                              cacheWidth: 120,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => ProceduralAlbumArt(
                                trackId: track.id,
                                size: _artworkSize,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(width: _artworkGap),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            if (track.unavailable) ...[
                              const Icon(
                                Icons.error_outline,
                                size: 16,
                                color: KalinkaColors.actionDelete,
                              ),
                              const SizedBox(width: 4),
                            ],
                            Expanded(
                              child: Text(
                                track.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: KalinkaTextStyles.queueItemTitle
                                    .copyWith(fontSize: 14, height: 1.25),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: secondary,
                        ),
                      ],
                    ),
                  ),
                  if (columns.showAlbum) ...[
                    const ColumnSeparator(),
                    SizedBox(
                      width: columns.albumWidth,
                      child: Text(
                        track.album?.title ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: secondary,
                      ),
                    ),
                  ],
                  const SizedBox(width: 8),
                  if (columns.showAlbum)
                    SizedBox(
                      width: columns.timeWidth,
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: time,
                      ),
                    )
                  else
                    time,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
