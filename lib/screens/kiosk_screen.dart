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
import '../providers/renderer_provider.dart';
import '../providers/source_modules_provider.dart';
import '../providers/url_resolver.dart';
import '../providers/volume_activity_provider.dart';
import '../theme/app_theme.dart';
import '../utils/playback_utils.dart';
import '../widgets/kiosk/kiosk_backdrop.dart';
import '../widgets/kiosk/kiosk_clock.dart';
import '../widgets/kiosk/kiosk_cover_flow.dart';
import '../widgets/kiosk/kiosk_header.dart';
import '../widgets/kiosk/kiosk_output_panel.dart';
import '../widgets/kiosk/kiosk_progress_bar.dart';
import '../widgets/kiosk/kiosk_splash.dart';
import '../widgets/kiosk/kiosk_track_text.dart';
import '../widgets/kiosk/kiosk_transport.dart';
import '../widgets/kiosk/kiosk_volume_control.dart';
import '../widgets/measure_size.dart';
import '../widgets/transport_button.dart';

/// Full-screen now-playing display, for a screen that shows what plays
/// rather than one used to choose it. Stands in for the whole app: queue,
/// search and settings are never built.
///
/// Laid out for a 1024×600 panel and scaled from there; a portrait screen
/// stacks the same parts on its centre line, and a small or square one lets
/// the cover fill it. The controls stay up, except on a small screen: there,
/// while music plays, they rest out of sight after a few seconds. With
/// nothing playing the screen dims after a while. Either way the touch that
/// brings it back acts on nothing else.
class KioskScreen extends ConsumerStatefulWidget {
  const KioskScreen({super.key});

  @override
  ConsumerState<KioskScreen> createState() => _KioskScreenState();
}

/// How the display is laid out for its screen.
enum _Layout {
  /// Landscape: the cover beside the track.
  side,

  /// Portrait: the cover above the track, everything on the centre line.
  stack,

  /// Small or near-square: the cover fills the screen, the track and the
  /// controls over its foot.
  fill,
}

_Layout _layoutFor(Size size) {
  final aspect = size.width / size.height;
  if (size.longestSide < 560 || (aspect > 0.8 && aspect < 1.3)) {
    return _Layout.fill;
  }
  return aspect >= 1 ? _Layout.side : _Layout.stack;
}

/// Each layout is drawn for one screen — a 1024×600 panel, a large phone,
/// a 600-wide square — and scaled from there.
double _scaleFor(_Layout layout, Size size) => switch (layout) {
  _Layout.side =>
    math.min(size.width / 1024, size.height / 600).clamp(0.6, 2.5),
  _Layout.stack =>
    math.min(size.width / 430, size.height / 932).clamp(0.7, 2.0),
  _Layout.fill => (size.shortestSide / 600).clamp(0.4, 2.6),
};

/// Small enough that the controls rest out of sight over the cover, and an
/// output panel takes the whole screen.
bool _isSmall(Size size) => size.shortestSide < 480;

/// The header's size: a slim strip over a cover beside the track, and in
/// proportion over one that fills the screen — but never too small to read.
double _headerScale(_Layout layout, double scale) =>
    layout == _Layout.fill ? math.max(scale * 0.82, 0.54) : scale * 0.7;

/// Room round the edge of a cover that fills the screen.
EdgeInsets _fillPadding(double scale) => EdgeInsets.fromLTRB(
  math.max(34 * scale, 12),
  math.max(22 * scale, 10),
  math.max(34 * scale, 12),
  math.max(16 * scale, 10),
);

