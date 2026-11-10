import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// A touch-sized row of alternate letters, wrapping on narrow displays.
/// The keypad supplies cased options and performs the eventual insertion.
Future<String?> showKeyboardAccentPicker(
  BuildContext context,
  List<String> options,
  Offset globalPosition,
) {
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
  final position = overlay.globalToLocal(globalPosition);
  return showGeneralDialog<String>(
    context: context,
    useRootNavigator: false,
    requestFocus: false,
    barrierDismissible: true,
    barrierLabel: 'Dismiss accented characters',
    barrierColor: Colors.transparent,
    transitionDuration: Duration.zero,
    pageBuilder: (context, _, _) =>
        _AccentChoices(options: options, position: position),
  );
}

class _AccentChoices extends StatelessWidget {
  const _AccentChoices({required this.options, required this.position});

  final List<String> options;
  final Offset position;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      const margin = 8.0;
      const padding = 8.0;
      const gap = 4.0;
      final extent = math.max(
        48.0,
        MediaQuery.textScalerOf(context).scale(20) + 16,
      );
      final available = constraints.maxWidth - 2 * (margin + padding);
      final columns = ((available + gap) / (extent + gap)).floor().clamp(
        1,
        options.length,
      );
      final rows = (options.length / columns).ceil();
      final width = columns * extent + (columns - 1) * gap + 2 * padding;
      final height = rows * extent + (rows - 1) * gap + 2 * padding;
      final left = (position.dx - width / 2).clamp(
        margin,
        math.max(margin, constraints.maxWidth - width - margin),
      );
      // Place above the held key when there is room, otherwise below it.
      final above = position.dy - height - margin;
      final top = (above >= margin ? above : position.dy + margin).clamp(
        margin,
        math.max(margin, constraints.maxHeight - height - margin),
      );

      return Stack(
        children: [
          Positioned(
            left: left.toDouble(),
            top: top.toDouble(),
            width: width,
            child: TextFieldTapRegion(
              child: ExcludeFocus(
                child: Semantics(
                  namesRoute: true,
                  label: 'Accented characters',
                  child: Material(
                    key: const ValueKey('keyboard-accent-picker'),
                    color: KalinkaColors.surfaceDialog,
                    surfaceTintColor: Colors.transparent,
                    elevation: 8,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: const BorderSide(
                        color: KalinkaColors.borderDefault,
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(padding),
                      child: Wrap(
                        spacing: gap,
                        runSpacing: gap,
                        children: [
                          for (final option in options)
                            SizedBox(
                              width: extent,
                              height: extent,
                              child: TextButton(
                                key: ValueKey('keyboard-accent-$option'),
                                onPressed: () =>
                                    Navigator.of(context).pop(option),
                                style: TextButton.styleFrom(
                                  padding: EdgeInsets.zero,
                                  foregroundColor: KalinkaColors.textPrimary,
                                  backgroundColor:
                                      KalinkaColors.surfaceElevated,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  textStyle: KalinkaTextStyles.trayRowLabel
                                      .copyWith(fontSize: 20),
                                ),
                                child: Text(option),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    },
  );
}
