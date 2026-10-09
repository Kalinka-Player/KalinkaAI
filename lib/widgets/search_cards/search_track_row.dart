import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data_model/data_model.dart';
import '../../providers/app_state_provider.dart';
import '../../providers/kalinka_player_api_provider.dart';
import '../../providers/selection_state_provider.dart';
import '../../providers/toast_provider.dart';
import '../../providers/url_resolver.dart';
import '../../theme/app_theme.dart';
import '../procedural_album_art.dart';
import '../source_badge.dart';
import '../swipe_to_act_row.dart';
import '../track_tile_layout.dart';
import 'long_press_ring_painter.dart';
import 'track_row_support.dart';

/// Track row for search results.
/// ~60px height, 44x44 thumbnail, title/artist/duration.
/// Tap row = play now (replaces queue). With [queueContextIds] the list the
/// row belongs to becomes the queue, playhead on the tapped track.
/// Swipe right = add to queue / play next.
/// Long-press row = enter multi-select.
class SearchTrackRow extends ConsumerStatefulWidget {
  final BrowseItem item;

  /// The sibling track ids of the list this row was tapped from (e.g. its
  /// search section). Null → tapping plays just this track.
  final List<String>? queueContextIds;

  /// Whether the second line leads with "Track" and the source badge. Off
  /// under a heading that already says both.
  final bool labelled;

  const SearchTrackRow({
    super.key,
    required this.item,
    this.queueContextIds,
    this.labelled = true,
  });

  @override
  ConsumerState<SearchTrackRow> createState() => _SearchTrackRowState();
}

