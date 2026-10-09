import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data_model/data_model.dart';
import '../../providers/app_state_provider.dart';
import '../../providers/browse_detail_provider.dart';
import '../../providers/kalinka_player_api_provider.dart';
import '../../providers/row_expansion_provider.dart';
import '../../providers/selection_state_provider.dart';
import '../../providers/url_resolver.dart';
import '../../theme/app_theme.dart';
import '../../utils/play_next.dart';
import '../procedural_album_art.dart';
import '../source_badge.dart';
import '../swipe_to_act_row.dart';
import 'long_press_ring_painter.dart';
import '../../providers/toast_provider.dart';
import 'expand_chevron_button.dart';
import 'search_album_row.dart';
import 'track_row_support.dart';

const _dimmedColor = Color(0xFF48485A);

/// Luma-weighted grayscale for the artist avatar while multi-select is
/// active — artists aren't selectable, so they drop to black & white.
const ColorFilter _grayscaleFilter = ColorFilter.matrix(<double>[
  0.2126, 0.7152, 0.0722, 0, 0, //
  0.2126, 0.7152, 0.0722, 0, 0, //
  0.2126, 0.7152, 0.0722, 0, 0, //
  0, 0, 0, 1, 0,
]);

/// Artist row for search results.
/// Collapsed: 52x52 circular avatar, name, stats, Top Tracks + Browse buttons.
/// Browse expands into a two-level tree: album rows with inline track lists.
class SearchArtistRow extends ConsumerStatefulWidget {
  final BrowseItem item;

  const SearchArtistRow({super.key, required this.item});

  @override
  ConsumerState<SearchArtistRow> createState() => _SearchArtistRowState();
}

class _SearchArtistRowState extends ConsumerState<SearchArtistRow> {
  void _toggleExpand() {
    ref.read(rowExpansionProvider.notifier).toggleArtist(widget.item.id);
  }

