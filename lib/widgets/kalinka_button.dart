import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../utils/click_cursor.dart';

enum KalinkaButtonVariant { accent, neutral }

enum KalinkaButtonSize { normal, compact }

/// Unified CTA button for the Kalinka app.
///
/// - [accent]: filled accent bg, accent border, surfaceBase text (primary action)
/// - [neutral]: surfaceElevated bg, default border, secondary text (secondary action)
///
/// Use [fullWidth] for buttons that should stretch to fill their parent.
/// Use [enabled] to dim and disable the button (e.g. nothing selected yet).
/// Use [leading] to add an icon before the label.
class KalinkaButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final KalinkaButtonVariant variant;
  final KalinkaButtonSize size;
  final bool fullWidth;
  final bool enabled;
  final Widget? leading;

  const KalinkaButton({
    super.key,
    required this.label,
    this.onTap,
    this.variant = KalinkaButtonVariant.accent,
    this.size = KalinkaButtonSize.normal,
    this.fullWidth = false,
    this.enabled = true,
    this.leading,
  });

  @override
  Widget build(BuildContext context) {
    final (bgColor, borderColor, textColor) = switch (variant) {
      KalinkaButtonVariant.accent => (
        KalinkaColors.accent,
        KalinkaColors.accent,
        KalinkaColors.textPrimary,
      ),
      KalinkaButtonVariant.neutral => (
        KalinkaColors.surfaceElevated,
        KalinkaColors.borderDefault,
        KalinkaColors.textSecondary,
      ),
    };

    final (vPad, hPad, radius) = switch (size) {
      KalinkaButtonSize.normal => (14.0, 20.0, 13.0),
      KalinkaButtonSize.compact => (8.0, 14.0, 10.0),
    };

    final labelText = Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: KalinkaTextStyles.trayRowLabel.copyWith(
        color: textColor,
        fontSize: size == KalinkaButtonSize.normal
            ? KalinkaTypography.baseSize + 3
            : KalinkaTypography.baseSize + 2,
      ),
    );

    return AnimatedOpacity(
      opacity: enabled ? 1.0 : 0.35,
      duration: const Duration(milliseconds: 150),
      child: Material(
        color: bgColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
          side: BorderSide(color: borderColor),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          mouseCursor: clickCursor(interactive: enabled && onTap != null),
          onTap: enabled ? onTap : null,
          overlayColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.pressed) ||
                states.contains(WidgetState.hovered)) {
              return Colors.white.withValues(alpha: 0.07);
            }
            return null;
          }),
          child: Container(
            width: fullWidth ? double.infinity : null,
            padding: EdgeInsets.symmetric(vertical: vPad, horizontal: hPad),
            child: Row(
              mainAxisSize: fullWidth ? MainAxisSize.max : MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (leading != null) ...[leading!, const SizedBox(width: 8)],
                // Flexible lets long labels truncate, but only when the
                // width is bounded — intrinsic buttons can sit in unbounded
                // Rows, where it would assert.
                if (fullWidth) Flexible(child: labelText) else labelText,
              ],
            ),
          ),
        ),
      ),
    );
  }
}
