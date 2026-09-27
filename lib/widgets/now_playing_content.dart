import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data_model/data_model.dart';
import '../data_model/kalinka_ws_api.dart';
import '../providers/app_state_provider.dart';
import '../providers/kalinka_ws_api_provider.dart';
import '../providers/url_resolver.dart';
import '../theme/app_theme.dart';
import '../utils/haptics.dart';
import '../utils/playback_utils.dart';
import '../providers/source_modules_provider.dart';
import 'bit_perfect_badge.dart';
import 'play_pause_glyph.dart';
import 'playback_progress_slider.dart';
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
  /// layout, where this header carries the only switcher on screen.
  final Key? outputSwitcherKey;

  const NowPlayingContent({
    super.key,
    this.isTablet = false,
    this.showOverlayHeader = false,
    this.onClose,
    this.outputSwitcherKey,
  });

  @override
  ConsumerState<NowPlayingContent> createState() => _NowPlayingContentState();
}

class _NowPlayingContentState extends ConsumerState<NowPlayingContent> {
  String _formatLabel(String? mimeType) {
    if (mimeType == null) return '';
    if (mimeType.contains('flac')) return 'FLAC';
    if (mimeType.contains('wav')) return 'WAV';
    if (mimeType.contains('mp3') || mimeType.contains('mpeg')) return 'MP3';
    if (mimeType.contains('aac')) return 'AAC';
    if (mimeType.contains('ogg')) return 'OGG';
    if (mimeType.contains('opus')) return 'OPUS';
    return mimeType.split('/').last.toUpperCase();
  }

  String _formatAudioQuality(AudioInfo? audioInfo) {
    if (audioInfo == null) return '';

    final bitsPerSample = audioInfo.bitsPerSample;
    final sampleRate = audioInfo.sampleRate;
    final parts = <String>[];
    if (bitsPerSample > 0) {
      parts.add('$bitsPerSample-bit');
    }
    if (sampleRate > 0) {
      final khz = sampleRate / 1000;
      final khzLabel = sampleRate % 1000 == 0
          ? khz.toStringAsFixed(0)
          : khz.toStringAsFixed(1);
      parts.add('$khzLabel kHz');
    }

    return parts.join(' • ');
  }

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
    final queueView = ref.watch(
      playQueueStateStoreProvider.select(
        (s) => (
          length: s.trackList.length,
          index: s.playbackState.index ?? 0,
          seq: s.seq,
        ),
      ),
    );
    final exclusive = ref.watch(playbackControlProvider).isExclusive;
    // Read full state without watching — content is current because the
    // selectors above already gated the rebuild on a meaningful change.
    final playbackState = ref.read(playerStateProvider);
    final trackList = ref.read(playQueueStateStoreProvider).trackList;
    // Derive the current track from the queue (like MiniPlayer) so an emptied
    // queue resolves to "no track" instead of the stale currentTrack. A
    // plugin's playback is not in the queue, so its track is the state's own.
    final Track? currentTrack;
    if (exclusive) {
      currentTrack = playbackState.currentTrack;
    } else if (queueView.index >= 0 && queueView.index < trackList.length) {
      currentTrack = trackList[queueView.index];
    } else if (trackList.isNotEmpty) {
      currentTrack = playbackState.currentTrack;
    } else {
      currentTrack = null;
    }
    final urlResolver = ref.read(urlResolverProvider);

    final streamDurationMs = playbackState.audioInfo?.durationMs ?? 0;
    final durationMs = exclusive && streamDurationMs > 0
        ? streamDurationMs
        : (currentTrack?.duration ?? 0) * 1000;

    final imageUrl = currentTrack?.album?.image?.large;
    final resolvedImageUrl = imageUrl != null
        ? urlResolver.abs(imageUrl)
        : null;

    final mimeLabel = _formatLabel(playbackState.mimeType);
    final qualityLabel = _formatAudioQuality(playbackState.audioInfo);

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