class _SearchTrackRowState extends ConsumerState<SearchTrackRow>
    with SingleTickerProviderStateMixin, LongPressRingMixin {
  late final AnimationController _flashController;
  late final Animation<Color?> _flashColorAnim;
  bool _tappedToPlay = false;

  @override
  void initState() {
    super.initState();
    _flashController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );
    _flashColorAnim = TweenSequence<Color?>([
      TweenSequenceItem(
        tween: ColorTween(
          begin: Colors.transparent,
          end: KalinkaColors.accent.withValues(alpha: 0.15),
        ).chain(CurveTween(curve: Curves.easeIn)),
        weight: 1,
      ),
      TweenSequenceItem(
        tween: ColorTween(
          begin: KalinkaColors.accent.withValues(alpha: 0.15),
          end: KalinkaColors.accentSubtle,
        ).chain(CurveTween(curve: Curves.easeOut)),
        weight: 2,
      ),
    ]).animate(_flashController);
  }

  @override
  void dispose() {
    _flashController.dispose();
    super.dispose();
  }

  Future<void> _playTrack() async {
    // Start flash animation immediately on tap, before the async API call.
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    setState(() => _tappedToPlay = true);
    if (!reduceMotion) _flashController.forward(from: 0.0);

    final api = ref.read(kalinkaProxyProvider);
    final ctx = widget.queueContextIds ?? const <String>[];
    final ctxIndex = ctx.indexOf(widget.item.id);
    final useContext = ctx.length > 1 && ctxIndex >= 0;
    final toast = ref.read(toastProvider.notifier);
    if (useContext) toast.beginQueueActivity('Starting playback…');
    try {
      if (useContext) {
        final added = await api.replace(ctx);
        await api.play(await _queuedIndex(api, ctx, ctxIndex, added.count));
        final n = added.count ?? ctx.length;
        toast.endQueueActivity('Playing $n ${n == 1 ? 'track' : 'tracks'}');
      } else {
        await api.replace([widget.item.id]);
        // Explicit index 0 avoids a backend race where a stale FINISHED event
        // from the just-cleared stream advances current_track_id before play().
        await api.play(0);
      }
    } catch (e) {
      // API failed — revert optimistic flash.
      if (mounted) {
        _flashController.reset();
        setState(() => _tappedToPlay = false);
      }
      if (useContext) {
        toast.endQueueActivity('Failed to play: $e', isError: true);
      } else {
        showSafeToast('Failed to play: $e', isError: true);
      }
    }
  }

  /// Where the tapped track stands in the queue [ctx] became. The server
  /// leaves out tracks it can't resolve, which moves later ones forward; if
  /// the tapped one went too, play the next one that stayed.
  static Future<int> _queuedIndex(
    KalinkaPlayerProxy api,
    List<String> ctx,
    int ctxIndex,
    int? kept,
  ) async {
    if (kept == null || kept >= ctx.length) return ctxIndex;
    final queued = (await api.listTracks(limit: kept)).items;
    var at = 0;
    for (var i = 0; i < ctx.length && at < queued.length; i++) {
      if (ctx[i] != queued[at].id) continue;
      if (i >= ctxIndex) return at;
      at++;
    }
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    // Scoped watches so unrelated selection changes don't rebuild the row.
    final isSelected = ref.watch(
      selectionStateProvider.select(
        (s) => s.selectedIds.contains(widget.item.id),
      ),
    );
    final selectionMode = ref.watch(
      selectionStateProvider.select((s) => s.isActive),
    );

    final track = widget.item.track;
    final title = track?.title ?? widget.item.name ?? 'Unknown';
    final artist = track?.performer?.name ?? '';
    final album = track?.album?.title ?? '';
    final subtitle = [
      artist,
      album,
    ].where((s) => s.isNotEmpty).join(' \u00B7 ');
    final duration = formatTrackDuration(
      track?.duration != null ? track!.duration * 1000 : null,
    );

    final urlResolver = ref.read(urlResolverProvider);
    final imageUrl = widget.item.image?.small;
    final resolvedImageUrl = imageUrl != null
        ? urlResolver.abs(imageUrl)
        : null;

    // Only rebuild on currentTrack ID changes — not on every position tick.
    // PlaybackState.position updates frequently while playing; watching the
    // whole state would re-`build()` every visible track row each tick.
    final currentTrackId = ref.watch(
      playerStateProvider.select((s) => s.currentTrack?.id),
    );
    final isCurrentTrack =
        widget.item.id.isNotEmpty && currentTrackId == widget.item.id;
    // Clear optimistic flash once server confirms this track is current,
    // or instantly revert if a different track became current.
    ref.listen(playerStateProvider.select((s) => s.currentTrack?.id), (
      prev,
      next,
    ) {
      if (!mounted) return;
      if (next == widget.item.id && _tappedToPlay) {
        setState(() => _tappedToPlay = false);
      } else if (_tappedToPlay && next != null && next != widget.item.id) {
        // A different track was chosen — clear our flash instantly.
        _flashController.reset();
        setState(() => _tappedToPlay = false);
      }
    });

    // Now-playing row decoration
    final showNowPlaying = !selectionMode && (_tappedToPlay || isCurrentTrack);
    // Bars follow the confirmed current track, not the optimistic flash.
    final showBars = !selectionMode && isCurrentTrack;
    final Color baseRowBg;
    if (selectionMode && isSelected) {
      baseRowBg = KalinkaColors.accent.withValues(alpha: 0.07);
    } else if (showNowPlaying) {
      baseRowBg = KalinkaColors.accentSubtle;
    } else {
      baseRowBg = Colors.transparent;
    }

    // Left-edge indicator bar drawn as an overlay so it doesn't push content
    // right the way a Border would.
    final Color? barColor = (selectionMode && isSelected)
        ? KalinkaColors.accent
        : (showNowPlaying ? KalinkaColors.accentBorder : null);

    final tileChild = TrackTileLayout(
      // Match the album/artist rows' 3px artwork inset — the default
      // TrackTileLayout left padding (12) pushed track artwork out of line.
      // Right 8 lands the duration on the chevrons'/chips' right edge.
      padding: const EdgeInsets.fromLTRB(
        3,
        kTrackTileVerticalPadding,
        8,
        kTrackTileVerticalPadding,
      ),
      leadingStartSpacing: 0,
      leading: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: resolvedImageUrl != null
                ? Image.network(
                    resolvedImageUrl,
                    width: 44,
                    height: 44,
                    cacheWidth: 132,
                    cacheHeight: 132,
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                    filterQuality: FilterQuality.low,
                    errorBuilder: (_, __, ___) =>
                        ProceduralAlbumArt(trackId: widget.item.id, size: 44),
                  )
                : ProceduralAlbumArt(trackId: widget.item.id, size: 44),
          ),
          if (longPressing && longPressProgress > 0)
            Positioned.fill(
              child: CustomPaint(
                painter: LongPressRingPainter(
                  progress: longPressProgress,
                  color: KalinkaColors.accent,
                ),
              ),
            ),
          if (selectionMode && isSelected)
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  color: KalinkaColors.accent.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Icon(Icons.check, color: Colors.white, size: 20),
              ),
            ),
        ],
      ),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
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
          const SizedBox(height: 2),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (widget.labelled &&
                  sourceBadgeVisible(ref, widget.item.id)) ...[
                SourceBadge(
                  entityId: widget.item.id,
                  size: SourceBadgeSize.standard,
                ),
                const SizedBox(width: 6),
              ],
              Expanded(
                child: widget.labelled
                    ? Text.rich(
                        entityTypeSubtitle('Track', subtitle),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      )
                    : Text(
                        subtitle,
                        style: KalinkaTextStyles.trackRowSubtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
              ),
            ],
          ),
        ],
      ),
      trailing: duration != null || showBars
          ? TrackRowTrailing(duration: duration, current: showBars)
          : null,
    );

    return SwipeToActRow(
      enabled: !selectionMode,
      onAddToQueue: () => addTrackToQueue(widget.item),
      onPlayNext: () => playTrackNext(widget.item),
      child: GestureDetector(
        onTap: () {
          if (selectionMode) {
            ref.read(selectionStateProvider.notifier).toggle(widget.item.id);
          } else {
            _playTrack();
          }
        },
        onLongPressStart: selectionMode
            ? null
            : (_) => startLongPressRing(
                () => ref
                    .read(selectionStateProvider.notifier)
                    .enterSelectionMode(widget.item.id),
              ),
        onLongPressEnd: selectionMode ? null : (_) => cancelLongPressRing(),
        onLongPressCancel: selectionMode ? null : cancelLongPressRing,
        child: Stack(
          children: [
            // The flash animation only repaints the background — `tileChild`
            // is captured outside the AnimatedBuilder so its image, badges,
            // and text don't rebuild on every animation tick.
            AnimatedBuilder(
              animation: _flashController,
              builder: (context, child) {
                final Color rowBg =
                    (showNowPlaying && _flashController.isAnimating)
                    ? (_flashColorAnim.value ?? baseRowBg)
                    : baseRowBg;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  decoration: BoxDecoration(color: rowBg),
                  child: child,
                );
              },
              child: tileChild,
            ),
            if (barColor != null)
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                child: IgnorePointer(
                  child: Container(width: 2, color: barColor),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
