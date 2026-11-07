import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'kalinka_popover.dart';

/// Navigation Back: the filter controls' 40dp circle in a 48dp target.
/// Album artwork keeps its own separately shaded Back control.
class KalinkaBackButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final String label;

  const KalinkaBackButton({
    super.key,
    required this.onPressed,
    this.label = 'Back',
  });

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: label,
    onPressed: onPressed == null
        ? null
        : () => KalinkaPopupOrigin.run(context, onPressed!),
    icon: Icon(Icons.arrow_back, size: 22, semanticLabel: label),
    style: ButtonStyle(
      fixedSize: const WidgetStatePropertyAll(Size.square(40)),
      minimumSize: const WidgetStatePropertyAll(Size.square(40)),
      maximumSize: const WidgetStatePropertyAll(Size.square(40)),
      padding: const WidgetStatePropertyAll(EdgeInsets.zero),
      tapTargetSize: MaterialTapTargetSize.padded,
      visualDensity: VisualDensity.standard,
      shape: const WidgetStatePropertyAll(CircleBorder()),
      foregroundColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.disabled)
            ? KalinkaColors.textMuted
            : KalinkaColors.textPrimary,
      ),
      overlayColor: const WidgetStatePropertyAll(Colors.transparent),
      backgroundColor: WidgetStateProperty.resolveWith(
        (states) =>
            states.any(
              {
                WidgetState.hovered,
                WidgetState.pressed,
                WidgetState.focused,
              }.contains,
            )
            ? KalinkaColors.surfaceOverlay
            : KalinkaColors.surfaceElevated,
      ),
      side: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.focused)) {
          return const BorderSide(color: KalinkaColors.textPrimary, width: 2);
        }
        return BorderSide(
          color: states.any({WidgetState.hovered, WidgetState.pressed}.contains)
              ? KalinkaColors.textMuted
              : KalinkaColors.borderDefault,
        );
      }),
      animationDuration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 130),
    ),
  );
}
