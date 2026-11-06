import 'package:flutter/material.dart';

import 'app_theme.dart';

/// The look of a field in a sheet: filled, rounded, and berry-edged while it
/// holds the focus. Sheets ask for one line of text at a time, so they all
/// wear the same one.
InputDecoration kalinkaFieldDecoration({
  required String hint,
  Widget? prefixIcon,
}) => InputDecoration(
  hintText: hint,
  hintStyle: KalinkaTextStyles.trackRowSubtitle,
  prefixIcon: prefixIcon,
  counterText: '',
  filled: true,
  fillColor: KalinkaColors.surfaceElevated,
  enabledBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(12),
    borderSide: const BorderSide(color: KalinkaColors.borderDefault),
  ),
  focusedBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(12),
    borderSide: const BorderSide(color: KalinkaColors.accent),
  ),
);

/// What a field holds, as an option row draws a choice. For a [DropdownMenu],
/// which dims its own text while off; a [TextField] takes [kalinkaFieldText].
final kalinkaFieldTextStyle = KalinkaFonts.sans(
  fontSize: KalinkaTypography.baseSize + 3,
  fontWeight: FontWeight.w400,
  letterSpacing: -0.1,
  color: KalinkaColors.textPrimary,
);

/// [style] (by default [kalinkaFieldTextStyle]) in primary text, dimmed as
/// Material dims it while the field is off. Left to the theme, a field takes
/// Material's baseline colour rather than the app's.
WidgetStateTextStyle kalinkaFieldText([TextStyle? style]) {
  final on = (style ?? kalinkaFieldTextStyle).copyWith(
    color: KalinkaColors.textPrimary,
  );
  final off = on.copyWith(
    color: KalinkaColors.textPrimary.withValues(alpha: 0.38),
  );
  return WidgetStateTextStyle.resolveWith(
    (states) => states.contains(WidgetState.disabled) ? off : on,
  );
}