    return Container(
      color: KalinkaColors.background,
      child: SafeArea(
        child: Column(
          children: [
            // Header
            _buildHeader(),
            // Content — fills remaining space with controls pinned to bottom
            _buildBodyContent(
              currentTrack: currentTrack,
              resolvedImageUrl: resolvedImageUrl,
              sourceInfo: sourceInfo,
              mimeLabel: mimeLabel,
              qualityLabel: qualityLabel,
              durationMs: durationMs,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBodyContent({
    required Track? currentTrack,
    required String? resolvedImageUrl,
    required SourceDisplayInfo? sourceInfo,
    required String mimeLabel,
    required String qualityLabel,
    required int durationMs,
  }) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          children: [
            const SizedBox(height: 8),
            _AlbumArtSection(
              trackId: currentTrack?.id,
              resolvedImageUrl: resolvedImageUrl,
            ),
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
            const _TransportControls(),
            const SizedBox(height: 16),
            const NowPlayingVolumeControl(),
            const SizedBox(height: 24),
          ],
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

    return Row(
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
    );
  }

  Widget _buildHeader() {
    if (widget.showOverlayHeader) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          children: [
            // Drag handle pill
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 12),
            // Minimise on the left, output switch on the right, NOW PLAYING
            // centred. A Stack, not a spaceBetween Row: the switcher hides
            // itself until a renderer list is read (and always on servers
            // without /renderer/*), and the label must stay centred either
            // way. The switcher stays icon-only here — a phone header hasn't
            // the width the tablet's name enjoys.
            Stack(
              alignment: Alignment.center,
              children: [
                Text('NOW PLAYING', style: KalinkaTextStyles.nowPlayingLabel),
                Align(
                  alignment: Alignment.centerLeft,
                  child: GestureDetector(
                    onTap: widget.onClose,
                    child: const Icon(
                      Icons.keyboard_arrow_down,
                      size: 28,
                      color: KalinkaColors.textSecondary,
                    ),
                  ),
                ),
                const Align(
                  alignment: Alignment.centerRight,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      StreamInfoButton(),
                      RendererSwitcherButton(hitDiameter: 36, iconSize: 20),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    if (widget.isTablet) {
      // Connection status lives in the right-panel top bar, not here.
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Row(
          children: [
            Expanded(
              child: Text(
                'NOW PLAYING',
                style: KalinkaTextStyles.nowPlayingLabel,
              ),
            ),
            const StreamInfoButton(),
            RendererSwitcherDropdown(key: widget.outputSwitcherKey),
          ],
        ),
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
              children: [StreamInfoButton(), RendererSwitcherDropdown()],
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
    final playerState = ref.watch(playerStateProvider.select((s) => s.state));
    final playbackMode = ref.watch(playbackModeProvider);
    final api = ref.read(kalinkaWsApiProvider);

    final isShuffle = playbackMode.shuffle;
    final isRepeatAll = playbackMode.repeatAll;
    final isRepeatOne = playbackMode.repeatSingle;

    // No track loaded → the transport buttons (prev / play-pause / next) go
    // inactive. Shuffle and repeat are switches that apply to whatever the
    // queue plays next, so they stay live, but only while the queue plays.
    final queuePosition = ref.watch(
      playQueueStateStoreProvider.select(
        (s) => (length: s.trackList.length, index: s.playbackState.index ?? 0),
      ),
    );
    // A plugin's playback carries its own queue: its controls go to it, and
    // only it knows where its ends are. It takes no shuffle or repeat.
    final exclusive = ref.watch(playbackControlProvider).isExclusive;
    final hasTrack = exclusive || queuePosition.length > 0;
    final playPauseDisabled =
        !hasTrack || isPlayPauseDisabled(playerState, exclusive: exclusive);

    // Gate prev/next at the queue ends, but only for plain sequential
    // playback: repeat-all wraps around and shuffle decouples list order from
    // play order, so in those modes either end stays meaningful.
    final boundedNav = !exclusive && !isShuffle && !isRepeatAll;
    final canPrev = hasTrack && (!boundedNav || queuePosition.index > 0);
    final canNext =
        hasTrack &&
        (!boundedNav || queuePosition.index < queuePosition.length - 1);

    return RepaintBoundary(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          if (!exclusive)
            TransportButton(
              hitDiameter: 44,
              onTapDown: (_) => isShuffle
                  ? KalinkaHaptics.lightImpact()
                  : KalinkaHaptics.mediumImpact(),
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
              onTapDown: canPrev ? (_) => KalinkaHaptics.mediumImpact() : null,
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
              onTapDown: playPauseDisabled
                  ? null
                  : (_) => playerState == PlayerStateType.playing
                        ? KalinkaHaptics.lightImpact()
                        : KalinkaHaptics.mediumImpact(),
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
              onTapDown: canNext ? (_) => KalinkaHaptics.mediumImpact() : null,
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
              onTapDown: (_) => KalinkaHaptics.selectionClick(),
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
                      errorBuilder: (_, __, ___) => ProceduralAlbumArt(
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
