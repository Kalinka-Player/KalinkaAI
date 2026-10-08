import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data_model/data_model.dart';
import '../../providers/app_state_provider.dart';
import '../../providers/browse_detail_provider.dart';
import '../../providers/kalinka_player_api_provider.dart';
import '../../providers/selection_state_provider.dart';
import '../../providers/toast_provider.dart';
import '../../providers/url_resolver.dart';
import '../../theme/app_theme.dart';
import '../procedural_album_art.dart';
import '../source_badge.dart';
import '../swipe_to_act_row.dart';
import 'container_action_header.dart';
import 'long_press_ring_painter.dart';
import 'track_row_support.dart';

/// The tracks of an unrolled container — a playlist, a collection — under the
/// row that opened it: the container's own actions, then one row per track.
/// Fetched by container id, so the row that unrolls need not have them.
class ExpandedContainerTracks extends ConsumerWidget {
  final BrowseItem item;

  /// What stands where the tracks would be. A collection says something
  /// different from a source's playlist, which cannot be empty by accident.
  final String emptyLabel;

  /// An action on the container itself, carried at the trailing end of the
  /// header row.
  final Widget? headerAction;

  /// An offer to fill the container while it holds nothing (a collection is
  /// offered the queue).
  final Widget? emptyAction;

  const ExpandedContainerTracks({
    super.key,
    required this.item,
    this.emptyLabel = 'No tracks in this playlist',
    this.headerAction,
    this.emptyAction,
  });

  String get containerId => item.id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tracksAsync = ref.watch(browseDetailProvider(containerId));

    return tracksAsync.when(
      // A write reloads a collection under the row; keep its rows up meanwhile.
      skipLoadingOnReload: true,
      data: (browseList) {
        final items = browseList.items;
        if (items.isEmpty) {
          return _EmptyState(
            label: emptyLabel,
            action: emptyAction,
            trailing: headerAction,
          );
        }
        // What the container holds, against what this page of it has: a
        // browse answers with one page, and the row above already counts the
        // whole thing.
        final held = browseList.total > items.length
            ? browseList.total
            : items.length;
        final paged = held > items.length;
        // A page cannot be added up into the whole, so a partial one defers
        // to the tally the source gave with the container itself.
        final seconds = paged
            ? item.playlist?.duration
            : items.fold<int>(0, (sum, it) => sum + (it.track?.duration ?? 0));
        return Column(
          children: [
            ContainerActionHeader(
              item: item,
              trackIds: [for (final it in items) it.id],
              totalTracks: held,
              totalDurationSeconds: (seconds ?? 0) > 0 ? seconds : null,
              trailing: headerAction,
            ),
            _buildTrackList(items, ref),
            if (paged) _PagedNote(shown: items.length, held: held),
          ],
        );
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
          'Failed to load tracks',
          style: KalinkaTextStyles.trackRowSubtitle,
        ),
      ),
    );
  }

  Widget _buildTrackList(List<BrowseItem> items, WidgetRef ref) {
    return Column(
      children: [
        for (int i = 0; i < items.length; i++) ...[
          _InlineContainerTrack(
            item: items[i],
            index: i + 1,
            containerId: containerId,
          ),
          if (i < items.length - 1)
            const Divider(
              color: KalinkaColors.borderSubtle,
              thickness: 1,
              height: 1,
            ),
        ],
      ],
    );
  }
}

/// The empty state: the label alone, or with the offer to fill the container
/// and the container's own action, in the header's shape.
class _EmptyState extends StatelessWidget {
  final String label;
  final Widget? action;
  final Widget? trailing;

  const _EmptyState({required this.label, this.action, this.trailing});

  @override
  Widget build(BuildContext context) {
    if (action == null && trailing == null) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: Text(label, style: KalinkaTextStyles.trackRowSubtitle),
      );
    }
    return SizedBox(
      width: double.infinity,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 4, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: KalinkaTextStyles.trackRowSubtitle),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: action ?? const SizedBox.shrink(),
                  ),
                ),
                ?trailing,
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Says so where the rows are one page of a longer container. Without it the
/// header's count and the rows below it would disagree, and the shorter of
/// the two numbers is the one that lies.
class _PagedNote extends StatelessWidget {
  final int shown;
  final int held;

  const _PagedNote({required this.shown, required this.held});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      child: Text(
        'Showing the first $shown of $held · Play all takes them all',
        style: KalinkaTextStyles.trackRowSubtitle.copyWith(
          color: KalinkaColors.textMuted,
        ),
      ),
    );
  }
}

class _InlineContainerTrack extends ConsumerStatefulWidget {
  final BrowseItem item;
  final int index;
  final String containerId;

  const _InlineContainerTrack({
    required this.item,
    required this.index,
    required this.containerId,
  });

  @override
  ConsumerState<_InlineContainerTrack> createState() =>
      _InlineContainerTrackState();
}