/// The output pill's size: a little larger than the header around it, so
/// it holds its own beside the clock; at a phone's foot, full size.
double _pillScale(_Layout layout, double scale) =>
    layout == _Layout.stack ? scale : _headerScale(layout, scale) * 1.2;

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
  static const _volumeFor = Duration(seconds: 3);

  // Left alone, the output panel gives the screen back to the music.
  static const _outputsFor = Duration(seconds: 15);

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

  bool _dimmed = false;

  /// The controls are out of sight — only where they lie over the cover.
  bool _resting = false;

  /// How tall the track and its controls stand over a cover that fills the
  /// screen, for the shade to start where they do.
  double? _infoHeight;

  void _onInfoHeight(double height) {
    if (mounted && height != _infoHeight) {
      setState(() => _infoHeight = height);
    }
  }

  Timer? _restTimer;
  bool _volumeVisible = false;
  bool _outputsOpen = false;
  Timer? _volumeTimer;
  Timer? _outputsTimer;
  Timer? _dimTimer;
  final _pillLink = LayerLink();
  Timer? _shiftTimer;
  int _shift = 0;

  String? _shownTrackId;
  int _shownIndex = 0;
  int _direction = 1;

  @override
  void initState() {
    super.initState();
    ref.listenManual(volumeActivityProvider, (_, _) => _showVolume());
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
    _outputsTimer?.cancel();
    _shiftTimer?.cancel();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  bool get _playing {
    final state = ref.read(playerStateProvider).state;
    return state == PlayerStateType.playing ||
        state == PlayerStateType.buffering;
  }

  void _armDim() {
    _dimTimer?.cancel();
    _dimTimer = Timer(_dimAfter, () {
      if (!mounted || _playing) return;
      _closeOutputs();
      setState(() => _dimmed = true);
    });
  }

  void _armRest() {
    _restTimer?.cancel();
    _restTimer = Timer(_restAfter, () {
      if (!mounted) return;
      // Only rest over music: paused or stopped, play is what a passer-by
      // reaches for.
      if (ref.read(playerStateProvider).state == PlayerStateType.playing) {
        setState(() => _resting = true);
      }
    });
  }

  void _wake() {
    if (_dimmed || _resting) {
      setState(() {
        _dimmed = false;
        _resting = false;
      });
    }
    _armRest();
    _armDim();
  }

  /// Brings up the volume by the output pill when it moves from elsewhere,
  /// or keeps it up a while longer while it is used. Not while the output
  /// panel is open: its own slider is already in view.
  void _showVolume() {
    if (_outputsOpen) return;
    if (!_volumeVisible) setState(() => _volumeVisible = true);
    _volumeTimer?.cancel();
    _volumeTimer = Timer(_volumeFor, () {
      if (mounted) setState(() => _volumeVisible = false);
    });
  }

  void _openOutputs() {
    // Servers with the renderer events keep the list fresh over the queue
    // socket; this re-read is the fallback for ones that predate them. Here,
    // on the tap, not as the panel builds: the read changes the list at once.
    if (ref.read(kioskProvider).lock == KioskLock.none) {
      ref.read(rendererListProvider.notifier).refresh();
    }
    _volumeTimer?.cancel();
    setState(() {
      _outputsOpen = true;
      _volumeVisible = false;
    });
    _touchOutputs();
  }

  /// Something was done in the output panel: it stays open a while longer.
  void _touchOutputs() {
    _outputsTimer?.cancel();
    _outputsTimer = Timer(_outputsFor, _closeOutputs);
  }

  void _closeOutputs() {
    _outputsTimer?.cancel();
    if (mounted && _outputsOpen) setState(() => _outputsOpen = false);
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
    final imagePath = standby ? null : (track.largeImage ?? track.smallImage);
    // Opened from the player, the way out is in plain sight. Held by this
    // device's setting, it is five taps on the logo; started by the launch
    // flag, there is none.
    final lock = ref.watch(kioskProvider.select((s) => s.lock));
    final canExit = lock == KioskLock.none;
    // Locked, the display shows the output; choosing one is for the full
    // app.
    final canPickOutput = lock == KioskLock.none;
    final volume = ref.watch(volumeAvailableProvider);
    // Somewhere else the music could go, for the panel to offer.
    final outputs =
        canPickOutput &&
        ref.watch(
          rendererListProvider.select(
            (s) => s.switcherVisible && s.renderers.any((r) => !r.active),
          ),
        );
    final splash = ref.watch(kioskSplashPendingProvider);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        // Back closes the output panel before it leaves the display.
        _outputsOpen ? _closeOutputs() : _exit();
      },
      child: Focus(
        autofocus: true,
        onKeyEvent: (_, event) {
          if (event is! KeyDownEvent ||
              event.logicalKey != LogicalKeyboardKey.escape) {
            return KeyEventResult.ignored;
          }
          if (_outputsOpen) {
            _closeOutputs();
            return KeyEventResult.handled;
          }
          if (canExit) {
            _exit();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (_) => _wake(),
          child: Material(
            color: KalinkaColors.background,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final layout = _layoutFor(constraints.biggest);
                final scale = _scaleFor(layout, constraints.biggest);
                final fill = layout == _Layout.fill && !standby;
                final small = _isSmall(constraints.biggest);
                final header = _headerScale(layout, scale);
                // On a small screen the controls come and go; elsewhere they
                // stay.
                final controlsUp = !(fill && small && _resting);
                // The output panel floats by the pill — under it in a
                // header, over it at a phone's foot — and takes the whole
                // screen only where there is no room to float it.
                final panelFullScreen =
                    (layout == _Layout.fill && small) ||
                    constraints.maxHeight < 420;
                final panelAbove = layout == _Layout.stack;
                final insets = MediaQuery.paddingOf(context);
                final panelScale = layout == _Layout.fill
                    ? scale.clamp(0.8, 1.2)
                    : scale;
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 900),
                      child: fill
                          ? KeyedSubtree(
                              key: const ValueKey('fill'),
                              child: _FillArt(
                                trackId: track.id,
                                imageUrl: imagePath == null
                                    ? null
                                    : urls.abs(imagePath),
                                infoTop: _infoHeight == null
                                    ? null
                                    : 1 -
                                          (_infoHeight! +
                                                  _fillPadding(scale).bottom +
                                                  insets.bottom) /
                                              constraints.maxHeight,
                              ),
                            )
                          : KioskBackdrop(
                              imageUrl: backdropPath == null
                                  ? null
                                  : urls.abs(backdropPath),
                            ),
                    ),
                    // Dimmed or resting, the touch that wakes the display
                    // acts on nothing else.
                    IgnorePointer(
                      ignoring: _dimmed || !controlsUp,
                      child: SafeArea(
                        child: _content(
                          track: standby ? null : track,
                          largeImage: track?.largeImage == null
                              ? null
                              : urls.abs(track!.largeImage!),
                          layout: layout,
                          scale: scale,
                          showExit: canExit,
                          controlsUp: controlsUp,
                          onLogoTap: lock == KioskLock.device
                              ? _onLogoTap
                              : null,
                          onOutputTap: volume || outputs ? _openOutputs : null,
                        ),
                      ),
                    ),
                    // The volume hangs from the output pill: under it in a
                    // header, over it at a phone's foot.
                    Positioned(
                      left: 0,
                      top: 0,
                      child: CompositedTransformFollower(
                        link: _pillLink,
                        showWhenUnlinked: false,
                        targetAnchor: layout == _Layout.stack
                            ? Alignment.topCenter
                            : Alignment.bottomCenter,
                        followerAnchor: layout == _Layout.stack
                            ? Alignment.bottomCenter
                            : Alignment.topCenter,
                        offset: Offset(
                          0,
                          (layout == _Layout.stack ? -12 : 12) * header,
                        ),
                        // Dimmed, the touch that wakes the display acts on
                        // nothing else — the volume included.
                        child: IgnorePointer(
                          ignoring: _dimmed,
                          child: KioskVolumePopup(
                            scale: _pillScale(layout, scale),
                            visible: _volumeVisible,
                            onActivity: _showVolume,
                          ),
                        ),
                      ),
                    ),
                    if (_outputsOpen)
                      if (panelFullScreen)
                        Positioned.fill(
                          child: Listener(
                            onPointerDown: (_) => _touchOutputs(),
                            child: KioskOutputPanel(
                              scale: panelScale,
                              fullScreen: true,
                              canPick: canPickOutput,
                              onClose: _closeOutputs,
                            ),
                          ),
                        )
                      else ...[
                        // Over the display, dimming it; a tap on it closes
                        // the panel.
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: _closeOutputs,
                          child: const ColoredBox(color: Color(0x80000000)),
                        ),
                        Positioned(
                          left: 0,
                          top: 0,
                          child: CompositedTransformFollower(
                            link: _pillLink,
                            showWhenUnlinked: false,
                            targetAnchor: panelAbove
                                ? Alignment.topCenter
                                : Alignment.bottomRight,
                            followerAnchor: panelAbove
                                ? Alignment.bottomCenter
                                : Alignment.topRight,
                            offset: Offset(0, (panelAbove ? -12 : 12) * header),
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                // Clear of the screen's sides, and of its
                                // top over a phone's pill.
                                maxWidth:
                                    constraints.maxWidth -
                                    2 * 16 * scale -
                                    insets.horizontal,
                                maxHeight:
                                    constraints.maxHeight -
                                    (panelAbove ? 120 : 100) * panelScale -
                                    insets.vertical,
                              ),
                              child: Listener(
                                onPointerDown: (_) => _touchOutputs(),
                                child: KioskOutputPanel(
                                  scale: panelScale,
                                  fullScreen: false,
                                  canPick: canPickOutput,
                                  onClose: _closeOutputs,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
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
    required _Layout layout,
    required double scale,
    required bool showExit,
    required bool controlsUp,
    required VoidCallback? onLogoTap,
    required VoidCallback? onOutputTap,
  }) {
    double s(double v) => v * scale;
    final fill = layout == _Layout.fill;
    final header = _headerScale(layout, scale);
    // Standby shows its own clock, large.
    final clock = track == null
        ? null
        : _TimeAndDate(
            scale: header,
            compact: fill && scale < 0.8,
            // Over a cover, as all text laid on one is.
            shadowed: fill,
          );
    final exit = showExit
        ? _ExitButton(
            scale: layout == _Layout.stack
                ? header * 1.2
                : _pillScale(layout, scale),
            onTap: _exit,
          )
        : null;
    // Over a cover that fills a large enough screen, the line under the
    // wordmark has room again.
    final logo = KioskLogo(
      scale: fill ? math.max(scale * 0.75, 0.52) : header,
      onTap: onLogoTap,
      tagline: fill && scale >= 1.4,
      shadowed: fill,
    );
    // Where it plays, and what the output panel hangs from.
    final output = CompositedTransformTarget(
      link: _pillLink,
      child: KioskOutputPill(
        scale: _pillScale(layout, scale),
        onTap: onOutputTap,
      ),
    );
    final view = AnimatedSwitcher(
      duration: const Duration(milliseconds: 600),
      child: track == null
          ? _StandbyView(key: const ValueKey('standby'), scale: scale)
          : _PlayingView(
              key: const ValueKey('playing'),
              track: track,
              largeImage: largeImage,
              direction: _direction,
              layout: layout,
              scale: scale,
              controlsUp: controlsUp,
              onSkip: _skip,
              onInfoHeight: _onInfoHeight,
            ),
    );

    final Widget body = switch (layout) {
      // The mark at the left, then where it plays and the time at the
      // right; the cover and the track under them.
      _Layout.side => Padding(
        padding: EdgeInsets.fromLTRB(s(34), s(22), s(34), s(26)),
        child: Column(
          children: [
            Row(
              children: [
                logo,
                SizedBox(width: header * 24),
                Expanded(
                  child: Align(alignment: Alignment.centerRight, child: output),
                ),
                if (clock != null) ...[SizedBox(width: header * 36), clock],
                if (exit != null) ...[SizedBox(width: header * 20), exit],
              ],
            ),
            SizedBox(height: s(16)),
            Expanded(child: view),
          ],
        ),
      ),
      // The mark and the time either side of the top, where it plays at the
      // foot, everything else on the centre line.
      _Layout.stack => Padding(
        padding: EdgeInsets.fromLTRB(s(24), s(18), s(24), s(20)),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Gives way to the clock on a narrow screen.
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: logo,
                  ),
                ),
                SizedBox(width: s(16)),
                ?clock,
                if (exit != null) ...[SizedBox(width: s(14)), exit],
              ],
            ),
            SizedBox(height: s(18)),
            Expanded(child: view),
            SizedBox(height: s(18)),
            output,
          ],
        ),
      ),
      // The mark at the left, where it plays and the time at the right,
      // along the top of the cover.
      _Layout.fill => Padding(
        padding: _fillPadding(scale),
        child: Column(
          children: [
            // Where it plays and the time take the width they need; pressed
            // for room, the mark shrinks before the output's name is cut
            // short, and only a name that would take most of the row is.
            LayoutBuilder(
              builder: (context, row) => Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: logo,
                    ),
                  ),
                  SizedBox(width: header * 16),
                  ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: row.maxWidth * 0.85),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ConstrainedBox(
                            constraints: BoxConstraints(
                              maxWidth: row.maxWidth * 0.55,
                            ),
                            child: output,
                          ),
                          SizedBox(width: header * 28),
                          ?clock,
                          if (exit != null) ...[
                            SizedBox(width: header * 16),
                            exit,
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(child: view),
          ],
        ),
      ),
    };

    return TweenAnimationBuilder<Offset>(
      tween: Tween(end: _shifts[_shift] * scale),
      duration: const Duration(seconds: 3),
      curve: Curves.easeInOut,
      builder: (context, offset, child) =>
          Transform.translate(offset: offset, child: child),
      child: body,
    );
  }
}

