import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/kiosk_provider.dart';
import '../providers/volume_activity_provider.dart';
import 'kiosk/kiosk_volume_control.dart';

/// The kiosk volume bar on a solid panel, above every Android app screen,
/// while the phone's volume keys or a touch on it keep it in use.
class ForegroundVolumeOverlay extends ConsumerStatefulWidget {
  final Widget child;

  const ForegroundVolumeOverlay({super.key, required this.child});

  @override
  ConsumerState<ForegroundVolumeOverlay> createState() =>
      _ForegroundVolumeOverlayState();
}

class _ForegroundVolumeOverlayState
    extends ConsumerState<ForegroundVolumeOverlay>
    with WidgetsBindingObserver {
  Timer? _timer;
  bool _visible = false;
  bool _foreground = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) {
      _timer?.cancel();
      setState(() => _visible = false);
    }
  }

  void _show() {
    if (!_foreground || ref.read(kioskActiveProvider)) return;
    _timer?.cancel();
    setState(() => _visible = true);
    _timer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _visible = false);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return widget.child;
    }
    ref.listen(volumeActivityProvider, (_, _) => _show());
    final kiosk = ref.watch(kioskActiveProvider);
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (!kiosk)
          Positioned.fill(
            child: SafeArea(
              minimum: const EdgeInsets.all(12),
              child: Align(
                alignment: Alignment.centerRight,
                child: Material(
                  type: MaterialType.transparency,
                  child: SizedBox(
                    height: 280,
                    child: KioskVolumeControl(
                      scale: 1,
                      visible: _visible,
                      onActivity: _show,
                      opaque: true,
                      // Only the phone's keys and touches bring it up.
                      revealOnChange: false,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