class _InlineContainerTrackState extends ConsumerState<_InlineContainerTrack>
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
    _flashController.addListener(() => setState(() {}));
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
    final toast = ref.read(toastProvider.notifier);
    toast.beginQueueActivity('Starting playback…');
    try {
      await api.clear();
      final added = await api.add([widget.containerId]);
      await api.play(widget.index - 1);
      final n = added.count ?? 0;
      toast.endQueueActivity('Playing $n ${n == 1 ? 'track' : 'tracks'}');
    } catch (e) {
      // API failed — revert optimistic flash.
      if (mounted) {
        _flashController.reset();
        setState(() => _tappedToPlay = false);
      }
      toast.endQueueActivity('Failed to play: $e', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
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
    final imageUrl =
        widget.item.image?.small ??
        widget.item.image?.thumbnail ??
        widget.item.image?.large;
    final resolvedImageUrl = imageUrl != null
        ? urlResolver.abs(imageUrl)
        : null;

    // Scoped watches so unrelated selection changes don't rebuild the row.
    final selectionMode = ref.watch(
      selectionStateProvider.select((s) => s.isActive),
    );
    final isSelected = ref.watch(
      selectionStateProvider.select(
        (s) => s.selectedIds.contains(widget.item.id),
      ),
    );
    final containerSelected = ref.watch(
      selectionStateProvider.select(
        (s) => s.isContainerSelected(widget.containerId),
      ),
    );
    final trackSelected = ref.watch(
      selectionStateProvider.select(
        (s) =>
            s.isContainerSelected(widget.containerId) &&
            s.isTrackInContainerSelected(widget.containerId, widget.item.id),
      ),
    );
    final inSelectionHighlight = isSelected || trackSelected;

    // Now-playing detection — scope the watch so we don't rebuild on every
    // position tick (PlaybackState.position updates frequently while playing).
    final currentTrackId = ref.watch(
      playerStateProvider.select((s) => s.currentTrack?.id),
    );
    final isCurrentTrack =
        widget.item.id.isNotEmpty && currentTrackId == widget.item.id;

    // Clear optimistic flash once server confirms, or revert if different track.
    ref.listen(playerStateProvider.select((s) => s.currentTrack?.id), (
      prev,
      next,
    ) {
      if (!mounted) return;
      if (next == widget.item.id && _tappedToPlay) {
        setState(() => _tappedToPlay = false);
      } else if (_tappedToPlay && next != null && next != widget.item.id) {
        _flashController.reset();
        setState(() => _tappedToPlay = false);
      }
    });

    // Now-playing row decoration (only outside selection mode).
    final showNowPlaying = !selectionMode && (_tappedToPlay || isCurrentTrack);
    final Color rowBg;
    if (selectionMode && inSelectionHighlight) {
      rowBg = KalinkaColors.accent.withValues(alpha: 0.07);
    } else if (showNowPlaying && _flashController.isAnimating) {
      rowBg = _flashColorAnim.value ?? Colors.transparent;
    } else if (showNowPlaying) {
      rowBg = KalinkaColors.accentSubtle;
    } else {
      rowBg = Colors.transparent;
    }

    // The left-edge mark, for a selected row and for the playing one alike
    // (never both — a selection hides the now-playing dress). It is drawn
    // over the row rather than as a Border, which would push the artwork
    // right by its own width.
    final Color? barColor = selectionMode && inSelectionHighlight
        ? KalinkaColors.accent
        : showNowPlaying
        ? KalinkaColors.accentBorder
        : null;

    return SwipeToActRow(
      enabled: !selectionMode,
      onAddToQueue: () => addTrackToQueue(widget.item),
      onPlayNext: () => playTrackNext(widget.item),
      child: GestureDetector(
        onTap: () {
          if (selectionMode) {
            if (containerSelected) {
              ref
                  .read(selectionStateProvider.notifier)
                  .toggleTrackInContainer(widget.containerId, widget.item.id);
            } else {
              ref.read(selectionStateProvider.notifier).toggle(widget.item.id);
            }
          } else {
            _playTrack();
          }
        },
        onLongPressStart: selectionMode
            ? null
            : (_) => startLongPressRing(
                () => ref
                    .read(selectionStateProvider.notifier)
                    .selectSingleTrackInContainer(
                      widget.containerId,
                      widget.item.id,
                    ),
              ),
        onLongPressEnd: selectionMode ? null : (_) => cancelLongPressRing(),
        onLongPressCancel: selectionMode ? null : cancelLongPressRing,
        behavior: HitTestBehavior.opaque,
        child: Stack(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              // Right 8 lands the duration on the chevrons' right edge.
              padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
              decoration: BoxDecoration(color: rowBg),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Artwork + selection overlay (search-results style)
                  SizedBox(
                    width: 44,
                    height: 44,
                    child: Stack(
                      fit: StackFit.expand,
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
                                  errorBuilder: (_, _, _) =>
                                      ProceduralAlbumArt(
                                        trackId: widget.item.id,
                                        size: 44,
                                      ),
                                )
                              : ProceduralAlbumArt(
                                  trackId: widget.item.id,
                                  size: 44,
                                ),
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
                        if (selectionMode && inSelectionHighlight)
                          Container(
                            decoration: BoxDecoration(
                              color: KalinkaColors.accent.withValues(
                                alpha: 0.4,
                              ),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Icon(
                              Icons.check,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          style: KalinkaTextStyles.trackRowTitle.copyWith(
                            color:
                                selectionMode &&
                                    containerSelected &&
                                    !trackSelected
                                ? KalinkaColors.textSecondary
                                : null,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        if (subtitle.isNotEmpty)
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              if (sourceBadgeVisible(ref, widget.item.id)) ...[
                                SourceBadge(
                                  entityId: widget.item.id,
                                  size: SourceBadgeSize.small,
                                ),
                                const SizedBox(width: 6),
                              ],
                              Expanded(
                                child: Text(
                                  subtitle,
                                  style: KalinkaTextStyles.trackRowSubtitle
                                      .copyWith(
                                        color:
                                            selectionMode &&
                                                containerSelected &&
                                                !trackSelected
                                            ? KalinkaColors.textMuted
                                            : null,
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
                  if (!selectionMode)
                    TrackRowTrailing(
                      duration: duration,
                      current: isCurrentTrack,
                    ),
                ],
              ),
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
