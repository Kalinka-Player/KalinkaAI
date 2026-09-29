import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data_model/data_model.dart';
import '../data_model/kalinka_ws_api.dart';
import '../providers/app_state_provider.dart';
import '../providers/connection_settings_provider.dart';
import '../providers/connection_state_provider.dart';
import '../providers/kalinka_ws_api_provider.dart';
import '../providers/kiosk_provider.dart';
import '../providers/now_playing_provider.dart';
import '../providers/source_modules_provider.dart';
import '../providers/url_resolver.dart';
import '../theme/app_theme.dart';
import '../utils/playback_utils.dart';
import '../widgets/kiosk/kiosk_backdrop.dart';
import '../widgets/kiosk/kiosk_clock.dart';
import '../widgets/kiosk/kiosk_cover_flow.dart';
import '../widgets/kiosk/kiosk_progress_bar.dart';
import '../widgets/kiosk/kiosk_splash.dart';
import '../widgets/kiosk/kiosk_status_strip.dart';
import '../widgets/kiosk/kiosk_track_text.dart';
import '../widgets/kiosk/kiosk_volume_control.dart';
import '../widgets/measure_size.dart';
import '../widgets/play_pause_glyph.dart';
import '../widgets/transport_button.dart';

/// Full-screen now-playing display, for a screen that shows what plays
/// rather than one used to choose it. Stands in for the whole app: queue,
/// search and settings are never built.
///
/// Laid out for a 1024×600 panel and scaled from there. While music plays
/// the controls rest out of sight after a few seconds; with nothing playing
/// the screen dims after a while. Either way the touch that brings it back
/// acts on nothing else.
class KioskScreen extends ConsumerStatefulWidget {
  const KioskScreen({super.key});

  @override
  ConsumerState<KioskScreen> createState() => _KioskScreenState();
}

typedef _TrackView = ({
  String id,
  String title,
  String? artist,
  String? album,
  int? year,
  String? largeImage,
  String? smallImage,
});

class _KioskScreenState extends ConsumerState<KioskScreen> {
  static const _restAfter = Duration(seconds: 10);
  static const _dimAfter = Duration(minutes: 2);
  static const _volumeFor = Duration(seconds: 4);

  // Nudges everything a few pixels once a minute so no edge sits on the
  // same pixels for hours.
  static const _shiftEvery = Duration(minutes: 1);
  static const _shifts = [
    Offset.zero,
    Offset(3, -2),
    Offset(-2, 3),
    Offset(2, 2),
    Offset(-3, -1),
    Offset(1, -3),
  ];

  bool _awake = true;
  bool _dimmed = false;
  bool _volumeVisible = false;
  Timer? _restTimer;
  Timer? _volumeTimer;
  Timer? _dimTimer;
  Timer? _shiftTimer;
  int _shift = 0;

