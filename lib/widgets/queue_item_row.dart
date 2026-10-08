import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data_model/data_model.dart';
import '../data_model/kalinka_ws_api.dart';
import '../providers/kalinka_player_api_provider.dart';
import '../providers/playback_failure_provider.dart';
import '../providers/playback_time_provider.dart';
import '../providers/toast_provider.dart';
import '../providers/kalinka_ws_api_provider.dart';
import '../providers/url_resolver.dart';
import '../theme/app_theme.dart';
import '../utils/playback_utils.dart';
import 'procedural_album_art.dart';
import 'source_badge.dart';
import 'swipe_to_delete_row.dart';
import 'track_tile_layout.dart';

/// A single queue item row with thumbnail, title, artist, and trailing slot.
///
/// Up Next rows always show a drag handle. History rows show the track duration
/// and are rendered in a dimmed style (no handle, no swipe-to-delete).
class QueueItemRow extends ConsumerWidget {
  final Track track;
  final int index;
  final int displayIndex;
  final bool isCurrentTrack;
  final bool isHistory;
  final bool isDragging;
  final bool showDragHandle;
  final VoidCallback? onDelete;

  /// Total number of UP NEXT rows (excluding the now-playing tile). Used by
  /// the left accent strip to know how far the fade should reach.
  final int upNextCount;

  const QueueItemRow({
    super.key,
    required this.track,
    required this.index,
    required this.displayIndex,
    this.isCurrentTrack = false,
    this.isHistory = false,
    this.isDragging = false,
    this.showDragHandle = true,
    this.onDelete,
    this.upNextCount = 0,
  });

  int get _upNextPosition => displayIndex + 1;

  double get _titleFadeFactor {
    // Position 1 -> 0.0, position 8+ -> 1.0
    return ((_upNextPosition - 1) / 8).clamp(0.0, 1.0);
  }

  Color _titleColor() {
    if (isHistory) return KalinkaColors.textMuted;
    if (isCurrentTrack) {
      // Single accent use per queue screen — now-playing indicator.
      return KalinkaColors.textPrimary;
    }

    // Smooth progressive fade for Up Next titles.
    return Color.lerp(
      KalinkaColors.textPrimary,
      KalinkaColors.textSecondary,
      _titleFadeFactor,
    )!;
  }

