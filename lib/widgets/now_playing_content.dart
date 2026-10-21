import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data_model/data_model.dart';
import '../providers/app_state_provider.dart';
import '../providers/connection_state_provider.dart';
import '../providers/now_playing_provider.dart';
import '../providers/shell_nav_provider.dart';
import '../providers/url_resolver.dart';
import '../theme/app_theme.dart';
import '../utils/click_cursor.dart';
import '../utils/playback_utils.dart';
import '../providers/source_modules_provider.dart';
import 'away.dart';
import 'bit_perfect_badge.dart';
import 'kalinka_dialog.dart';
import 'kiosk/kiosk_enter_button.dart';
import 'kalinka_toast_overlay.dart' show kalinkaMiniPlayerHeight;
import 'play_pause_glyph.dart';
import 'playback_progress_slider.dart';
import 'player_queue_view.dart';
import 'player_sheet.dart';
import 'player_header.dart';
import 'renderer_switcher.dart';
import 'transport_button.dart';
import 'transport_controls.dart';
import 'procedural_album_art.dart';
import 'source_badge.dart';
import 'stream_info_dialog.dart';
import 'up_next_preview.dart';

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
  /// layout, where this is the only output selector while the track shows;
  /// the queue's [QueueMiniPlayer] takes the key while the queue does.
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
              SheetDragArea(
                child: _buildHeader(showingQueue: true, away: away),
              ),
              Expanded(
                child: PlayerQueueView(
                  onFindMusic: widget.onFindMusic,
                  isTablet: widget.isTablet,
                  bottomPadding:
                      kalinkaMiniPlayerHeight(context) +
                      MediaQuery.paddingOf(context).bottom,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // The fitted player can drag the phone sheet from anywhere in its body.
    return SheetDragArea(
      child: Container(
        color: KalinkaColors.background,
        child: SafeArea(
          child: Column(
            children: [
              // Header
              _buildHeader(showingQueue: false, away: away),
              // Content starts below the header; spare space can show Up Next.
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
            final textScaler = MediaQuery.textScalerOf(context);
            const metadataGap = 24.0;
            final metadataMinWidth = textScaler.scale(200);
            // Near-square and wider player panes can keep the cover beside
            // the details. Reserve readable text space before choosing this
            // arrangement, including when the system text size is enlarged.
            final sideBySide =
                constraints.maxWidth >= constraints.maxHeight * 0.8 &&
                constraints.maxWidth >= 144 + metadataGap + metadataMinWidth;
            // Start with a comfortable cover size, then give space back to
            // the controls and metadata when the viewport is short.
            final compact =
                constraints.maxHeight < 440 ||
                textScaler.scale(KalinkaTypography.baseSize) >
                    KalinkaTypography.baseSize * 1.3;
            final artSize = sideBySide
                ? (constraints.maxWidth * 0.42).clamp(
                    0.0,
                    (constraints.maxWidth - metadataGap - metadataMinWidth)
                        .clamp(0.0, 320.0),
                  )
                : compact
                ? (constraints.maxWidth * 0.72).clamp(0.0, 240.0)
                : (constraints.maxWidth * 0.88).clamp(
                    0.0,
                    constraints.maxHeight * 0.52,
                  );
            Widget metadataOf({double grow = 1}) => _buildTrackMetadataSection(
              currentTrack: currentTrack,
              sourceInfo: sourceInfo,
              mimeLabel: mimeLabel,
              qualityLabel: qualityLabel,
              leftAligned: sideBySide,
              grow: grow,
            );
            final short = constraints.maxHeight < 400;
            Widget output() => AwayLock(
              away: away,
              child: RendererSwitcherDropdown(
                key: widget.outputSwitcherKey,
                framed: true,
                maxNameWidth: 220,
              ),
            );
            final content = AwayDim(
              away: away,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Beside the details, the cover is held by the height, so
                  // what is spared above it goes to the cover.
                  SizedBox(height: sideBySide ? 8 : 32),
                  Flexible(
                    child: LayoutBuilder(
                      builder: (context, available) {
                        // Controls are laid out first by the Column. Only
                        // the cover/details group adapts to what remains.
                        final coverHeight = sideBySide
                            ? available.maxHeight
                            : available.maxHeight -
                                  _metadataHeight(
                                    currentTrack,
                                    available.maxWidth,
                                  ) -
                                  20;
                        final fittedArtSize = coverHeight.clamp(0.0, artSize);
                        final metadataWidth =
                            available.maxWidth - fittedArtSize - metadataGap;
                        // Beside the cover the details grow into the room
                        // there, as far as the cover's height holds them.
                        final metadata = sideBySide
                            ? metadataOf(
                                grow: _metadataGrowth(
                                  currentTrack,
                                  width: metadataWidth,
                                  height: math.max(
                                    fittedArtSize - 16 - _outputHeight(),
                                    _metadataHeight(
                                      currentTrack,
                                      metadataWidth,
                                    ),
                                  ),
                                ),
                              )
                            : metadataOf();
                        final artwork = _AlbumArtSection(
                          size: fittedArtSize,
                          trackId: currentTrack?.id,
                          resolvedImageUrl: resolvedImageUrl,
                        );
                        // The cover yields first. Exceptionally short windows
                        // can scale the presentation without shrinking the
                        // progress slider or transport controls.
                        return FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.topCenter,
                          child: SizedBox(
                            key: const ValueKey('now-playing-presentation'),
                            width: available.maxWidth,
                            child: sideBySide
                                ? IntrinsicHeight(
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        Align(
                                          alignment: Alignment.centerLeft,
                                          child: artwork,
                                        ),
                                        const SizedBox(width: metadataGap),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Expanded(
                                                child: Align(
                                                  key: const ValueKey(
                                                    'now-playing-metadata-area',
                                                  ),
                                                  alignment:
                                                      Alignment.centerLeft,
                                                  child: metadata,
                                                ),
                                              ),
                                              const SizedBox(height: 16),
                                              output(),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  )
                                : Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      artwork,
                                      if (fittedArtSize > 0)
                                        const SizedBox(height: 20),
                                      metadata,
                                    ],
                                  ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 32),
                  PlaybackProgressSlider(
                    durationMs: durationMs,
                    enabled: currentTrack != null,
                  ),
                  SizedBox(height: short ? 8 : 20),
                  AwayLock(away: away, child: const _TransportControls()),
                  if (!sideBySide) ...[
                    SizedBox(height: short ? 12 : 24),
                    Center(child: output()),
                  ],
                  SizedBox(height: short ? 12 : 24),
                ],
              ),
            );
            // Slivers measure any space left for Up Next, but the player
            // itself never scrolls. Vertical drags belong to the phone sheet.
            return CustomScrollView(
              primary: false,
              physics: const NeverScrollableScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: constraints.maxHeight,
                    ),
                    child: content,
                  ),
                ),
                // Optional: omit the preview when even one row cannot fit.
                SliverUpNextPreview(
                  canOpenQueue: widget.showOverlayHeader || widget.isTablet,
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// Space reserved for stacked metadata before sizing the cover. Measuring
  /// these few labels keeps long names and system text from pushing controls
  /// below the viewport; it runs only when the presentation is laid out.
  double _metadataHeight(Track? track, double width, {double grow = 1}) {
    double line(
      String text,
      TextStyle style,
      int maxLines, {
      bool grows = true,
    }) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: grows ? _grown(style, grow) : style),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
        maxLines: maxLines,
      )..layout(maxWidth: width);
      final height = painter.height;
      painter.dispose();
      return height;
    }

    var height =
        line(track?.title ?? 'No track', KalinkaTextStyles.expandedTitle, 2) +
        6 * grow +
        line(
          track?.performer?.name ?? '\u2014',
          KalinkaTextStyles.expandedArtist,
          2,
        );
    if (track?.album case final album?) {
      height +=
          4 * grow +
          line(_albumLine(album), KalinkaTextStyles.expandedAlbum, 1);
    }
    if (track != null) {
      // The stream's line keeps its size.
      height +=
          12 +
          line(
            'Stream info',
            KalinkaTextStyles.expandedAttribution,
            1,
            grows: false,
          );
    }
    return height;
  }

  /// How much larger than the stacked layout's the details beside the cover
  /// may be: in step with the [width] they have, up to 1.6×, and no taller
  /// than [height].
  double _metadataGrowth(
    Track? track, {
    required double width,
    required double height,
  }) {
    final room = width / MediaQuery.textScalerOf(context).scale(260);
    for (var grow = room.clamp(1.0, 1.6); grow > 1; grow -= 0.05) {
      if (_metadataHeight(track, width, grow: grow) <= height) return grow;
    }
    return 1;
  }

  /// The output switcher under the details beside the cover.
  double _outputHeight() {
    final painter = TextPainter(
      text: TextSpan(text: 'Output', style: KalinkaTextStyles.trayRowSublabel),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final height = painter.height;
    painter.dispose();
    // Its padding, and the glyphs beside the name.
    return 20 + math.max(18.0, height);
  }

  static TextStyle _grown(TextStyle style, double grow) =>
      grow == 1 ? style : style.copyWith(fontSize: style.fontSize! * grow);

  static String _albumLine(Album album) =>
      album.year != null ? '${album.title} · ${album.year}' : album.title;

  Widget _buildTrackMetadataSection({
    required Track? currentTrack,
    required SourceDisplayInfo? sourceInfo,
    required String mimeLabel,
    required String qualityLabel,
    bool leftAligned = false,
    double grow = 1,
  }) {
    final textAlign = leftAligned ? TextAlign.left : TextAlign.center;
    return Column(
      key: const ValueKey('now-playing-metadata'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: leftAligned
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.center,
      children: [
        Text(
          currentTrack?.title ?? 'No track',
          style: _grown(KalinkaTextStyles.expandedTitle, grow),
          textAlign: textAlign,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        SizedBox(height: 6 * grow),
        Text(
          currentTrack?.performer?.name ?? '\u2014',
          style: _grown(KalinkaTextStyles.expandedArtist, grow),
          textAlign: textAlign,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        if (currentTrack?.album case final album?) ...[
          SizedBox(height: 4 * grow),
          Text(
            _albumLine(album),
            style: _grown(KalinkaTextStyles.expandedAlbum, grow),
            textAlign: textAlign,
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
            leftAligned: leftAligned,
          ),
          const _PlaybackErrorNote(),
          _ExclusivePlaybackNote(textAlign: textAlign),
        ],
      ],
    );
  }

  Widget _buildSourceAttributionRow({
    required Track currentTrack,
    required SourceDisplayInfo? sourceInfo,
    required String mimeLabel,
    required String qualityLabel,
    required bool leftAligned,
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
            padding: EdgeInsets.fromLTRB(leftAligned ? 0 : 6, 4, 6, 4),
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

  Widget _buildHeader({required bool showingQueue, required bool away}) {
    if (widget.showOverlayHeader || widget.isTablet) {
      return PlayerHeader(
        isTablet: widget.isTablet && !widget.showOverlayHeader,
        showingQueue: showingQueue,
        onClose: widget.onClose,
      );
    }

    // Embedded mode: label centred, kiosk entry pinned right.
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Text('NOW PLAYING', style: KalinkaTextStyles.nowPlayingLabel),
          const Align(
            alignment: Alignment.centerRight,
            child: KioskEnterButton(),
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
  final TextAlign textAlign;

  const _ExclusivePlaybackNote({required this.textAlign});

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
              textAlign: textAlign,
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
    final exclusive = transport.exclusive;

    // No track loaded → the transport buttons (prev / play-pause / next) go
    // inactive. Shuffle and repeat are switches that apply to whatever the
    // queue plays next, so they stay live, but only while the queue plays —
    // a plugin's playback takes neither.
    return RepaintBoundary(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          if (!exclusive) const ShuffleButton(),
          const SkipButton(next: false),
          Opacity(
            opacity: transport.hasTrack ? 1.0 : 0.4,
            child: TransportButton(
              hitDiameter: 68,
              background: Colors.white,
              // Ripple has to read against the white face of the play/pause
              // disc, so use a dark tint instead of the default white-on-dark.
              splashColor: KalinkaColors.background.withValues(alpha: 0.18),
              highlightColor: KalinkaColors.background.withValues(alpha: 0.08),
              onTap: transport.playPauseDisabled
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
          const SkipButton(next: true),
          if (!exclusive) const RepeatButton(),
        ],
      ),
    );
  }
}

/// The cover keeps its natural square frame; spare height belongs below the
/// playback controls, where it can hold a queue preview.
class _AlbumArtSection extends StatelessWidget {
  final double size;
  final String? trackId;
  final String? resolvedImageUrl;

  const _AlbumArtSection({
    required this.size,
    required this.trackId,
    required this.resolvedImageUrl,
  });

  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('now-playing-artwork'),
    width: size,
    height: size,
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
            width: size,
            height: size,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) =>
                ProceduralAlbumArt(trackId: trackId ?? '', size: size),
          )
        : ProceduralAlbumArt(trackId: trackId ?? '', size: size),
  );
}
