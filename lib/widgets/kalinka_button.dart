import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

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

    // A compact button is a pill like the browsing actions beside it.
    final (minHeight, hPad) = switch (size) {
      KalinkaButtonSize.normal => (kKalinkaPillTarget, 24.0),
      KalinkaButtonSize.compact => (kKalinkaPillHeight, 18.0),
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
    final interactive = enabled && onTap != null;

    return AnimatedOpacity(
      opacity: enabled ? 1.0 : 0.35,
      duration: const Duration(milliseconds: 150),
      child: PillTarget(
        onTap: interactive ? onTap : null,
        child: Material(
          color: bgColor,
          shape: StadiumBorder(side: BorderSide(color: borderColor)),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            mouseCursor: clickCursor(interactive: interactive),
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
              constraints: BoxConstraints(minHeight: minHeight),
              padding: EdgeInsets.symmetric(vertical: 8, horizontal: hPad),
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
      ),
    );
  }
}

/// Pads a pill shorter than [kKalinkaPillTarget] out to that height, the
/// margin taking a tap as the pill itself would.
class PillTarget extends StatelessWidget {
  final VoidCallback? onTap;
  final Widget child;

  const PillTarget({super.key, required this.onTap, required this.child});

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: clickCursor(interactive: onTap != null),
    child: GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      excludeFromSemantics: true,
      child: _CentredInTarget(child: child),
    ),
  );
}

/// Centres its child in [kKalinkaPillTarget] of height, leaving the width
/// to the child, so a button stretched across a row still stretches.
class _CentredInTarget extends SingleChildRenderObjectWidget {
  const _CentredInTarget({super.child});

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderCentredInTarget();
}

class _RenderCentredInTarget extends RenderShiftedBox {
  _RenderCentredInTarget() : super(null);

  Size _sizeFor(BoxConstraints constraints, Size child) => constraints
      .constrain(Size(child.width, math.max(child.height, kKalinkaPillTarget)));

  @override
  double computeMinIntrinsicHeight(double width) =>
      math.max(super.computeMinIntrinsicHeight(width), kKalinkaPillTarget);

  @override
  double computeMaxIntrinsicHeight(double width) =>
      math.max(super.computeMaxIntrinsicHeight(width), kKalinkaPillTarget);

  @override
  Size computeDryLayout(BoxConstraints constraints) => _sizeFor(
    constraints,
    child!.getDryLayout(constraints.copyWith(minHeight: 0)),
  );

  @override
  void performLayout() {
    final child = this.child!;
    child.layout(constraints.copyWith(minHeight: 0), parentUsesSize: true);
    size = _sizeFor(constraints, child.size);
    (child.parentData! as BoxParentData).offset = Alignment.center.alongOffset(
      size - child.size as Offset,
    );
  }
}