  @override
  Widget build(BuildContext context) {
    final isExpanded = ref.watch(
      rowExpansionProvider.select((s) => s.artists.contains(widget.item.id)),
    );
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

    return Column(
      children: [
        // Artist header row
        GestureDetector(
          onTap: selectionMode ? null : _toggleExpand,
          onLongPress: () {
            showSafeToast('Artists can’t be multi-selected');
          },
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            // Right 0 keeps the chevron on the shared right-edge line.
            padding: EdgeInsets.only(
              top: 10,
              bottom: 10,
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
                        color: KalinkaColors.gold.withValues(alpha: 0.40),
                        width: 3,
                      ),
                    )
                  : null,
            ),
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
                                  errorBuilder: (_, __, ___) =>
                                      ProceduralAlbumArt(
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
                              if (sourceBadgeVisible(ref, widget.item.id)) ...[
                                SourceBadge(entityId: widget.item.id),
                                const SizedBox(width: 6),
                              ],
                              Expanded(
                                child: Text.rich(
                                  entityTypeSubtitle('Artist', stats),
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
                    // Chevron button
                    IgnorePointer(
                      ignoring: selectionMode,
                      child: ExpandChevronButton(
                        isExpanded: isExpanded,
                        onTap: _toggleExpand,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        // Expanded section
        AnimatedCrossFade(
          firstChild: const SizedBox.shrink(),
          secondChild: isExpanded
              ? _ArtistExpansionContent(
                  artistId: widget.item.id,
                  artistName: artist?.name ?? widget.item.name ?? 'Unknown',
                )
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

// ---------------------------------------------------------------------------
// Expansion content: album rows + singles + "N more" row
// ---------------------------------------------------------------------------

class _ArtistExpansionContent extends ConsumerWidget {
  final String artistId;
  final String artistName;

  const _ArtistExpansionContent({
    required this.artistId,
    required this.artistName,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final browseAsync = ref.watch(browseDetailProvider(artistId));
    final showAllAlbums = ref.watch(
      rowExpansionProvider.select((s) => s.artistMoreAlbums.contains(artistId)),
    );

    return Padding(
      padding: const EdgeInsets.only(left: 16),
      child: browseAsync.when(
        data: (browseList) {
          final allItems = browseList.items;
          // Separate browsable albums from loose tracks
          final albums = allItems.where((item) => item.canBrowse).toList();
          final looseTracks = allItems
              .where((item) => item.track != null && !item.canBrowse)
              .toList();

          // Determine albums to display
          final maxInitial = albums.length > 4 ? 3 : albums.length;
          final displayAlbums = showAllAlbums
              ? albums
              : albums.take(maxInitial).toList();
          final moreCount = albums.length - maxInitial;

          if (albums.isEmpty && looseTracks.isEmpty) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'No albums found',
                style: KalinkaTextStyles.trackRowSubtitle,
              ),
            );
          }

          return Column(
            children: [
              // Album rows — reuse the same SearchAlbumRow as top-level
              for (int i = 0; i < displayAlbums.length; i++) ...[
                SearchAlbumRow(item: displayAlbums[i]),
                if (i < displayAlbums.length - 1)
                  const Divider(
                    color: KalinkaColors.borderSubtle,
                    thickness: 1,
                    height: 1,
                  ),
              ],
              // "N more albums" row
              if (!showAllAlbums && moreCount > 0)
                GestureDetector(
                  onTap: () => ref
                      .read(rowExpansionProvider.notifier)
                      .revealArtistMoreAlbums(artistId),
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    child: Text(
                      '\u00B7\u00B7\u00B7 $moreCount more ${moreCount == 1 ? 'album' : 'albums'}',
                      style: KalinkaTextStyles.showMoreLabel,
                    ),
                  ),
                ),
              // Singles & Loose Tracks
              if (looseTracks.isNotEmpty)
                _SinglesSection(
                  tracks: looseTracks,
                  artistId: artistId,
                  artistName: artistName,
                ),
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
            'Failed to load albums',
            style: KalinkaTextStyles.trackRowSubtitle,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Individual track row within album expansion (used by _SinglesSection)
// ---------------------------------------------------------------------------

class _ArtistTrackRow extends ConsumerStatefulWidget {
  final BrowseItem item;
  final int index;
  final String containerId;
  final bool siblingIsPlaying;

  const _ArtistTrackRow({
    required this.item,
    required this.index,
    required this.containerId,
    required this.siblingIsPlaying,
  });

  @override
  ConsumerState<_ArtistTrackRow> createState() => _ArtistTrackRowState();
}

class _ArtistTrackRowState extends ConsumerState<_ArtistTrackRow>
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
    try {
      if (widget.containerId.startsWith('singles_')) {
        await api.replace([widget.item.id]);
        // Explicit index 0 avoids a backend race where a stale FINISHED event
        // from the just-cleared stream advances current_track_id before play().
        await api.play(0);
      } else {
        await api.replace([widget.containerId]);
        await api.play(widget.index - 1);
      }
    } catch (e) {
      // API failed — revert optimistic flash.
      if (mounted) {
        _flashController.reset();
        setState(() => _tappedToPlay = false);
      }
      showSafeToast('Failed to play: $e', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final track = widget.item.track;
    final title = track?.title ?? widget.item.name ?? 'Unknown';
    final duration = formatTrackDuration(
      track?.duration != null ? track!.duration * 1000 : null,
    );

    // Scoped watches so unrelated selection changes don't rebuild the row.
    // Loose tracks select individually — the 'singles_<artistId>' key is
    // synthetic and has no browseDetailProvider backing.
    final selectionMode = ref.watch(
      selectionStateProvider.select((s) => s.isActive),
    );
    final inSelectionHighlight = ref.watch(
      selectionStateProvider.select(
        (s) => s.selectedIds.contains(widget.item.id),
      ),
    );

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

    // Now-playing row decoration
    final showNowPlaying = !selectionMode && (_tappedToPlay || isCurrentTrack);
    final Color rowBg;
    if (selectionMode && inSelectionHighlight) {
      rowBg = KalinkaColors.accent.withValues(alpha: 0.05);
    } else if (showNowPlaying && _flashController.isAnimating) {
      rowBg = _flashColorAnim.value ?? Colors.transparent;
    } else if (showNowPlaying) {
      rowBg = KalinkaColors.accentSubtle;
    } else {
      rowBg = Colors.transparent;
    }

    // Left-edge indicator bar drawn as an overlay so it doesn't push content
    // right the way a Border would.
    final Color? barColor = showNowPlaying ? KalinkaColors.accentBorder : null;

    // Sibling dimming: animated fade-in (200ms), instant restore.
    final dimmed = widget.siblingIsPlaying && !selectionMode;
    final dimDuration = Duration(milliseconds: dimmed ? 200 : 0);

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
        behavior: HitTestBehavior.opaque,
        child: Stack(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              // Right 8 lands the duration on the chevrons' right edge.
              padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
              decoration: BoxDecoration(color: rowBg),
              child: AnimatedOpacity(
                opacity: dimmed ? 0.7 : 1.0,
                duration: dimDuration,
                curve: Curves.easeOut,
                child: Row(
                  children: [
                    // Track number / long-press indicator / selection icon
                    SizedBox(
                      width: 24,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          if (selectionMode)
                            Icon(
                              inSelectionHighlight
                                  ? Icons.check_circle
                                  : Icons.radio_button_unchecked,
                              size: 16,
                              color: inSelectionHighlight
                                  ? KalinkaColors.accent
                                  : KalinkaColors.textSecondary,
                            )
                          else
                            Text(
                              '${widget.index}',
                              style: KalinkaTextStyles.trackRowSubtitle,
                              textAlign: TextAlign.center,
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
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Title
                    Expanded(
                      child: Text(
                        title,
                        style: KalinkaTextStyles.trackRowTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    // Duration
                    if (!selectionMode && duration != null)
                      Text(duration, style: KalinkaTextStyles.trackRowSubtitle),
                  ],
                ),
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

// ---------------------------------------------------------------------------
// Singles & Loose Tracks pseudo-album section
// ---------------------------------------------------------------------------

class _SinglesSection extends ConsumerStatefulWidget {
  final List<BrowseItem> tracks;
  final String artistId;
  final String artistName;

  const _SinglesSection({
    required this.tracks,
    required this.artistId,
    required this.artistName,
  });

  @override
  ConsumerState<_SinglesSection> createState() => _SinglesSectionState();
}

class _SinglesSectionState extends ConsumerState<_SinglesSection>
    with LongPressRingMixin {
  bool _expanded = false;

  /// Loose tracks have no real container, so "select the whole singles bucket"
  /// is just selecting/clearing every loose track id individually.
  void _toggleSelectAll(bool anySelected) {
    final ids = widget.tracks.map((t) => t.id);
    final notifier = ref.read(selectionStateProvider.notifier);
    if (anySelected) {
      notifier.deselectTracks(ids);
    } else {
      notifier.selectTracks(ids);
    }
  }

  Future<void> _addToQueue() async {
    final api = ref.read(kalinkaProxyProvider);
    final ids = widget.tracks.map((t) => t.id).toList();
    await runQueueActivity(
      pending: 'Adding to queue…',
      action: () => api.add(ids),
      done: (r) {
        final n = r.count ?? widget.tracks.length;
        return '$n ${n == 1 ? 'track' : 'tracks'} by ${widget.artistName} '
            'added to queue';
      },
      failed: (e) => 'Failed to add: $e',
    );
  }

  Future<void> _playNext() async {
    final api = ref.read(kalinkaProxyProvider);
    final ids = widget.tracks.map((t) => t.id).toList();
    final insertIndex = playNextInsertIndex(ref);
    await runQueueActivity(
      pending: 'Queueing next…',
      action: () => api.add(ids, index: insertIndex),
      done: (r) {
        final n = r.count ?? widget.tracks.length;
        return '$n ${n == 1 ? 'track' : 'tracks'} by ${widget.artistName} '
            'playing next';
      },
      failed: (e) => 'Failed to add: $e',
    );
  }

  @override
  Widget build(BuildContext context) {
    final singlesKey = 'singles_${widget.artistId}';
    final showAllTracks = ref.watch(
      rowExpansionProvider.select(
        (s) => s.albumMoreTracks.contains(singlesKey),
      ),
    );
    final selection = ref.watch(selectionStateProvider);
    final selectionMode = selection.isActive;
    final anySelected = widget.tracks.any(
      (t) => selection.selectedIds.contains(t.id),
    );
    final allSelected =
        widget.tracks.isNotEmpty &&
        widget.tracks.every((t) => selection.selectedIds.contains(t.id));
    final isPartial = anySelected && !allSelected;
    final showSelected = selectionMode && anySelected;

    return Column(
      children: [
        // Singles header row — mirrors SearchAlbumRow (list icon for artwork).
        SwipeToActRow(
          enabled: !selectionMode,
          onAddToQueue: _addToQueue,
          onPlayNext: _playNext,
          child: GestureDetector(
            onTap: () {
              if (selectionMode) {
                _toggleSelectAll(anySelected);
              } else {
                setState(() => _expanded = !_expanded);
              }
            },
            onLongPressStart: selectionMode
                ? null
                : (_) => startLongPressRing(() => _toggleSelectAll(false)),
            onLongPressEnd: selectionMode ? null : (_) => cancelLongPressRing(),
            onLongPressCancel: selectionMode ? null : cancelLongPressRing,
            behavior: HitTestBehavior.opaque,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: EdgeInsets.only(
                top: 8,
                bottom: 8,
                left: _expanded || showSelected ? 0 : 3,
                right: 0,
              ),
              decoration: BoxDecoration(
                color: showSelected
                    ? KalinkaColors.accent.withValues(alpha: 0.07)
                    : _expanded
                    ? KalinkaColors.surfaceRaised
                    : Colors.transparent,
                border: showSelected
                    ? const Border(
                        left: BorderSide(color: KalinkaColors.accent, width: 3),
                      )
                    : _expanded
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
                  // List icon, sized like the 60x60 album thumbnail
                  SizedBox(
                    width: 60,
                    height: 60,
                    child: Stack(
                      children: [
                        Container(
                          width: 60,
                          height: 60,
                          decoration: BoxDecoration(
                            color: KalinkaColors.surfaceElevated,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            Icons.queue_music,
                            size: 22,
                            color: _dimmedColor,
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
                        if (showSelected)
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
                  // Title + count
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Singles & Loose Tracks',
                          style: KalinkaTextStyles.trackRowTitle.copyWith(
                            color: showSelected
                                ? KalinkaColors.accentTint
                                : null,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          '${widget.tracks.length} '
                          '${widget.tracks.length == 1 ? 'track' : 'tracks'}',
                          style: KalinkaTextStyles.trackRowSubtitle,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  ExpandChevronButton(
                    isExpanded: _expanded,
                    onTap: () => setState(() => _expanded = !_expanded),
                  ),
                ],
              ),
            ),
          ),
        ),
        // Expanded track list
        AnimatedCrossFade(
          firstChild: const SizedBox.shrink(),
          secondChild: _expanded
              ? _buildTrackList(showAllTracks, ref)
              : const SizedBox.shrink(),
          crossFadeState: _expanded
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

  Widget _buildTrackList(bool showAll, WidgetRef ref) {
    final tracks = widget.tracks;
    final maxInitial = tracks.length > 5 ? 4 : tracks.length;
    final displayTracks = showAll ? tracks : tracks.take(maxInitial).toList();
    final moreCount = tracks.length - maxInitial;
    final singlesKey = 'singles_${widget.artistId}';

    // Sibling dimming, same as the album expansion: when one of these
    // tracks is playing, the others step back.
    final currentTrackId = ref.watch(
      playerStateProvider.select((s) => s.currentTrack?.id),
    );
    final hasPlayingSibling = displayTracks.any((t) => t.id == currentTrackId);

    return Container(
      margin: const EdgeInsets.only(left: 16),
      decoration: const BoxDecoration(
        border: Border(
          left: BorderSide(color: KalinkaColors.borderSubtle, width: 1),
        ),
      ),
      child: Column(
        children: [
          for (int i = 0; i < displayTracks.length; i++) ...[
            _ArtistTrackRow(
              item: displayTracks[i],
              index: i + 1,
              containerId: singlesKey,
              siblingIsPlaying:
                  hasPlayingSibling && displayTracks[i].id != currentTrackId,
            ),
            if (i < displayTracks.length - 1)
              const Divider(
                color: KalinkaColors.borderSubtle,
                thickness: 1,
                height: 1,
              ),
          ],
          if (!showAll && moreCount > 0)
            GestureDetector(
              onTap: () => ref
                  .read(rowExpansionProvider.notifier)
                  .revealAlbumMoreTracks(singlesKey),
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                child: Text(
                  '\u00B7\u00B7\u00B7 $moreCount more ${moreCount == 1 ? 'track' : 'tracks'}',
                  style: KalinkaTextStyles.showMoreLabel,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
