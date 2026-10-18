import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data_model/data_model.dart';
import '../data_model/kalinka_ws_api.dart';
import '../providers/app_state_provider.dart';
import '../providers/connection_state_provider.dart';
import '../providers/kalinka_ws_api_provider.dart';
import '../providers/now_playing_provider.dart';
import '../providers/shell_nav_provider.dart';
import '../providers/url_resolver.dart';
import '../theme/app_theme.dart';
import '../utils/click_cursor.dart';
import '../utils/playback_utils.dart';
import '../providers/source_modules_provider.dart';
import 'bit_perfect_badge.dart';
import 'kalinka_dialog.dart';
import 'kiosk/kiosk_enter_button.dart';
import 'kalinka_toast_overlay.dart' show kMiniPlayerHeight;
import 'mini_player.dart' show AwayDim;
import 'play_pause_glyph.dart';
import 'playback_progress_slider.dart';
import 'player_queue_view.dart';
import 'player_sheet.dart';
import 'player_header.dart';
import 'renderer_switcher.dart';
import 'transport_button.dart';
import 'procedural_album_art.dart';
import 'source_badge.dart';
import 'stream_info_dialog.dart';
import 'volume_control_slider.dart';

/// Core now-playing UI: album art, track info, transport controls, volume.
/// Used embedded in tablet layout and wrapped with animation in phone overlay.
class NowPlayingContent extends ConsumerStatefulWidget {
  /// When true, renders tablet-specific embedded header layout.
  final bool isTablet;

  /// When true, shows drag handle and close button (phone overlay mode).
  final bool showOverlayHeader;

  /// Close callback, used when [showOverlayHeader] is true.
  final VoidCallback? onClose;

  /// Marks the output switcher for the first-run tour. Used by the tablet
  /// layout, where the header's is the only one on screen while the track
  /// shows; the queue's [QueueMiniPlayer] takes the key while the queue does.
  final Key? outputSwitcherKey;

  /// Offered by the queue view while the queue is empty.
  final VoidCallback? onFindMusic;

  const NowPlayingContent({
    super.key,
    this.isTablet = false,
    this.showOverlayHeader = false,
    this.onClose,
    this.outputSwitcherKey,
    this.onFindMusic,
  });

  @override
  ConsumerState<NowPlayingContent> createState() => _NowPlayingContentState();
}

