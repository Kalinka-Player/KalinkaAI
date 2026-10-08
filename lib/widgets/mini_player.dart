import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data_model/data_model.dart';
import '../data_model/kalinka_ws_api.dart';
import '../data_model/playqueue_events.dart';
import '../providers/app_state_provider.dart';
import '../providers/connection_state_provider.dart';
import '../providers/kalinka_ws_api_provider.dart';
import '../providers/playback_time_provider.dart';
import '../providers/url_resolver.dart';
import '../theme/app_theme.dart';
import '../utils/haptics.dart';
import '../utils/playback_utils.dart';
import 'bit_perfect_badge.dart';
import 'gradient_progress_line.dart';
import 'play_pause_glyph.dart';
import 'procedural_album_art.dart';
import 'renderer_switcher.dart';
import 'source_badge.dart';
import 'transport_button.dart';

/// How long the mini-player takes to slide down out of view when the search
/// entry overlay opens (and to slide back up on close). The search view holds
/// the keyboard back by this long so the bar clears first.
const Duration kMiniPlayerHideDuration = Duration(milliseconds: 260);

/// Fixed bottom mini player — 72px tall plus safe area inset. Stays put on the
/// search screen too; playback controls remain reachable while browsing.
///
/// Swipe gestures:
/// - Swipe left  = next track (with resistance; haptic + auto-complete at 1/3)
/// - Swipe right = previous track
/// - Swipe up    = open now-playing overlay (same as tap)
///
/// Only the track title/artist text participates in the carousel slide.
/// Album art and play/pause button remain stationary.
class MiniPlayer extends ConsumerStatefulWidget {
  final VoidCallback? onTap;

  /// Marks the output switcher for the first-run tour. Lives here on phone;
  /// the tablet layout has no mini-player and keys its Now Playing header
  /// switcher instead.
  final Key? outputSwitcherKey;

  const MiniPlayer({super.key, this.onTap, this.outputSwitcherKey});

  @override
  ConsumerState<MiniPlayer> createState() => _MiniPlayerState();
}

