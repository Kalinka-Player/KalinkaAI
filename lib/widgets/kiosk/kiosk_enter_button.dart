import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/kiosk_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/haptics.dart';
import '../transport_button.dart';

/// Switches the app to the full-screen now-playing display.
class KioskEnterButton extends ConsumerWidget {
  const KioskEnterButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Semantics(
      label: 'Now-playing display',
      button: true,
      child: Tooltip(
        message: 'Now-playing display',
        excludeFromSemantics: true,
        child: TransportButton(
          hitDiameter: 36,
          onTapDown: (_) => KalinkaHaptics.selectionClick(),
          onTap: () {
            // The display replaces the home screen; anything stacked above it
            // (the phone's player sheet) would stay on top.
            Navigator.of(context).popUntil((route) => route.isFirst);
            ref.read(kioskProvider.notifier).enter();
          },
          child: const Icon(
            Icons.fullscreen_rounded,
            size: 22,
            color: KalinkaColors.textSecondary,
          ),
        ),
      ),
    );
  }
}
