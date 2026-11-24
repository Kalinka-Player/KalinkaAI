import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../data_model/room_eq.dart';
import '../../theme/app_theme.dart';
import 'filter_shape_icon.dart';

/// The controls for the currently selected band, sized to the editor pane.
class BandEditorHeader extends StatelessWidget {
  const BandEditorHeader({
    super.key,
    required this.number,
    required this.shape,
    required this.onShapeChanged,
    required this.onRemove,
  });

  final int number;
  final FilterShape shape;
  final ValueChanged<FilterShape>? onShapeChanged;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final titleStyle = KalinkaTextStyles.cardTitle;
    final labelStyle = KalinkaTextStyles.trayRowLabel;
    final titleText = 'Band $number';
    final direction = Directionality.of(context);
    final scaler = MediaQuery.textScalerOf(context);
    double textWidth(String text, TextStyle style) => TextPainter.computeWidth(
      text: TextSpan(text: text, style: style),
      textDirection: direction,
      textScaler: scaler,
    ).ceilToDouble();

    const gap = 12.0, iconSize = 22.0, arrowSize = 20.0, fieldPadding = 12.0;
    final fieldWidth =
        FilterShape.values
            .map((type) => textWidth(type.label, labelStyle))
            .reduce(math.max) +
        iconSize +
        8 +
        arrowSize +
        2 * fieldPadding +
        4;
    final titleWidth = textWidth(titleText, titleStyle);
    final removeWidth = textWidth('Remove', labelStyle) + iconSize + 8 + 32;
    final title = Text(titleText, style: titleStyle);
    final radius = BorderRadius.circular(10);
    final field = Tooltip(
      message: 'Filter type for band $number',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: KalinkaColors.surfaceElevated,
          borderRadius: radius,
          border: Border.all(color: KalinkaColors.borderDefault),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<FilterShape>(
            value: shape,
            isExpanded: true,
            itemHeight: null,
            padding: const EdgeInsets.symmetric(horizontal: fieldPadding),
            borderRadius: radius,
            dropdownColor: KalinkaColors.surfaceDialog,
            focusColor: KalinkaColors.surfaceOverlay,
            icon: const Icon(
              Icons.keyboard_arrow_down_rounded,
              size: arrowSize,
            ),
            style: labelStyle.copyWith(
              color: onShapeChanged == null
                  ? KalinkaColors.textMuted
                  : KalinkaColors.textPrimary,
            ),
            items: [
              for (final type in FilterShape.values)
                DropdownMenuItem(
                  value: type,
                  child: Row(
                    children: [
                      FilterShapeIcon(
                        type,
                        color: onShapeChanged == null
                            ? KalinkaColors.textMuted
                            : KalinkaColors.textPrimary,
                      ),
                      const SizedBox(width: 8),
                      Flexible(child: Text(type.label)),
                    ],
                  ),
                ),
            ],
            onChanged: onShapeChanged == null
                ? null
                : (type) {
                    if (type != null && type != shape) onShapeChanged!(type);
                  },
          ),
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: LayoutBuilder(
        builder: (context, box) {
          final rowSpace = box.maxWidth - titleWidth - fieldWidth - 2 * gap;
          final showLabel = rowSpace >= removeWidth;
          final stacked = rowSpace < kMinInteractiveDimension;
          final remove = Tooltip(
            message: 'Remove band $number',
            excludeFromSemantics: true,
            child: OutlinedButton(
              onPressed: onRemove,
              style:
                  OutlinedButton.styleFrom(
                    backgroundColor: KalinkaColors.surfaceElevated,
                    foregroundColor: KalinkaColors.textPrimary,
                    textStyle: labelStyle,
                    minimumSize: const Size.square(kMinInteractiveDimension),
                    padding: EdgeInsets.symmetric(
                      horizontal: showLabel ? 16 : 0,
                    ),
                    shape: showLabel
                        ? const StadiumBorder()
                        : const CircleBorder(),
                  ).copyWith(
                    side: WidgetStateProperty.resolveWith(
                      (states) => states.contains(WidgetState.focused)
                          ? const BorderSide(
                              color: KalinkaColors.textPrimary,
                              width: 2,
                            )
                          : const BorderSide(
                              color: KalinkaColors.borderDefault,
                            ),
                    ),
                  ),
              child: Semantics(
                label: 'Remove band $number',
                excludeSemantics: true,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.delete_outline_rounded,
                      size: iconSize,
                      color: onRemove == null
                          ? KalinkaColors.textMuted
                          : KalinkaColors.accentTint,
                    ),
                    if (showLabel) ...[
                      const SizedBox(width: 8),
                      const Text('Remove'),
                    ],
                  ],
                ),
              ),
            ),
          );
          if (stacked) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 8,
              children: [
                Row(
                  children: [
                    Expanded(child: title),
                    const SizedBox(width: gap),
                    remove,
                  ],
                ),
                field,
              ],
            );
          }
          return Row(
            spacing: gap,
            children: [
              title,
              Expanded(
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: SizedBox(width: fieldWidth, child: field),
                ),
              ),
              remove,
            ],
          );
        },
      ),
    );
  }
}