class _NowPlayingContentState extends ConsumerState<NowPlayingContent> {
  @override
  Widget build(BuildContext context) {
    // Use only primitive-typed selectors so Riverpod's == comparison works by
    // value. Object-typed selectors (Track, AudioInfo) fail because play/pause
    // events may produce new instances with identical content but different
    // references, causing false-positive rebuilds of the whole screen.
    // Play/pause/buffering is handled exclusively by _TransportControls.
    ref.watch(
      playerStateProvider.select(
        (s) => (
          trackId: s.currentTrack?.id,
          mimeType: s.mimeType,
          bitsPerSample: s.audioInfo?.bitsPerSample,
          sampleRate: s.audioInfo?.sampleRate,
        ),
      ),
    );
    // Rebuild on any queue change: index/length covers Clear All (currentTrack
    // is sticky), seq covers same-index in-place changes.
    ref.watch(
      playQueueStateStoreProvider.select(
        (s) => (
          length: s.trackList.length,
          index: s.playbackState.index ?? 0,
          seq: s.seq,
        ),
      ),
    );
    ref.watch(playbackControlProvider.select((c) => c.isExclusive));
    final away = ref.watch(
      connectionStateProvider.select((s) => s.isInterrupted),
    );
    // Read full state without watching — content is current because the
    // selectors above already gated the rebuild on a meaningful change.
    final playbackState = ref.read(playerStateProvider);
    final currentTrack = ref.read(nowPlayingTrackProvider);
    final durationMs = ref.read(nowPlayingDurationMsProvider);
    final urlResolver = ref.read(urlResolverProvider);

    final imageUrl = currentTrack?.album?.image?.large;
    final resolvedImageUrl = imageUrl != null
        ? urlResolver.abs(imageUrl)
        : null;

    final mimeLabel = mimeTypeLabel(playbackState.mimeType);
    final qualityLabel = audioQualityLabel(playbackState.audioInfo);

    // Source display info for the attribution line.
    final sourceMap = ref.watch(sourceDisplayInfoProvider);
    final String? currentSource = (() {
      if (currentTrack == null) return null;
      try {
        return EntityId.fromString(currentTrack.id).source;
      } catch (_) {
        return null;
      }
    })();
    final sourceInfo = currentSource != null ? sourceMap[currentSource] : null;

    // The embedded player has no header to switch from, so no queue view.
    final showingQueue =
        (widget.showOverlayHeader || widget.isTablet) &&
        ref.watch(playerViewProvider) == PlayerView.queue;
    if (showingQueue) {
      return Container(
        color: KalinkaColors.background,
        // The list runs on under the host's QueueMiniPlayer.
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              // Only the top drags the phone sheet, so the list scrolls.
              SheetDragArea(child: _buildHeader(showingQueue: true)),
              Expanded(
                child: PlayerQueueView(
                  onFindMusic: widget.onFindMusic,
                  isTablet: widget.isTablet,
                  bottomPadding:
                      kMiniPlayerHeight + MediaQuery.paddingOf(context).bottom,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // All of it drags the phone sheet but what scrolls at large text.
    return SheetDragArea(
      child: Container(
        color: KalinkaColors.background,
        child: SafeArea(
          child: Column(
            children: [
              // Header
              _buildHeader(showingQueue: false),
              // Content — fills remaining space with controls pinned to bottom
              _buildBodyContent(
                currentTrack: currentTrack,
                resolvedImageUrl: resolvedImageUrl,
                sourceInfo: sourceInfo,
                mimeLabel: mimeLabel,
                qualityLabel: qualityLabel,
                durationMs: durationMs,
                away: away,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// While the server is [away], dimmed and without its controls, as the
  /// mini-player is.
  Widget _buildBodyContent({
    required Track? currentTrack,
    required String? resolvedImageUrl,
    required SourceDisplayInfo? sourceInfo,
    required String mimeLabel,
    required String qualityLabel,
    required int durationMs,
    required bool away,
  }) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: LayoutBuilder(
          builder: (context, constraints) {
            // A taller header or enlarged metadata must not push controls past
            // the window. Normal portrait layouts retain flexible artwork;
            // short windows and large text get a scrollable content column.
            final scroll =
                constraints.maxHeight < 440 ||
                MediaQuery.textScalerOf(context)
                        .scale(KalinkaTypography.baseSize) >
                    KalinkaTypography.baseSize * 1.3;
            final artwork = _AlbumArtSection(
              trackId: currentTrack?.id,
              resolvedImageUrl: resolvedImageUrl,
            );
            final content = AwayDim(
              away: away,
              child: Column(
                children: [
                  const SizedBox(height: 8),
                  if (scroll)
                    SizedBox(
                      height: (constraints.maxWidth * 0.72).clamp(0.0, 240.0),
                      child: Column(children: [artwork]),
                    )
                  else
                    artwork,
                  const SizedBox(height: 20),
                  _buildTrackMetadataSection(
                    currentTrack: currentTrack,
                    sourceInfo: sourceInfo,
                    mimeLabel: mimeLabel,
                    qualityLabel: qualityLabel,
                  ),
                  const SizedBox(height: 24),
                  PlaybackProgressSlider(
                    durationMs: durationMs,
                    enabled: currentTrack != null,
                  ),
                  const SizedBox(height: 20),
                  IgnorePointer(
                    ignoring: away,
                    child: const _TransportControls(),
                  ),
                  const SizedBox(height: 16),
                  IgnorePointer(
                    ignoring: away,
                    child: const NowPlayingVolumeControl(),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            );
            return scroll ? SingleChildScrollView(child: content) : content;
          },
        ),
      ),
    );
  }

  Widget _buildTrackMetadataSection({
    required Track? currentTrack,
    required SourceDisplayInfo? sourceInfo,
    required String mimeLabel,
    required String qualityLabel,
  }) {
    return Column(
      children: [
        Text(
          currentTrack?.title ?? 'No track',
          style: KalinkaTextStyles.expandedTitle,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 6),
        Text(
          currentTrack?.performer?.name ?? '\u2014',
          style: KalinkaTextStyles.expandedArtist,
          textAlign: TextAlign.center,
        ),
        if (currentTrack?.album != null) ...[
          const SizedBox(height: 4),
          Text(
            () {
              final album = currentTrack!.album!;
              final year = album.year;
              return year != null ? '${album.title} · $year' : album.title;
            }(),
            style: KalinkaTextStyles.expandedAlbum,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
        if (currentTrack != null) ...[
          const SizedBox(height: 4),
          _buildSourceAttributionRow(
            currentTrack: currentTrack,
            sourceInfo: sourceInfo,
            mimeLabel: mimeLabel,
            qualityLabel: qualityLabel,
          ),
          const _PlaybackErrorNote(),
          const _ExclusivePlaybackNote(),
        ],
      ],
    );
  }

  Widget _buildSourceAttributionRow({
    required Track currentTrack,
    required SourceDisplayInfo? sourceInfo,
    required String mimeLabel,
    required String qualityLabel,
  }) {
    final List<String> parts = [if (sourceInfo != null) sourceInfo.title];
    final List<String> fmtParts = [
      if (mimeLabel.isNotEmpty) mimeLabel,
      if (qualityLabel.isNotEmpty) qualityLabel,
    ];
    if (fmtParts.isNotEmpty) {
      parts.add(fmtParts.join(' '));
    }
    final attributionText = parts.join(' · ');
    final showBadge = sourceBadgeVisible(ref, currentTrack.id);

    // The line that names the stream is also the way into its details.
    return Semantics(
      label: 'Stream info',
      button: true,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          mouseCursor: clickCursor(interactive: true),
          onTap: () {
            showKalinkaDialog<void>(
              context: context,
              builder: (_) => const StreamInfoDialog(),
            );
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (showBadge) SourceBadge(entityId: currentTrack.id),
                if (attributionText.isNotEmpty) ...[
                  if (showBadge) const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      attributionText,
                      style: KalinkaTextStyles.expandedAttribution,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
                const BitPerfectBadge(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader({required bool showingQueue}) {
    if (widget.showOverlayHeader || widget.isTablet) {
      return PlayerHeader(
        isTablet: widget.isTablet && !widget.showOverlayHeader,
        showingQueue: showingQueue,
        onClose: widget.onClose,
        outputSwitcherKey: widget.outputSwitcherKey,
      );
    }

    // Embedded mode: label centred, switcher pinned right.
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Text('NOW PLAYING', style: KalinkaTextStyles.nowPlayingLabel),
          const Align(
            alignment: Alignment.centerRight,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [KioskEnterButton(), RendererSwitcherDropdown()],
            ),
          ),
        ],
      ),
    );
  }
}

/// Inline note under the track metadata when the current track failed to play.
///
/// The transport disc stays a plain play button that retries, so this line and
/// the queue's CAN'T PLAY label are what report the failure once the dialog is
/// gone. Its own widget so state changes don't rebuild the metadata above it.
class _PlaybackErrorNote extends ConsumerWidget {
  const _PlaybackErrorNote();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final failed = ref.watch(
      playerStateProvider.select((s) => s.state == PlayerStateType.error),
    );
    if (!failed) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.warning_rounded,
            size: 14,
            color: KalinkaColors.statusPendingLight,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              'Couldn’t play this track',
              style: KalinkaTextStyles.expandedAttribution.copyWith(
                color: KalinkaColors.statusPendingLight,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// Inline note under the track metadata while a plugin plays exclusively, so
/// it is plain the controls reach that playback and not Kalinka's queue.
class _ExclusivePlaybackNote extends ConsumerWidget {
  const _ExclusivePlaybackNote();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final control = ref.watch(playbackControlProvider);
    if (!control.isExclusive) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.speaker_outlined,
            size: 14,
            color: KalinkaColors.textSecondary,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              'Playing via ${control.title}',
              style: KalinkaTextStyles.expandedAttribution,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// Transport controls row (shuffle, prev, play/pause, next, repeat).
/// Extracted so only this widget rebuilds on playerState / playbackMode changes,
/// leaving the rest of NowPlayingContent (album art, metadata) untouched.
class _TransportControls extends ConsumerWidget {
  const _TransportControls();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final transport = ref.watch(transportStateProvider);
    final playerState = transport.playerState;
    final playbackMode = ref.watch(playbackModeProvider);
    final api = ref.read(kalinkaWsApiProvider);

    final isShuffle = playbackMode.shuffle;
    final isRepeatAll = playbackMode.repeatAll;
    final isRepeatOne = playbackMode.repeatSingle;

    // No track loaded → the transport buttons (prev / play-pause / next) go
    // inactive. Shuffle and repeat are switches that apply to whatever the
    // queue plays next, so they stay live, but only while the queue plays —
    // a plugin's playback takes neither.
    final exclusive = transport.exclusive;
    final hasTrack = transport.hasTrack;
    final playPauseDisabled = transport.playPauseDisabled;
    final canPrev = transport.canPrev;
    final canNext = transport.canNext;

    return RepaintBoundary(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          if (!exclusive)
            TransportButton(
              hitDiameter: 44,
              onTap: () {
                api.sendQueueCommand(
                  QueueCommand.setPlaybackMode(
                    shuffle: !isShuffle,
                    repeatAll: playbackMode.repeatAll,
                    repeatSingle: playbackMode.repeatSingle,
                  ),
                );
              },
              child: Icon(
                Icons.shuffle,
                size: 22,
                color: isShuffle
                    ? KalinkaColors.accent
                    : KalinkaColors.textSecondary,
              ),
            ),
          Opacity(
            opacity: canPrev ? 1.0 : 0.4,
            child: TransportButton(
              hitDiameter: 52,
              onTap: canPrev
                  ? () => api.sendQueueCommand(const QueueCommand.prev())
                  : null,
              child: const Icon(
                Icons.skip_previous_rounded,
                size: 36,
                color: KalinkaColors.textPrimary,
              ),
            ),
          ),
          Opacity(
            opacity: hasTrack ? 1.0 : 0.4,
            child: TransportButton(
              hitDiameter: 68,
              background: Colors.white,
              // Ripple has to read against the white face of the play/pause
              // disc, so use a dark tint instead of the default white-on-dark.
              splashColor: KalinkaColors.background.withValues(alpha: 0.18),
              highlightColor: KalinkaColors.background.withValues(alpha: 0.08),
              onTap: playPauseDisabled
                  ? null
                  : () => sendPlayPauseCommand(
                      ref,
                      playerState,
                      exclusive: exclusive,
                    ),
              child: PlayPauseGlyph(
                playerState: playerState,
                iconSize: 38,
                spinnerSize: 30,
                spinnerStrokeWidth: 3,
              ),
            ),
          ),
          Opacity(
            opacity: canNext ? 1.0 : 0.4,
            child: TransportButton(
              hitDiameter: 52,
              onTap: canNext
                  ? () => api.sendQueueCommand(const QueueCommand.next())
                  : null,
              child: const Icon(
                Icons.skip_next_rounded,
                size: 36,
                color: KalinkaColors.textPrimary,
              ),
            ),
          ),
          if (!exclusive)
            TransportButton(
              hitDiameter: 44,
              onTap: () {
                final bool newRepeatAll;
                final bool newRepeatSingle;
                if (isRepeatOne) {
                  newRepeatAll = false;
                  newRepeatSingle = false;
                } else if (isRepeatAll) {
                  newRepeatAll = false;
                  newRepeatSingle = true;
                } else {
                  newRepeatAll = true;
                  newRepeatSingle = false;
                }
                api.sendQueueCommand(
                  QueueCommand.setPlaybackMode(
                    shuffle: playbackMode.shuffle,
                    repeatAll: newRepeatAll,
                    repeatSingle: newRepeatSingle,
                  ),
                );
              },
              child: Icon(
                isRepeatOne ? Icons.repeat_one : Icons.repeat,
                size: 22,
                color: (isRepeatAll || isRepeatOne)
                    ? KalinkaColors.accent
                    : KalinkaColors.textSecondary,
              ),
            ),
        ],
      ),
    );
  }
}

/// Album art section with a LayoutBuilder for size calculation.
/// Extracted into its own widget so that LayoutBuilder._rebuildWithConstraints
/// only rebuilds this element, not the parent _NowPlayingContentState.
class _AlbumArtSection extends StatelessWidget {
  final String? trackId;
  final String? resolvedImageUrl;

  const _AlbumArtSection({
    required this.trackId,
    required this.resolvedImageUrl,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: LayoutBuilder(
        builder: (context, artConstraints) {
          final artSize = (artConstraints.maxWidth * 0.88).clamp(
            0.0,
            artConstraints.maxHeight,
          );
          return Center(
            child: Container(
              width: artSize,
              height: artSize,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.5),
                    blurRadius: 40,
                    offset: const Offset(0, 20),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: resolvedImageUrl != null
                  ? Image.network(
                      resolvedImageUrl!,
                      width: artSize,
                      height: artSize,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => ProceduralAlbumArt(
                        trackId: trackId ?? '',
                        size: artSize,
                      ),
                    )
                  : ProceduralAlbumArt(trackId: trackId ?? '', size: artSize),
            ),
          );
        },
      ),
    );
  }
}