  String? _shownTrackId;
  int _shownIndex = 0;
  int _direction = 1;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    ref.listenManual(playerStateProvider.select((s) => s.state), (_, next) {
      switch (next) {
        case PlayerStateType.playing:
          // Music on a dimmed display brings the picture back, not the
          // controls: they rest again once it has run for a while.
          if (_dimmed) setState(() => _dimmed = false);
          _armRest();
        case PlayerStateType.buffering:
          break;
        default:
          _wake();
      }
    });
    _wake();
    _shiftTimer = Timer.periodic(_shiftEvery, (_) {
      if (mounted) setState(() => _shift = (_shift + 1) % _shifts.length);
    });
  }

  @override
  void dispose() {
    _restTimer?.cancel();
    _dimTimer?.cancel();
    _volumeTimer?.cancel();
    _shiftTimer?.cancel();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  bool get _playing {
    final state = ref.read(playerStateProvider).state;
    return state == PlayerStateType.playing ||
        state == PlayerStateType.buffering;
  }

  void _armRest() {
    _restTimer?.cancel();
    _restTimer = Timer(_restAfter, () {
      if (!mounted) return;
      // Only rest over music: paused or stopped, play is what a passer-by
      // reaches for.
      if (ref.read(playerStateProvider).state == PlayerStateType.playing) {
        setState(() {
          _awake = false;
        });
      }
    });
  }

  void _armDim() {
    _dimTimer?.cancel();
    _dimTimer = Timer(_dimAfter, () {
      if (!mounted || _playing) return;
      setState(() {
        _dimmed = true;
        _awake = false;
      });
    });
  }

  void _wake() {
    if (!_awake || _dimmed) {
      setState(() {
        _awake = true;
        _dimmed = false;
      });
    }
    _armRest();
    _armDim();
  }

  void _showVolume() {
    if (!_volumeVisible) setState(() => _volumeVisible = true);
    _volumeTimer?.cancel();
    _volumeTimer = Timer(_volumeFor, () {
      if (mounted) setState(() => _volumeVisible = false);
    });
  }

  // The way the viewer last skipped, kept for the track change it causes.
  static const _skipHeldFor = Duration(seconds: 10);
  int? _skipDirection;
  DateTime? _skippedAt;

  /// Skips a track (+1 next, -1 previous) from the display's own buttons,
  /// remembering which way for the cover to turn.
  void _skip(int direction) {
    _skipDirection = direction;
    _skippedAt = DateTime.now();
    ref
        .read(kalinkaWsApiProvider)
        .sendQueueCommand(
          direction > 0 ? const QueueCommand.next() : const QueueCommand.prev(),
        );
  }

  /// Which way the cover flow turns: the way the viewer skipped, when they
  /// did — a plugin's playback, shuffle and a wrap to the queue's start all
  /// hide it from the queue position — otherwise forward unless the queue
  /// went back.
  void _trackDirection(String? trackId, int index) {
    if (trackId == _shownTrackId) return;
    final skipped = _skippedAt;
    if (_skipDirection != null &&
        skipped != null &&
        DateTime.now().difference(skipped) <= _skipHeldFor) {
      _direction = _skipDirection!;
    } else {
      _direction = index >= _shownIndex ? 1 : -1;
    }
    _skipDirection = null;
    _shownTrackId = trackId;
    _shownIndex = index;
  }

  void _exit() => ref.read(kioskProvider.notifier).exit();

  static const _logoTapsToLeave = 5;
  static const _logoTapWindow = Duration(milliseconds: 1500);
  int _logoTaps = 0;
  DateTime? _lastLogoTap;

  /// Five quick taps on the logo leave a display this device's setting holds.
  void _onLogoTap() {
    final now = DateTime.now();
    final last = _lastLogoTap;
    _logoTaps = last != null && now.difference(last) <= _logoTapWindow
        ? _logoTaps + 1
        : 1;
    _lastLogoTap = now;
    if (_logoTaps >= _logoTapsToLeave) {
      _logoTaps = 0;
      ref.read(kioskProvider.notifier).unlockDevice();
    }
  }

  @override
  Widget build(BuildContext context) {
    final track = ref.watch(
      nowPlayingTrackProvider.select<_TrackView?>(
        (t) => t == null
            ? null
            : (
                id: t.id,
                title: t.title,
                artist: t.performer?.name,
                album: t.album?.title,
                year: t.album?.year,
                largeImage: t.album?.image?.large,
                smallImage: t.album?.image?.small,
              ),
      ),
    );
    _trackDirection(
      track?.id,
      ref.watch(
        playQueueStateStoreProvider.select((s) => s.playbackState.index ?? 0),
      ),
    );
    final stopped = ref.watch(
      playerStateProvider.select((s) => s.state == PlayerStateType.stopped),
    );
    // Stopped is standby too: the queue ran out, or someone pressed stop.
    final standby = track == null || stopped;
    final urls = ref.read(urlResolverProvider);
    final backdropPath = standby
        ? null
        : (track.smallImage ?? track.largeImage);
    // Opened from the player, the way out is in plain sight. Held by this
    // device's setting, it is five taps on the logo; started by the launch
    // flag, there is none.
    final lock = ref.watch(kioskProvider.select((s) => s.lock));
    final canExit = lock == KioskLock.none;
    final showExit = canExit && _awake;
    final splash = ref.watch(kioskSplashPendingProvider);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _exit();
      },
      child: Focus(
        autofocus: true,
        onKeyEvent: (_, event) {
          if (canExit &&
              event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.escape) {
            _exit();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (_) {
            _wake();
            _showVolume();
          },
          child: Material(
            color: KalinkaColors.background,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final portrait =
                    constraints.maxWidth < constraints.maxHeight * 1.1;
                final scale =
                    (portrait
                            ? math.min(
                                constraints.maxWidth / 600,
                                constraints.maxHeight / 1024,
                              )
                            : math.min(
                                constraints.maxWidth / 1024,
                                constraints.maxHeight / 600,
                              ))
                        .clamp(0.7, 2.0);
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    KioskBackdrop(
                      imageUrl: backdropPath == null
                          ? null
                          : urls.abs(backdropPath),
                    ),
                    SafeArea(
                      child: _content(
                        track: standby ? null : track,
                        largeImage: track?.largeImage == null
                            ? null
                            : urls.abs(track!.largeImage!),
                        scale: scale,
                        portrait: portrait,
                        showExit: showExit,
                        onLogoTap: lock == KioskLock.device ? _onLogoTap : null,
                        // Locked, the display shows the output; choosing
                        // one is for the full app.
                        canPickOutput: lock == KioskLock.none,
                      ),
                    ),
                    Positioned(
                      right: 18 * scale,
                      top: 0,
                      bottom: 0,
                      child: Center(
                        child: SizedBox(
                          height: math.min(
                            constraints.maxHeight * 0.7,
                            400 * scale,
                          ),
                          child: KioskVolumeControl(
                            scale: scale,
                            visible: _volumeVisible,
                            onActivity: _showVolume,
                          ),
                        ),
                      ),
                    ),
                    // Dimmed, not blanked: the clock still reads.
                    IgnorePointer(
                      child: AnimatedOpacity(
                        opacity: _dimmed ? 1 : 0,
                        duration: const Duration(milliseconds: 1500),
                        child: const ColoredBox(color: Color(0xB3000000)),
                      ),
                    ),
                    if (splash)
                      KioskSplash(
                        onDone: () => ref
                            .read(kioskSplashPendingProvider.notifier)
                            .shown(),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _content({
    required _TrackView? track,
    required String? largeImage,
    required double scale,
    required bool portrait,
    required bool showExit,
    required VoidCallback? onLogoTap,
    required bool canPickOutput,
  }) {
    double s(double v) => v * scale;
    return TweenAnimationBuilder<Offset>(
      tween: Tween(end: _shifts[_shift] * scale),
      duration: const Duration(seconds: 3),
      curve: Curves.easeInOut,
      builder: (context, offset, child) =>
          Transform.translate(offset: offset, child: child),
      child: Padding(
        padding: EdgeInsets.fromLTRB(s(32), s(16), s(32), s(20)),
        child: Column(
          children: [
            KioskStatusStrip(
              scale: scale,
              interactive: _awake,
              canPickOutput: canPickOutput,
              onLogoTap: onLogoTap,
              compact: portrait,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Standby shows its own clock, large.
                  if (track != null)
                    KioskClock(
                      builder: (context, now) => Text(
                        KioskClock.time(context, now),
                        style: KalinkaFonts.mono(
                          fontSize: s(17),
                          color: KalinkaColors.textSecondary,
                        ),
                      ),
                    ),
                  if (showExit) ...[
                    SizedBox(width: s(12)),
                    _ExitButton(scale: scale, onTap: _exit),
                  ],
                ],
              ),
            ),
            SizedBox(height: s(8)),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 600),
                child: track == null
                    ? _StandbyView(
                        key: const ValueKey('standby'),
                        scale: scale,
                        awake: _awake,
                      )
                    : _PlayingView(
                        key: const ValueKey('playing'),
                        track: track,
                        largeImage: largeImage,
                        direction: _direction,
                        scale: scale,
                        portrait: portrait,
                        awake: _awake,
                        onSkip: _skip,
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlayingView extends ConsumerWidget {
  final _TrackView track;
  final String? largeImage;
  final int direction;
  final double scale;
  final bool portrait;
  final bool awake;

  /// Skips a track, +1 next or -1 previous.
  final ValueChanged<int> onSkip;

  const _PlayingView({
    super.key,
    required this.track,
    required this.largeImage,
    required this.direction,
    required this.scale,
    required this.portrait,
    required this.awake,
    required this.onSkip,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    double s(double v) => v * scale;
    final lines = KioskTrackLines(
      trackId: track.id,
      title: track.title,
      artist: track.artist ?? '—',
      album: track.album == null
          ? null
          : (track.year != null
                ? '${track.album} · ${track.year}'
                : track.album),
      stream: _streamLine(ref, track.id),
    );
    final durationMs = ref.watch(nowPlayingDurationMsProvider);
    final progress = KioskProgressBar(
      durationMs: durationMs,
      scale: scale,
      interactive: awake,
    );
    final controls = _Resting(
      awake: awake,
      child: _KioskTransport(scale: scale, onSkip: onSkip),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final barHeight = s(26 + 44);
        final gap = s(12);
        final body = constraints.maxHeight - barHeight - gap;
        final reflection = 1 + KioskCoverFlow.reflectionExtent(1);

        if (portrait) {
          return Column(
            children: [
              Expanded(
                child: _OverlayLayout(
                  scale: scale,
                  cover: (size) => KioskCoverFlow(
                    trackId: track.id,
                    imageUrl: largeImage,
                    size: size,
                    direction: direction,
                    reflected: false,
                  ),
                  overlay: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      KioskTrackText(lines: lines, scale: scale, centred: true),
                      SizedBox(height: s(20)),
                      controls,
                    ],
                  ),
                ),
              ),
              SizedBox(height: gap),
              progress,
            ],
          );
        }

        final art = math.max(
          0.0,
          math.min(body / reflection, constraints.maxWidth * 0.42),
        );
        return Column(
          children: [
            Expanded(
              child: Center(
                child: SizedBox(
                  height: art * reflection,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      KioskCoverFlow(
                        trackId: track.id,
                        imageUrl: largeImage,
                        size: art,
                        direction: direction,
                      ),
                      SizedBox(width: s(44)),
                      // Text at the top, controls at the foot, both
                      // centred across the column.
                      Expanded(
                        child: SizedBox(
                          height: art,
                          child: Column(
                            children: [
                              // Short of room, the whole text block scales
                              // down a little — never cut off, and never the
                              // buttons squashed.
                              Expanded(
                                child: Padding(
                                  padding: EdgeInsets.only(top: s(32)),
                                  child: LayoutBuilder(
                                    builder: (context, box) => FittedBox(
                                      fit: BoxFit.scaleDown,
                                      alignment: Alignment.topCenter,
                                      child: ConstrainedBox(
                                        constraints: BoxConstraints(
                                          maxWidth: box.maxWidth,
                                        ),
                                        child: KioskTrackText(
                                          lines: lines,
                                          scale: scale,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              SizedBox(height: s(16)),
                              // Fixed size, lower edge on the cover's.
                              controls,
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            SizedBox(height: gap),
            progress,
          ],
        );
      },
    );
  }

  /// `Qobuz · FLAC · 16-bit / 44.1 kHz`, or null before anything is known.
  String? _streamLine(WidgetRef ref, String trackId) {
    final stream = ref.watch(
      playerStateProvider.select(
        (s) => (
          mime: mimeTypeLabel(s.mimeType),
          quality: audioQualityLabel(s.audioInfo, separator: ' / '),
        ),
      ),
    );
    final sourceId = _sourceOf(trackId);
    final source = sourceId == null
        ? null
        : ref.watch(
            sourceDisplayInfoProvider.select((m) => m[sourceId]?.title),
          );
    final parts = [
      ?source,
      if (stream.mime.isNotEmpty) stream.mime,
      if (stream.quality.isNotEmpty) stream.quality,
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }
}

/// Narrow screens: the cover as large as the width allows, the text and
/// controls laid over its foot. The cover dissolves into the backdrop just
/// above where the text starts, so the text reads on any artwork and no
/// panel edge shows.
class _OverlayLayout extends StatefulWidget {
  final double scale;
  final Widget Function(double size) cover;
  final Widget overlay;

  const _OverlayLayout({
    required this.scale,
    required this.cover,
    required this.overlay,
  });

  @override
  State<_OverlayLayout> createState() => _OverlayLayoutState();
}

class _OverlayLayoutState extends State<_OverlayLayout> {
  double _overlayHeight = 0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, area) {
        final art = math.min(area.maxWidth, area.maxHeight);
        // Where the text starts, measured down the cover.
        final textTop = area.maxHeight - _overlayHeight;
        final fade = 96 * widget.scale;
        final solidUntil = ((textTop - fade) / art).clamp(0.0, 1.0);
        final clearBy = ((textTop + 24 * widget.scale) / art).clamp(
          solidUntil,
          1.0,
        );
        return Stack(
          alignment: Alignment.topCenter,
          children: [
            ShaderMask(
              blendMode: BlendMode.dstIn,
              shaderCallback: (rect) => LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: const [Colors.white, Colors.white, Color(0x2EFFFFFF)],
                stops: [0, solidUntil, clearBy],
              ).createShader(rect),
              child: widget.cover(art),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: MeasureSize(
                onChange: (size) {
                  if (mounted) setState(() => _overlayHeight = size.height);
                },
                child: widget.overlay,
              ),
            ),
          ],
        );
      },
    );
  }
}

String? _sourceOf(String trackId) {
  try {
    return EntityId.fromString(trackId).source;
  } catch (_) {
    return null;
  }
}

const _weekdays = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];
const _months = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

/// `Tuesday, 29 September` — no year, nothing shouted.
String kioskDate(DateTime d) =>
    '${_weekdays[d.weekday - 1]}, ${d.day} ${_months[d.month - 1]}';

/// Nothing playing: a clock, and what the display is waiting for.
class _StandbyView extends ConsumerWidget {
  final double scale;
  final bool awake;

  const _StandbyView({super.key, required this.scale, required this.awake});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    double s(double v) => v * scale;
    final connected =
        ref.watch(connectionStateProvider) == ConnectionStatus.connected;
    final serverName = ref.watch(
      connectionSettingsProvider.select((s) => s.name),
    );

    final String headline;
    final String hint;
    if (connected) {
      headline = 'Ready to play';
      hint = 'Choose music in the Kalinka app to play here.';
    } else {
      headline = 'Can’t reach $serverName';
      hint = 'Reconnecting — this screen picks up where it left off.';
    }

    return Center(
      child: KioskClock(
        builder: (context, now) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              KioskClock.time(context, now),
              style: KalinkaFonts.display(
                fontSize: s(104),
                color: KalinkaColors.frost,
                height: 1,
              ),
            ),
            SizedBox(height: s(14)),
            Text(
              kioskDate(now),
              style: KalinkaFonts.sans(
                fontSize: s(19),
                color: KalinkaColors.textPrimary.withValues(alpha: 0.78),
              ),
            ),
            SizedBox(height: s(44)),
            Text(
              headline,
              style: KalinkaFonts.sans(
                fontSize: s(19),
                fontWeight: FontWeight.w500,
                color: KalinkaColors.textPrimary,
              ),
            ),
            SizedBox(height: s(6)),
            Text(
              hint,
              textAlign: TextAlign.center,
              style: KalinkaFonts.sans(
                fontSize: s(15),
                color: KalinkaColors.textSecondary,
              ),
            ),
            if (connected)
              _Resting(
                awake: awake,
                child: _ResumeButton(scale: scale),
              ),
          ],
        ),
      ),
    );
  }
}

/// Stopped with the queue still there: start it over once it has run out,
/// otherwise carry on from where it stopped.
class _ResumeButton extends ConsumerWidget {
  final double scale;

  const _ResumeButton({required this.scale});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    double s(double v) => v * scale;
    final queue = ref.watch(
      playQueueStateStoreProvider.select(
        (s) => (
          length: s.trackList.length,
          index: s.playbackState.index ?? 0,
          exclusive: s.playbackControl.isExclusive,
        ),
      ),
    );
    if (queue.exclusive || queue.length == 0) return const SizedBox.shrink();
    final finished = queue.index >= queue.length - 1;
    final api = ref.read(kalinkaWsApiProvider);

    return Padding(
      padding: EdgeInsets.only(top: s(28)),
      child: Material(
        color: Colors.white.withValues(alpha: 0.08),
        shape: StadiumBorder(
          side: BorderSide(color: Colors.white.withValues(alpha: 0.28)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => api.sendQueueCommand(
            finished
                ? const QueueCommand.play(index: 0)
                : const QueueCommand.play(),
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: s(26), vertical: s(14)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  finished ? Icons.replay_rounded : Icons.play_arrow_rounded,
                  size: s(24),
                  color: KalinkaColors.textPrimary,
                ),
                SizedBox(width: s(10)),
                Text(
                  finished ? 'Play again' : 'Resume',
                  style: KalinkaFonts.sans(
                    fontSize: s(17),
                    fontWeight: FontWeight.w500,
                    color: KalinkaColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Previous, play/pause and next, in the full player's colours and sized for
/// a room: a fingertip at arm's length. Shuffle and repeat stay with the full
/// app: they set up listening rather than follow it.
class _KioskTransport extends ConsumerWidget {
  final double scale;
  final ValueChanged<int> onSkip;

  const _KioskTransport({required this.scale, required this.onSkip});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    double s(double v) => v * scale;
    final transport = ref.watch(transportStateProvider);

    Widget skip(bool enabled, IconData icon, int direction) => Opacity(
      opacity: enabled ? 1.0 : 0.35,
      child: TransportButton(
        hitDiameter: s(62),
        onTapDown: null,
        onTap: enabled ? () => onSkip(direction) : null,
        child: Icon(icon, size: s(50), color: KalinkaColors.textPrimary),
      ),
    );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        skip(transport.canPrev, Icons.skip_previous_rounded, -1),
        SizedBox(width: s(16)),
        Opacity(
          opacity: transport.hasTrack ? 1.0 : 0.35,
          child: TransportButton(
            hitDiameter: s(100),
            background: Colors.white,
            // Ripple has to read against the white face of the disc.
            splashColor: KalinkaColors.background.withValues(alpha: 0.18),
            highlightColor: KalinkaColors.background.withValues(alpha: 0.08),
            onTapDown: null,
            onTap: transport.playPauseDisabled
                ? null
                : () => sendPlayPauseCommand(
                    ref,
                    transport.playerState,
                    exclusive: transport.exclusive,
                  ),
            child: PlayPauseGlyph(
              playerState: transport.playerState,
              iconSize: s(54),
              spinnerSize: s(40),
              spinnerStrokeWidth: s(3.5),
            ),
          ),
        ),
        SizedBox(width: s(16)),
        skip(transport.canNext, Icons.skip_next_rounded, 1),
      ],
    );
  }
}

class _ExitButton extends StatelessWidget {
  final double scale;
  final VoidCallback onTap;

  const _ExitButton({required this.scale, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Leave the now-playing display',
      button: true,
      excludeSemantics: true,
      child: TransportButton(
        hitDiameter: 48 * scale,
        onTapDown: null,
        onTap: onTap,
        child: Icon(
          Icons.fullscreen_exit_rounded,
          size: 26 * scale,
          color: KalinkaColors.textSecondary,
        ),
      ),
    );
  }
}

/// Fades a control out while the display rests and keeps touches off it
/// until it is back.
class _Resting extends StatelessWidget {
  final bool awake;
  final Widget child;

  const _Resting({required this.awake, required this.child});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: !awake,
      child: AnimatedOpacity(
        opacity: awake ? 1 : 0,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeOut,
        child: child,
      ),
    );
  }
}