  double _upNextArtworkOpacity() {
    if (isCurrentTrack) return 1.0;
    if (isHistory) return 0.75;

    if (_upNextPosition <= 3) return 1.0;
    if (_upNextPosition <= 8) return 0.85;
    return 0.8;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final api = ref.read(kalinkaWsApiProvider);
    final kalinkaProxy = ref.read(kalinkaProxyProvider);
    final urlResolver = ref.read(urlResolverProvider);
    // Failures this session, so a track that couldn't play stays marked after
    // the error dialog is gone and the player has moved on.
    final playbackFailed = ref.watch(
      playbackFailuresProvider.select((ids) => ids.contains(track.id)),
    );

    final imageUrl =
        track.album?.image?.small ??
        track.album?.image?.thumbnail ??
        track.album?.image?.large;
    final resolvedImageUrl = imageUrl != null
        ? urlResolver.abs(imageUrl)
        : null;

    // Colour tokens vary by state
    final titleColor = _titleColor();

    final artistColor = isHistory
        ? KalinkaColors.textMuted
        : KalinkaColors.textSecondary;

    // No tinted background — active row uses a left border accent strip only.
    final rowBg = isCurrentTrack
        ? KalinkaColors.accent.withValues(alpha: 0.08)
        : KalinkaColors.background;

    const double currentArtworkSize = 64;
    final double rowArtworkSize = isCurrentTrack && !isHistory
        ? currentArtworkSize
        : kTrackTileArtworkSize;

    Widget artwork;
    if (isCurrentTrack && !isHistory) {
      artwork = ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: currentArtworkSize,
          height: currentArtworkSize,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Layer 1 — album artwork
              resolvedImageUrl != null
                  ? Image.network(
                      resolvedImageUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => ProceduralAlbumArt(
                        trackId: track.id,
                        size: currentArtworkSize,
                      ),
                    )
                  : ProceduralAlbumArt(
                      trackId: track.id,
                      size: currentArtworkSize,
                    ),
              // Layer 2 — scrim
              // const DecoratedBox(
              //   decoration: BoxDecoration(
              //     gradient: LinearGradient(
              //       begin: Alignment.topCenter,
              //       end: Alignment.bottomCenter,
              //       stops: [0.0, 0.45, 1.0],
              //       colors: [
              //         Color(0x000A0204),
              //         Color(0x8C0A0204),
              //         Color(0xD10A0204),
              //       ],
              //     ),
              //   ),
              // ),
            ],
          ),
        ),
      );
    } else {
      artwork = Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(6)),
        clipBehavior: Clip.antiAlias,
        child: resolvedImageUrl != null
            ? Image.network(
                resolvedImageUrl,
                width: 44,
                height: 44,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) =>
                    ProceduralAlbumArt(trackId: track.id, size: 44),
              )
            : ProceduralAlbumArt(trackId: track.id, size: 44),
      );

      artwork = Opacity(opacity: _upNextArtworkOpacity(), child: artwork);
    }

    final showNowPlayingBar = isCurrentTrack && !isHistory;

    final isNowPlaying = isCurrentTrack && !isHistory;
    final titleStyle = isNowPlaying
        ? KalinkaTextStyles.queueItemTitle.copyWith(
            color: titleColor,
            fontSize: (KalinkaTextStyles.queueItemTitle.fontSize ?? 16) + 1,
            fontWeight: FontWeight.w600,
            height: 1.2,
          )
        : KalinkaTextStyles.queueItemTitle.copyWith(color: titleColor);
    final rowPadding = isNowPlaying
        ? const EdgeInsets.symmetric(horizontal: 12, vertical: 12)
        : kTrackTilePadding;

    final rowContent = GestureDetector(
      onTap: () {
        api.sendQueueCommand(QueueCommand.play(index: index));
      },
      child: Stack(
        children: [
          Container(
            decoration: BoxDecoration(color: rowBg),
            child: TrackTileLayout(
              leading: artwork,
              artworkSize: rowArtworkSize,
              padding: rowPadding,
              content: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      if (track.unavailable || playbackFailed) ...[
                        Tooltip(
                          message: track.unavailable
                              ? (track.unavailableReason ??
                                    'Unavailable — could not load this track')
                              : 'Playback failed — press play to try again',
                          child: const Icon(
                            Icons.error_outline,
                            size: 16,
                            color: KalinkaColors.actionDelete,
                          ),
                        ),
                        const SizedBox(width: 4),
                      ],
                      Expanded(
                        child: Text(
                          track.title,
                          style: titleStyle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          softWrap: false,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: isNowPlaying ? 4 : 2),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      if (sourceBadgeVisible(ref, track.id)) ...[
                        SourceBadge(
                          entityId: track.id,
                          size: SourceBadgeSize.small,
                        ),
                        const SizedBox(width: 4),
                      ],
                      Expanded(
                        child: Text(
                          track.performer?.name ?? 'Unknown Artist',
                          style: KalinkaTextStyles.queueItemArtist.copyWith(
                            color: artistColor,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          softWrap: false,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              trailing: isHistory
                  ? Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text(
                        formatClock(Duration(seconds: track.duration)),
                        style: KalinkaTextStyles.queueItemDuration.copyWith(
                          color: KalinkaColors.textMuted,
                        ),
                      ),
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (isNowPlaying)
                          _NowPlayingTimer(durationSec: track.duration)
                        else
                          Text(
                            formatClock(Duration(seconds: track.duration)),
                            // Keep Up Next duration fixed for fast scanning.
                            style: KalinkaTextStyles.queueItemDuration.copyWith(
                              color: KalinkaColors.textSecondary,
                            ),
                          ),
                        if (showDragHandle) ...[
                          const SizedBox(width: 7),
                          _DragHandle(index: displayIndex),
                        ] else
                          const SizedBox(width: 8),
                      ],
                    ),
            ),
          ),
          if (showNowPlayingBar)
            const Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              child: IgnorePointer(
                child: SizedBox(
                  width: 4,
                  child: ColoredBox(color: KalinkaColors.accentBorder),
                ),
              ),
            )
          else if (!isHistory && !isCurrentTrack)
            () {
              final fadeRows = upNextCount >= 2 ? 2 : upNextCount;
              if (fadeRows == 0 || displayIndex >= fadeRows) {
                return const SizedBox.shrink();
              }
              return Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                child: IgnorePointer(
                  child: _UpNextFadeBar(
                    rowIndex: displayIndex,
                    fadeRows: fadeRows,
                  ),
                ),
              );
            }(),
        ],
      ),
    );

    return SwipeToDeleteRow(
      enabled: !isHistory && !isDragging,
      onDelete: () async {
        onDelete?.call();
        try {
          await kalinkaProxy.remove(index);
          ref.read(toastProvider.notifier).showTrackRemoved(track.title);
        } catch (e) {
          ref
              .read(toastProvider.notifier)
              .show('Failed to remove: $e', isError: true);
        }
      },
      child: rowContent,
    );
  }
}

