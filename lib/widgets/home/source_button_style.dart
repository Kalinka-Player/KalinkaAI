import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

bool _lit(Set<WidgetState> states) =>
    states.contains(WidgetState.hovered) ||
    states.contains(WidgetState.focused) ||
    states.contains(WidgetState.pressed);

/// Shared treatment for music sources and Connect in the home source strip.
final homeSourceButtonStyle = ButtonStyle(
  minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
  padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 18)),
  shape: const WidgetStatePropertyAll(StadiumBorder()),
  textStyle: WidgetStatePropertyAll(
    KalinkaFonts.sans(fontSize: 16, fontWeight: FontWeight.w500),
  ),
  foregroundColor: WidgetStateProperty.resolveWith(
    (states) =>
        _lit(states) ? KalinkaColors.textPrimary : KalinkaColors.textSecondary,
  ),
  backgroundColor: WidgetStateProperty.resolveWith(
    (states) =>
        _lit(states) ? KalinkaColors.surfaceOverlay : Colors.transparent,
  ),
  overlayColor: const WidgetStatePropertyAll(Colors.transparent),
);