class _MiniPlayerState extends ConsumerState<MiniPlayer>
    with TickerProviderStateMixin {
  // ── Carousel swipe state ──────────────────────────────────────────────────
  /// Normalized offset: -1.0 = next track centred, 0 = current, +1.0 = prev centred.
  late AnimationController _carouselController;

  /// Width of the text area, cached from LayoutBuilder each frame.
  double _textAreaWidth = 200.0;

  /// Swipe direction lock: null = idle, true = going next (left), false = going prev (right).
  bool? _swipeIsNext;
  bool _swipeHapticFired = false;
  Track? _incomingTrackSnapshot;
  Track? _latchedCurrentTrack;
  PlayQueueState? _swipeStartState;
  PlayQueueState? _pendingSwipeState;
  Timer? _previewTimeout;
  int _swipeRequestId = 0;

  /// True while the auto-complete animation is running so gesture updates are ignored.
  bool _committed = false;

  /// Visual gap between adjacent track slots as a fraction of textAreaWidth.
  /// 1.0 keeps track slots fully separated to avoid text overlap while swiping.
  static const double _carouselGap = 1.15;

  /// Auto-commit threshold as a fraction of the configured gap.
  static const double _commitThreshold = 0.3;

  /// Content moves at 70% of finger speed — gives a tactile "dragging against something" feel.
  static const double _carouselResistance = 0.70;

  @override
  void initState() {
    super.initState();
    _carouselController = AnimationController(
      vsync: this,
      lowerBound: -1.2,
      upperBound: 1.2,
      duration: const Duration(milliseconds: 250),
    );
    _carouselController.value =
        0.0; // AnimationController defaults to lowerBound
    _carouselController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _previewTimeout?.cancel();
    _carouselController.dispose();
    super.dispose();
  }

  // ── Gesture handlers ──────────────────────────────────────────────────────

  void _onHorizontalDragStart(DragStartDetails _) {
    if (_committed) return;
    _carouselController.stop();
    _swipeIsNext = null;
    _swipeHapticFired = false;
    _incomingTrackSnapshot = null;
    _swipeStartState = null;
  }

  void _onHorizontalDragUpdate(DragUpdateDetails d) {
    if (_committed) return;

    final normalizedDelta = d.delta.dx / _textAreaWidth;

    // Lock direction on first meaningful movement.
    if (_swipeIsNext == null && normalizedDelta.abs() > 0.001) {
      setState(() {
        _swipeIsNext = normalizedDelta < 0; // left = next
        _swipeStartState = ref.read(playQueueStateStoreProvider);
        _incomingTrackSnapshot = _peekIncomingTrack(_swipeIsNext!);
      });
    }

    var newOffset =
        _carouselController.value + normalizedDelta * _carouselResistance;

    // Prevent reversing direction mid-swipe; clamp to the gap range.
    if (_swipeIsNext == true) {
      newOffset = newOffset.clamp(-_carouselGap, 0.0);
    } else if (_swipeIsNext == false) {
      newOffset = newOffset.clamp(0.0, _carouselGap);
    }

    _carouselController.value = newOffset; // triggers addListener → setState

    if (!_swipeHapticFired &&
        newOffset.abs() >= _carouselGap * _commitThreshold) {
      _swipeHapticFired = true;
      KalinkaHaptics.selectionClick();
      _autoComplete();
    }
  }

  void _onHorizontalDragEnd(DragEndDetails _) {
    if (_committed) return;
    _snapBack();
  }

  void _onHorizontalDragCancel() {
    if (!_committed && _swipeIsNext != null) _snapBack();
  }

  // A neighbour preview is valid only for the queue and playback position it
  // came from. Insertions, shuffle, renderer changes, or a skipped track can
  // make the server choose a different track from the one we predicted.
  bool _sameQueuePosition(PlayQueueState a, PlayQueueState b) =>
      identical(a.trackList, b.trackList) &&
      a.playbackState.index == b.playbackState.index &&
      a.playbackState.currentTrack?.id == b.playbackState.currentTrack?.id &&
      a.playbackControl == b.playbackControl &&
      a.currentRendererId == b.currentRendererId;

  void _releaseTrackPreview() {
    _previewTimeout?.cancel();
    _previewTimeout = null;
    if (_latchedCurrentTrack == null) return;
    setState(() {
      _latchedCurrentTrack = null;
      _pendingSwipeState = null;
    });
  }

  Future<void> _sendSwipeCommand(QueueCommand command, int requestId) async {
    try {
      await ref.read(kalinkaWsApiProvider).sendQueueCommand(command);
    } catch (error) {
      debugPrint('MiniPlayer swipe command failed: $error');
      if (mounted && requestId == _swipeRequestId) _releaseTrackPreview();
    }
  }

  /// Animates the carousel to ±1.0, sends the queue command, then resets.
  void _autoComplete() {
    if (_committed) return;
    _committed = true;

    final target = _swipeIsNext == true ? -_carouselGap : _carouselGap;
    final remaining = (target - _carouselController.value).abs();
    // Duration scales with remaining distance so fast mid-swipe feels instant.
    final ms = (remaining * 200.0).round().clamp(60, 280);

    _carouselController
        .animateTo(
          target,
          duration: Duration(milliseconds: ms),
          curve: Curves.easeOut,
        )
        .then((_) {
          if (!mounted) return;
          final connectionState = ref.read(connectionStateProvider);
          final isOffline =
              connectionState == ConnectionStatus.reconnecting ||
              connectionState == ConnectionStatus.offline;
          final command = _swipeIsNext == true
              ? const QueueCommand.next()
              : const QueueCommand.prev();
          final queueState = ref.read(playQueueStateStoreProvider);
          final previewIsValid =
              !isOffline &&
              _swipeStartState != null &&
              _sameQueuePosition(_swipeStartState!, queueState);
          // Reset carousel to centre; new track info arrives via WebSocket.
          setState(() {
            if (previewIsValid && _incomingTrackSnapshot != null) {
              _latchedCurrentTrack = _incomingTrackSnapshot;
              _pendingSwipeState = queueState;
              // Commands have no acknowledgement. A no-op or lost response
              // must not leave stale metadata and disabled swipes forever.
              _previewTimeout = Timer(const Duration(seconds: 2), () {
                debugPrint(
                  'MiniPlayer swipe preview expired; using queue state',
                );
                _releaseTrackPreview();
              });
            }
            _committed = false;
            _swipeIsNext = null;
            _swipeHapticFired = false;
            _incomingTrackSnapshot = null;
            _swipeStartState = null;
          });
          _carouselController.value = 0.0;
          if (!isOffline) {
            unawaited(_sendSwipeCommand(command, ++_swipeRequestId));
          }
        });
  }

  /// User released before the commit threshold — snap text back to centre.
  void _snapBack() {
    setState(() {
      _swipeIsNext = null;
      _swipeHapticFired = false;
      _incomingTrackSnapshot = null;
      _swipeStartState = null;
    });
    _carouselController.animateTo(
      0.0,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
  }

  Track? _peekIncomingTrack(bool isNext) {
    final queueState = ref.read(playQueueStateStoreProvider);
    // A plugin's playback has no queue neighbours to preview.
    if (queueState.playbackControl.isExclusive) return null;
    final trackList = queueState.trackList;
    final currentIndex = queueState.playbackState.index ?? 0;

    final hasCurrentInQueue =
        currentIndex >= 0 && currentIndex < trackList.length;
    if (!hasCurrentInQueue) {
      return null;
    }

    if (isNext) {
      return currentIndex + 1 < trackList.length
          ? trackList[currentIndex + 1]
          : null;
    }
    return currentIndex > 0 ? trackList[currentIndex - 1] : null;
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(playQueueStateStoreProvider, (_, next) {
      final pending = _pendingSwipeState;
      if (pending != null &&
          (!_sameQueuePosition(pending, next) ||
              next.playbackState.state == PlayerStateType.error)) {
        _releaseTrackPreview();
      }
    });
    ref.listen(connectionStateProvider, (_, next) {
      if (next == ConnectionStatus.offline ||
          next == ConnectionStatus.reconnecting) {
        _releaseTrackPreview();
      }
    });
    final queueSnapshot = ref.watch(
      playQueueStateStoreProvider.select(
        (s) => (
          trackList: s.trackList,
          playbackIndex: s.playbackState.index ?? 0,
          playerState: s.playbackState.state,
          fallbackTrackId: s.playbackState.currentTrack?.id,
          fallbackTrackTitle: s.playbackState.currentTrack?.title,
          fallbackTrackArtist: s.playbackState.currentTrack?.performer?.name,
          fallbackTrackDurationSec: s.playbackState.currentTrack?.duration ?? 0,
          fallbackTrackImageSmall:
              s.playbackState.currentTrack?.album?.image?.small ??
              s.playbackState.currentTrack?.album?.image?.thumbnail ??
              s.playbackState.currentTrack?.album?.image?.large,
          fallbackDurationMs: s.playbackState.audioInfo?.durationMs ?? 0,
          errorMessage: s.playbackState.message,
          exclusive: s.playbackControl.isExclusive,
        ),
      ),
    );
    final trackList = queueSnapshot.trackList;
    final playbackIndex = queueSnapshot.playbackIndex;
    final exclusive = queueSnapshot.exclusive;

    // A plugin's playback is not in the queue: its track is the state's own,
    // and shows even with an empty queue.
    Track? currentTrack;
    if (!exclusive && playbackIndex >= 0 && playbackIndex < trackList.length) {
      currentTrack = trackList[playbackIndex];
    } else if ((exclusive || trackList.isNotEmpty) &&
        queueSnapshot.fallbackTrackId != null) {
      currentTrack = Track(
        id: queueSnapshot.fallbackTrackId!,
        title: queueSnapshot.fallbackTrackTitle ?? 'No track',
        duration: queueSnapshot.fallbackTrackDurationSec,
        performer: queueSnapshot.fallbackTrackArtist == null
            ? null
            : Artist(id: '', name: queueSnapshot.fallbackTrackArtist!),
        album: queueSnapshot.fallbackTrackImageSmall == null
            ? null
            : Album(
                id: '',
                title: '',
                image: AlbumImage(small: queueSnapshot.fallbackTrackImageSmall),
              ),
      );
    }

    final effectiveCurrentTrack = _latchedCurrentTrack ?? currentTrack;
    final playerState = queueSnapshot.playerState;
    final urlResolver = ref.read(urlResolverProvider);

    // Queue peek for carousel incoming-track preview.
    final currentIndex = playbackIndex;
    final hasCurrentInQueue =
        !exclusive && currentIndex >= 0 && currentIndex < trackList.length;
    final nextTrack = hasCurrentInQueue && currentIndex + 1 < trackList.length
        ? trackList[currentIndex + 1]
        : null;
    final prevTrack = hasCurrentInQueue && currentIndex > 0
        ? trackList[currentIndex - 1]
        : null;
    final incomingTrack = _swipeIsNext == null
        ? null
        : _incomingTrackSnapshot ??
              (_swipeIsNext == true ? nextTrack : prevTrack);

    final connectionState = ref.watch(connectionStateProvider);
    final isOffline =
        connectionState == ConnectionStatus.reconnecting ||
        connectionState == ConnectionStatus.offline;
    final progressLineMode = connectionState == ConnectionStatus.reconnecting
        ? GradientProgressLineMode.reconnecting
        : connectionState == ConnectionStatus.offline
        ? GradientProgressLineMode.offline
        : GradientProgressLineMode.normal;

    final durationMs = exclusive && queueSnapshot.fallbackDurationMs > 0
        ? queueSnapshot.fallbackDurationMs
        : (effectiveCurrentTrack?.duration ?? 0) * 1000;

    final imageUrl =
        effectiveCurrentTrack?.album?.image?.small ??
        effectiveCurrentTrack?.album?.image?.thumbnail ??
        effectiveCurrentTrack?.album?.image?.large;
    final resolvedImageUrl = imageUrl != null
        ? urlResolver.abs(imageUrl)
        : null;

    final carouselOffset = _carouselController.value; // -1..1

    return Container(
      decoration: const BoxDecoration(
        color: KalinkaColors.surfaceRaised,
        border: Border(
          top: BorderSide(color: KalinkaColors.borderDefault, width: 1),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildProgressLine(progressLineMode, durationMs),
            _buildMainContent(
              resolvedImageUrl: resolvedImageUrl,
              currentTrack: effectiveCurrentTrack,
              incomingTrack: incomingTrack,
              carouselOffset: carouselOffset,
              isOffline: isOffline,
              playerState: playerState,
              exclusive: exclusive,
            ),
          ],
        ),
      ),
    );
  }

  /// 2px progress line pinned above the main content. Uses its own [Consumer]
  /// so only the line rebuilds when playback time ticks.
  Widget _buildProgressLine(GradientProgressLineMode mode, int durationMs) {
    return RepaintBoundary(
      child: Consumer(
        builder: (context, ref, _) {
          final playbackTimeMs = ref.watch(playbackTimeMsProvider);
          final progress = durationMs > 0
              ? (playbackTimeMs / durationMs).clamp(0.0, 1.0)
              : 0.0;
          return GradientProgressLine(progress: progress, mode: mode);
        },
      ),
    );
  }

  /// 70px row containing album art, the swipe-capable carousel text, and the
  /// play/pause button. Owns the horizontal/vertical gesture detection that
  /// drives the carousel and the swipe-up-to-open gesture.
  Widget _buildMainContent({
    required String? resolvedImageUrl,
    required Track? currentTrack,
    required Track? incomingTrack,
    required double carouselOffset,
    required bool isOffline,
    required PlayerStateType? playerState,
    required bool exclusive,
  }) {
    final canSwipe = _latchedCurrentTrack == null;
    return AnimatedOpacity(
      opacity: isOffline ? 0.45 : 1.0,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
      child: SizedBox(
        height: 70,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              // Only art + text take the tap-to-open / swipe gestures; the
              // play button stays outside so the swipe recognizer can't steal
              // its taps.
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: widget.onTap,
                  onHorizontalDragStart: canSwipe
                      ? _onHorizontalDragStart
                      : null,
                  onHorizontalDragUpdate: canSwipe
                      ? _onHorizontalDragUpdate
                      : null,
                  onHorizontalDragEnd: canSwipe ? _onHorizontalDragEnd : null,
                  onHorizontalDragCancel: canSwipe
                      ? _onHorizontalDragCancel
                      : null,
                  onVerticalDragEnd: (d) {
                    // Swipe up → open now-playing
                    if ((d.primaryVelocity ?? 0) < -200) widget.onTap?.call();
                  },
                  child: Row(
                    children: [
                      _buildAlbumArt(
                        resolvedImageUrl: resolvedImageUrl,
                        trackId: currentTrack?.id ?? '',
                      ),
                      const SizedBox(width: 10),
                      _buildCarouselText(
                        currentTrack: currentTrack,
                        incomingTrack: incomingTrack,
                        carouselOffset: carouselOffset,
                      ),
                    ],
                  ),
                ),
              ),
              if (currentTrack != null) const BitPerfectBadge(),
              const SizedBox(width: 4),
              // Outside the gesture area too, for the same reason as the play
              // button: the swipe recognizer must not steal its taps.
              IgnorePointer(
                ignoring: isOffline,
                child: RendererSwitcherButton(
                  key: widget.outputSwitcherKey,
                  hitDiameter: 40,
                  iconSize: 20,
                ),
              ),
              const SizedBox(width: 4),
              _buildPlayPauseButton(
                playerState: playerState,
                isOffline: isOffline,
                hasTrack: currentTrack != null,
                exclusive: exclusive,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 46×46 album thumbnail. Uses [Image.network] when a URL is available,
  /// falling back to [ProceduralAlbumArt] on load error or when no art URL
  /// exists at all.
  Widget _buildAlbumArt({
    required String? resolvedImageUrl,
    required String trackId,
  }) {
    return Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(8)),
      clipBehavior: Clip.antiAlias,
      child: resolvedImageUrl != null
          ? Image.network(
              resolvedImageUrl,
              width: 46,
              height: 46,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) =>
                  ProceduralAlbumArt(trackId: trackId, size: 46),
            )
          : ProceduralAlbumArt(trackId: trackId, size: 46),
    );
  }

  /// Carousel text area: current track label (slides during swipe, instant
  /// swap on track change) plus an optional incoming-track label that slides
  /// in from the opposite edge. [LayoutBuilder] caches the width into
  /// [_textAreaWidth] so gesture handlers can normalise horizontal deltas.
  Widget _buildCarouselText({
    required Track? currentTrack,
    required Track? incomingTrack,
    required double carouselOffset,
  }) {
    return Expanded(
      child: LayoutBuilder(
        builder: (context, constraints) {
          _textAreaWidth = math.max(constraints.maxWidth, 1.0);
          return ClipRect(
            child: Stack(
              children: [
                Transform.translate(
                  offset: Offset(carouselOffset * _textAreaWidth, 0),
                  child: _TrackLabel(
                    title: currentTrack?.title,
                    subtitle: currentTrack?.performer?.name,
                    entityId: currentTrack?.id,
                  ),
                ),
                if (incomingTrack != null)
                  Transform.translate(
                    offset: Offset(
                      _swipeIsNext == true
                          // Next: enters from the right
                          ? (carouselOffset + _carouselGap) * _textAreaWidth
                          // Prev: enters from the left
                          : (carouselOffset - _carouselGap) * _textAreaWidth,
                      0,
                    ),
                    child: _TrackLabel(
                      title: incomingTrack.title,
                      subtitle: incomingTrack.performer?.name,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      entityId: incomingTrack.id,
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// Stationary 46×46 play/pause control sharing the now-playing
  /// [TransportButton] (InkWell ripple + press-scale feedback). Disabled when
  /// the player state doesn't allow toggling, fully ignored while offline, and
  /// greyed out when there's no track loaded.
  Widget _buildPlayPauseButton({
    required PlayerStateType? playerState,
    required bool isOffline,
    required bool hasTrack,
    required bool exclusive,
  }) {
    final disabled =
        !hasTrack || isPlayPauseDisabled(playerState, exclusive: exclusive);
    return IgnorePointer(
      ignoring: isOffline,
      child: Opacity(
        opacity: hasTrack ? 1.0 : 0.4,
        child: TransportButton(
          hitDiameter: 46,
          background: Colors.white,
          // Ripple has to read against the white face, so use a dark tint.
          splashColor: KalinkaColors.background.withValues(alpha: 0.18),
          highlightColor: KalinkaColors.background.withValues(alpha: 0.08),
          onTap: disabled
              ? null
              : () => sendPlayPauseCommand(
                  ref,
                  playerState,
                  exclusive: exclusive,
                ),
          // Fixed 26×26 glyph slot keeps visual weight stable across states
          // and prevents the spinner from appearing offset against the icon.
          child: SizedBox(
            width: 26,
            height: 26,
            child: PlayPauseGlyph(
              playerState: playerState,
              iconSize: 26,
              spinnerSize: 22,
            ),
          ),
        ),
      ),
    );
  }
}

/// Single text block for the carousel: title + subtitle + optional source badge.
/// Uses [SizedBox.expand] so it fills the slot and clips correctly inside [ClipRect].
class _TrackLabel extends ConsumerWidget {
  final String? title;
  final String? subtitle;
  final CrossAxisAlignment crossAxisAlignment;

  /// When set, a [SourceBadge] is appended to the subtitle line.
  final String? entityId;

  const _TrackLabel({
    this.title,
    this.subtitle,
    this.crossAxisAlignment = CrossAxisAlignment.start,
    this.entityId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final titleStyle = KalinkaTextStyles.miniPlayerTitle;
    final subtitleStyle = KalinkaTextStyles.miniPlayerArtist;

    return SizedBox.expand(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: crossAxisAlignment,
        children: [
          Text(
            title ?? 'No track',
            style: titleStyle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (entityId != null && sourceBadgeVisible(ref, entityId!)) ...[
                SourceBadge(
                  entityId: entityId!,
                  size: SourceBadgeSize.standard,
                ),
                const SizedBox(width: 4),
              ],
              Flexible(
                child: Text(
                  subtitle ?? '\u2014',
                  style: subtitleStyle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
