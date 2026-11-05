import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data_model/data_model.dart';
import '../../providers/app_state_provider.dart';
import '../../providers/connection_settings_provider.dart';
import '../../providers/display_power_provider.dart';
import '../../providers/display_settings_provider.dart';
import '../../providers/kiosk_provider.dart';
import '../../providers/onboarding_provider.dart';
import '../../screens/kiosk_screen.dart';
import '../../utils/display_power.dart';

typedef _DisplayState = ({bool enabled, bool kiosk, bool waiting});

final _playbackPreventsBlankingProvider = Provider<bool>((ref) {
  final playback = ref.watch(playerStateProvider.select((s) => s.state));
  return playback != PlayerStateType.paused &&
      playback != PlayerStateType.stopped;
});

final _displayStateProvider = Provider<_DisplayState>((ref) {
  final state = ref.watch(kioskProvider);
  final ready =
      ref.watch(onboardingStatusProvider.select((s) => s.oobeComplete)) &&
      ref.watch(connectionSettingsProvider.select((s) => s.isSet));
  final enabled = ready && state.lock == KioskLock.server;
  return (
    enabled: enabled,
    kiosk: enabled && state.active,
    waiting: enabled && !state.active,
  );
});

/// The server's display returns to the music, then blanks after local inactivity.
/// Lives above the app Navigator so dialogs, sheets and settings count as use
/// and are covered by the display without losing their state or pending edits.
class LocalKioskHost extends ConsumerStatefulWidget {
  final Widget child;

  const LocalKioskHost({super.key, required this.child});

  @override
  ConsumerState<LocalKioskHost> createState() => _LocalKioskHostState();
}

class _LocalKioskHostState extends ConsumerState<LocalKioskHost> {
  Timer? _idleTimer;
  Timer? _blankTimer;
  late final DisplayPower _power;
  final _pointers = <int>{};
  final _wakeKeys = <PhysicalKeyboardKey>{};
  bool _blanked = false;
  bool _consumeWakeGesture = false;

  @override
  void initState() {
    super.initState();
    _power = ref.read(displayPowerProvider);
    ref.listenManual(_displayStateProvider, (previous, next) {
      // Entering kiosk is not activity: its time comes out of the same
      // blanking countdown, rather than starting another five minutes.
      if (previous?.enabled != next.enabled ||
          (next.waiting && previous?.waiting != true)) {
        _wake();
        _recordActivity();
      } else {
        _scheduleKioskReturn();
      }
      if (previous?.kiosk == next.kiosk) return;
      if (next.kiosk) FocusManager.instance.primaryFocus?.unfocus();
    });
    ref.listenManual(displaySettingsProvider, (_, _) {
      _wake();
      _recordActivity();
    });
    ref.listenManual(_playbackPreventsBlankingProvider, (_, preventsBlanking) {
      if (preventsBlanking) _wake();
      // A pause gets a fresh blanking interval. Playback never changes the
      // separate deadline for returning from Home to the kiosk.
      _armBlankTimer();
    });
    FocusManager.instance.addEarlyKeyEventHandler(_onKeyEvent);
    _recordActivity();
  }

  void _scheduleKioskReturn() {
    _idleTimer?.cancel();
    if (!ref.read(_displayStateProvider).waiting || _pointers.isNotEmpty) {
      return;
    }
    _idleTimer = Timer(ref.read(displaySettingsProvider).kioskTimeout, () {
      ref.read(kioskProvider.notifier).enter();
    });
  }

  void _recordActivity() {
    _scheduleKioskReturn();
    _armBlankTimer();
  }

  void _armBlankTimer() {
    _blankTimer?.cancel();
    final timeout = ref.read(displaySettingsProvider).blankTimeout;
    if (!ref.read(_displayStateProvider).enabled ||
        _pointers.isNotEmpty ||
        _blanked ||
        timeout == Duration.zero ||
        ref.read(_playbackPreventsBlankingProvider)) {
      return;
    }
    _blankTimer = Timer(timeout, () {
      FocusManager.instance.primaryFocus?.unfocus();
      setState(() => _blanked = true);
      unawaited(_power.setBlanked(true));
    });
  }

  void _wake() {
    if (!_blanked) return;
    setState(() => _blanked = false);
    unawaited(_power.setBlanked(false));
  }

  // Run before focused controls: the key that wakes the screen must not also
  // type into a hidden field, pause playback or activate a hidden button.
  KeyEventResult _onKeyEvent(KeyEvent event) {
    if (event.synthesized) return KeyEventResult.ignored;
    if (_blanked || _wakeKeys.contains(event.physicalKey)) {
      if (event is KeyUpEvent) {
        _wakeKeys.remove(event.physicalKey);
      } else {
        _wakeKeys.add(event.physicalKey);
      }
      _wake();
      _recordActivity();
      return KeyEventResult.handled;
    }
    _recordActivity();
    return KeyEventResult.ignored;
  }

  void _pointerDown(PointerEvent event) {
    _pointers.add(event.pointer);
    if (_blanked) _consumeWakeGesture = true;
    _wake();
    _recordActivity();
  }

  void _pointerUp(PointerEvent event) {
    _pointers.remove(event.pointer);
    if (_consumeWakeGesture && _pointers.isEmpty) {
      setState(() => _consumeWakeGesture = false);
    }
    _recordActivity();
  }

  void _pointerActivity(PointerEvent event) {
    _wake();
    _recordActivity();
  }

  @override
  void dispose() {
    _idleTimer?.cancel();
    _blankTimer?.cancel();
    FocusManager.instance.removeEarlyKeyEventHandler(_onKeyEvent);
    unawaited(_power.setBlanked(false));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final kiosk = ref.watch(_displayStateProvider).kiosk;
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: _pointerDown,
      onPointerUp: _pointerUp,
      onPointerCancel: _pointerUp,
      onPointerMove: _pointerActivity,
      onPointerHover: _pointerActivity,
      onPointerSignal: _pointerActivity,
      onPointerPanZoomStart: _pointerDown,
      onPointerPanZoomUpdate: _pointerActivity,
      onPointerPanZoomEnd: _pointerUp,
      // Switch in one frame: no full-screen clipping, scaling or offscreen
      // texture during a transition on the server's display.
      child: IgnorePointer(
        ignoring: _consumeWakeGesture,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Offstage(
              offstage: kiosk || _blanked,
              child: TickerMode(
                enabled: !kiosk && !_blanked,
                child: ExcludeFocus(
                  excluding: kiosk || _blanked,
                  child: widget.child,
                ),
              ),
            ),
            if (kiosk)
              // A separate route gives the display its own Back and focus
              // scope, independent of the app's open dialogs.
              Offstage(
                offstage: _blanked,
                child: TickerMode(
                  enabled: !_blanked,
                  child: ExcludeFocus(
                    excluding: _blanked,
                    child: HeroControllerScope.none(
                      child: Navigator(
                        onGenerateRoute: (_) => MaterialPageRoute<void>(
                          builder: (_) => const KioskScreen(),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            if (_blanked)
              Positioned.fill(
                child: Semantics(
                  label: 'Display asleep. Touch to wake.',
                  child: const MouseRegion(
                    cursor: SystemMouseCursors.none,
                    child: ColoredBox(
                      key: ValueKey('display-blanked'),
                      color: Colors.black,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