class _PlayingView extends ConsumerWidget {
  final _TrackView track;
  final String? largeImage;
  final int direction;
  final _Layout layout;
  final double scale;

  /// False while the controls rest out of sight over the cover.
  final bool controlsUp;

  /// Skips a track, +1 next or -1 previous.
  final ValueChanged<int> onSkip;

  /// Over a cover that fills the screen: how tall the track and its
  /// controls stand, each time that changes.
  final ValueChanged<double>? onInfoHeight;

  const _PlayingView({
    super.key,
    required this.track,
    required this.largeImage,
    required this.direction,
    required this.layout,
    required this.scale,
    required this.controlsUp,
    required this.onSkip,
    this.onInfoHeight,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    double s(double v) => v * scale;
    final sourceId = sourceOfId(track.id);
    final lines = KioskTrackLines(
      trackId: track.id,
      title: track.title,
      artist: track.artist ?? '—',
      album: track.album == null
          ? null
          : (track.year != null
                ? '${track.album} · ${track.year}'
                : track.album),
      format: _format(ref),
      source: sourceId,
      sourceTitle: sourceId == null
          ? null
          : ref.watch(
              sourceDisplayInfoProvider.select((m) => m[sourceId]?.title),
            ),
    );
    final durationMs = ref.watch(nowPlayingDurationMsProvider);
    final fill = layout == _Layout.fill;
    // Over a cover that fills the screen, sized as drawn for a 600-wide
    // square, but never too small to read or press.
    final barScale = fill ? math.max(scale * 0.8, 0.62) : scale;
    final progress = KioskProgressBar(durationMs: durationMs, scale: barScale);
    // Never wider than the space it is given.
    Widget controls({double? width}) => FittedBox(
      fit: BoxFit.scaleDown,
      child: KioskTransport(
        scale: fill ? math.max(scale * 0.9, 0.6) : scale,
        width: width,
        onSkip: onSkip,
      ),
    );
    Widget cover(double size) => KioskCoverFlow(
      trackId: track.id,
      imageUrl: largeImage,
      size: size,
      direction: direction,
    );

    switch (layout) {
      // The cover clear above; the track, the controls and the progress
      // gathered at its foot. The controls give their room back while they
      // rest.
      case _Layout.fill:
        // The ring's glow already spaces it from the lines around it.
        final gap = math.max(s(4), 2.0);
        return LayoutBuilder(
          builder: (context, box) => Align(
            alignment: Alignment.bottomCenter,
            child: MeasureSize(
              onChange: (size) => onInfoHeight?.call(size.height),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  KioskTrackText(lines: lines, scale: s(1.77), compact: true),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 500),
                    transitionBuilder: (child, animation) => SizeTransition(
                      sizeFactor: animation,
                      child: FadeTransition(opacity: animation, child: child),
                    ),
                    child: controlsUp
                        ? Padding(
                            key: const ValueKey('controls'),
                            padding: EdgeInsets.only(top: gap),
                            child: Center(
                              child: controls(width: box.maxWidth * 0.9),
                            ),
                          )
                        : const SizedBox(
                            key: ValueKey('resting'),
                            width: double.infinity,
                          ),
                  ),
                  progress,
                ],
              ),
            ),
          ),
        );

      case _Layout.stack:
        return Column(
          children: [
            Expanded(
              child: LayoutBuilder(
                builder: (context, box) => Center(
                  child: cover(
                    math.max(0.0, math.min(box.maxWidth, box.maxHeight)),
                  ),
                ),
              ),
            ),
            SizedBox(height: s(24)),
            KioskEyebrow(scale: scale),
            SizedBox(height: s(12)),
            KioskTrackText(lines: lines, scale: scale * 0.86, centred: true),
            SizedBox(height: s(22)),
            progress,
            SizedBox(height: s(6)),
            controls(),
          ],
        );

      case _Layout.side:
        return LayoutBuilder(
          builder: (context, constraints) {
            final gap = s(48);
            final art = math.max(
              0.0,
              math.min(constraints.maxHeight, constraints.maxWidth * 0.46),
            );
            final column = math.max(0.0, constraints.maxWidth - art - gap);
            return Center(
              child: SizedBox(
                height: art,
                child: Row(
                  children: [
                    cover(art),
                    SizedBox(width: gap),
                    SizedBox(
                      width: column,
                      child: Column(
                        children: [
                          // Short of room, the whole text block scales down
                          // a little — never cut off, and never the buttons
                          // squashed. Scaled, it still starts at the column's
                          // left edge, in line with the progress bar.
                          Expanded(
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: SizedBox(
                                  width: column,
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      KioskEyebrow(scale: scale),
                                      SizedBox(height: s(14)),
                                      KioskTrackText(
                                        lines: lines,
                                        scale: scale,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                          SizedBox(height: s(24)),
                          progress,
                          SizedBox(height: s(6)),
                          controls(),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
    }
  }

  /// `FLAC 24-bit 96 kHz`, or null before anything is known.
  String? _format(WidgetRef ref) {
    final stream = ref.watch(
      playerStateProvider.select(
        (s) => (
          mime: mimeTypeLabel(s.mimeType),
          quality: audioQualityLabel(s.audioInfo, separator: ' '),
        ),
      ),
    );
    final parts = [
      if (stream.mime.isNotEmpty) stream.mime,
      if (stream.quality.isNotEmpty) stream.quality,
    ];
    return parts.isEmpty ? null : parts.join(' ');
  }
}

/// The cover over the whole screen in three zones: shaded behind the header,
/// left alone through the middle, then darkening steadily from just above
/// the track down over the controls to the foot, with a broad soft oval
/// behind the title for a cover that is pale where it lands. Fixed, not
/// fitted to the cover: black over a dark cover changes little, and a pale
/// one gets the contrast it needs.
class _FillArt extends StatelessWidget {
  final String trackId;
  final String? imageUrl;

  /// Where the track starts, as a fraction of the height; null until it has
  /// been laid out.
  final double? infoTop;

  const _FillArt({
    required this.trackId,
    required this.imageUrl,
    required this.infoTop,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        KioskCoverFill(trackId: trackId, imageUrl: imageUrl),
        // Follows the track as it moves — the controls folding away, a
        // longer album name — rather than jumping.
        TweenAnimationBuilder<double>(
          tween: Tween(end: (infoTop ?? 0.42).clamp(0.24, 0.9)),
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOutCubic,
          builder: (context, top, _) {
            final start = top - 0.08;
            final headerEnd = math.min(0.26, start - 0.02);
            final title = Alignment(-0.4, (top + 0.035) * 2 - 1);
            return Stack(
              fit: StackFit.expand,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: const [
                        Color(0x73080808),
                        Color(0x4D080808),
                        Color(0x00080808),
                        Color(0x00080808),
                        Color(0x73080808),
                        Color(0xBF080808),
                        Color(0xE6080808),
                      ],
                      stops: [
                        0.0,
                        0.11,
                        headerEnd,
                        start,
                        top,
                        top + (1 - top) * 0.45,
                        1.0,
                      ],
                    ),
                  ),
                ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: title,
                      radius: 0.36,
                      colors: const [
                        Color(0x6B000000),
                        Color(0x38000000),
                        Color(0x00000000),
                      ],
                      stops: const [0.0, 0.35, 0.68],
                      transform: _Widen(1.8, title),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

/// Stretches a radial gradient sideways about its centre, into an oval.
class _Widen extends GradientTransform {
  final double factor;
  final Alignment centre;

  const _Widen(this.factor, this.centre);

  @override
  Matrix4 transform(Rect bounds, {TextDirection? textDirection}) {
    final c = centre.withinRect(bounds);
    return Matrix4.identity()
      ..translateByDouble(c.dx, c.dy, 0, 1)
      ..scaleByDouble(factor, 1, 1, 1)
      ..translateByDouble(-c.dx, -c.dy, 0, 1);
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

/// `Tue 29 Sep 2026`, under the header's clock.
String kioskShortDate(DateTime d) =>
    '${_weekdays[d.weekday - 1].substring(0, 3)} ${d.day} '
    '${_months[d.month - 1].substring(0, 3)} ${d.year}';

/// The time over the date, at the header's far end.
class _TimeAndDate extends StatelessWidget {
  final double scale;

  /// On a small screen: the date nearer the time's size, so it still reads.
  final bool compact;

  /// A hairline of shade under the figures, as polish over a cover.
  final bool shadowed;

  const _TimeAndDate({
    required this.scale,
    this.compact = false,
    this.shadowed = false,
  });

  @override
  Widget build(BuildContext context) {
    double s(double v) => v * scale;
    final shadows = shadowed ? kioskTextPolish : null;
    return KioskClock(
      builder: (context, now) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            KioskClock.time(context, now),
            style:
                KalinkaFonts.sans(
                  fontSize: s(30),
                  fontWeight: FontWeight.w500,
                  color: KalinkaColors.textPrimary,
                  height: 1.1,
                ).copyWith(
                  fontFeatures: const [FontFeature.tabularFigures()],
                  shadows: shadows,
                ),
          ),
          SizedBox(height: s(3)),
          Text(
            kioskShortDate(now),
            style: KalinkaFonts.sans(
              fontSize: s(compact ? 17 : 14),
              color: KalinkaColors.textPrimary.withValues(alpha: 0.76),
              height: 1.2,
            ).copyWith(shadows: shadows),
          ),
        ],
      ),
    );
  }
}

/// Nothing playing: a clock, and what the display is waiting for.
class _StandbyView extends ConsumerWidget {
  final double scale;

  const _StandbyView({super.key, required this.scale});

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
      // Usually the server is still starting, so this must not read as a fault.
      headline = 'Preparing…';
      hint = 'Waiting for $serverName. This screen picks up by itself.';
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
            if (connected) _ResumeButton(scale: scale),
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

/// The way back to the full app, for a display opened from it: a round
/// button the height of the output pill beside it, and never smaller than a
/// fingertip however far the layout scales down. Grows with the system's
/// text size, as the clock beside it does.
class _ExitButton extends StatelessWidget {
  final double scale;
  final VoidCallback onTap;

  const _ExitButton({required this.scale, required this.onTap});

  /// The smallest a touch target should be, in logical pixels.
  static const _minTarget = 44.0;

  @override
  Widget build(BuildContext context) {
    final textGrowth = MediaQuery.textScalerOf(context).scale(16) / 16;
    final diameter = math.max(48 * scale, _minTarget) * textGrowth;
    return Semantics(
      label: 'Leave the now-playing display',
      button: true,
      excludeSemantics: true,
      child: DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: KalinkaColors.textPrimary.withValues(alpha: 0.14),
          ),
        ),
        child: TransportButton(
          hitDiameter: diameter,
          background: Colors.black.withValues(alpha: 0.36),
          onTapDown: null,
          onTap: onTap,
          child: Icon(
            Icons.fullscreen_exit_rounded,
            size: diameter * 0.58,
            color: KalinkaColors.textPrimary,
          ),
        ),
      ),
    );
  }
}