/// Continuation of the accent bar through the first one or two UP NEXT rows.
/// Each row draws its segment as a vertical gradient so adjacent rows form one
/// smooth top-to-bottom fade ending at the bottom of the last fade row.
class _UpNextFadeBar extends StatelessWidget {
  final int rowIndex;
  final int fadeRows;

  const _UpNextFadeBar({required this.rowIndex, required this.fadeRows});

  @override
  Widget build(BuildContext context) {
    final topAlpha = (1.0 - rowIndex / fadeRows).clamp(0.0, 1.0);
    final bottomAlpha = (1.0 - (rowIndex + 1) / fadeRows).clamp(0.0, 1.0);
    const base = KalinkaColors.accentBorder;
    return SizedBox(
      width: 4,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              base.withValues(alpha: base.a * topAlpha),
              base.withValues(alpha: base.a * bottomAlpha),
            ],
          ),
        ),
      ),
    );
  }
}

/// Position/total timer for the now-playing row, ticking once per second via
/// [playbackTimeMsProvider]. Renders "M:SS / M:SS".
class _NowPlayingTimer extends ConsumerWidget {
  final int durationSec;

  const _NowPlayingTimer({required this.durationSec});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final positionMs = ref.watch(playbackTimeMsProvider);
    final positionSec = (positionMs / 1000).floor();
    final String label;
    if (durationSec > 0) {
      final clamped = positionSec.clamp(0, durationSec);
      label = '-${formatClock(Duration(seconds: durationSec - clamped))}';
    } else {
      // Unknown duration: fall back to elapsed time so the timer still moves.
      label = formatClock(Duration(seconds: positionSec));
    }
    return Text(
      label,
      style: KalinkaTextStyles.queueItemDuration.copyWith(
        color: KalinkaColors.textSecondary,
      ),
    );
  }
}

/// Drag handle widget aligned to the 44px artwork centerline.
class _DragHandle extends StatelessWidget {
  /// The index of this item within the enclosing [SliverReorderableList].
  final int index;

  const _DragHandle({required this.index});

  @override
  Widget build(BuildContext context) {
    return ReorderableDragStartListener(
      index: index,
      child: const SizedBox(
        width: 48,
        height: 44,
        child: Center(
          child: Icon(
            Icons.drag_handle,
            size: 20,
            color: KalinkaColors.textMuted,
          ),
        ),
      ),
    );
  }
}
