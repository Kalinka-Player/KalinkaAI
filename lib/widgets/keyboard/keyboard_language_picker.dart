import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:virtual_keypad/virtual_keypad.dart';

import '../../theme/app_theme.dart';
import '../overlay_card.dart';

/// A temporary grid above the keyboard. It uses the window's available space,
/// leaving the keyboard's height and the active input connection unchanged.
class KeyboardLanguagePicker extends StatelessWidget {
  const KeyboardLanguagePicker({
    super.key,
    required this.languages,
    required this.selectedCode,
    required this.origin,
    required this.onSelected,
    required this.onCancel,
  });

  final List<KeyboardLanguage> languages;
  final String selectedCode;
  final Offset origin;
  final ValueChanged<String> onSelected;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final media = MediaQuery.of(context);
      const margin = 12.0;
      const padding = 12.0;
      const gap = 8.0;
      final width = math.min(
        900.0,
        constraints.maxWidth - media.padding.horizontal - 2 * margin,
      );
      final availableHeight =
          constraints.maxHeight - media.padding.vertical - 2 * margin;
      final contentWidth = width - 2 * padding;
      final style = KalinkaTextStyles.trayRowLabel;
      Size textSize(String text, TextStyle style, double width) {
        final painter = TextPainter(
          text: TextSpan(text: text, style: style),
          textDirection: Directionality.of(context),
          textScaler: media.textScaler,
        )..layout(maxWidth: math.max(1, width));
        final size = painter.size;
        painter.dispose();
        return size;
      }

      final headingStyle = KalinkaTextStyles.trayRowLabel;
      final headingHeight = math.max(
        48.0,
        textSize('Keyboard layout', headingStyle, contentWidth - 56).height,
      );
      var columns = width >= 800 ? 5 : 4;
      var compact = false;
      double cellWidth() =>
          ((contentWidth - (columns - 1) * gap) / columns).floorToDouble();
      final measuredHeights = <(int, bool), double>{};
      double cellHeight() => measuredHeights.putIfAbsent(
        (columns, compact),
        () => math.max(
          48.0,
          languages
              .map(
                (language) =>
                    textSize(
                      compact ? language.code.toUpperCase() : language.name,
                      style,
                      cellWidth() - (compact ? 16 : 36),
                    ).height +
                    (compact ? 24 : 16),
              )
              .reduce(math.max),
        ),
      );
      double gridHeight() {
        final rows = (languages.length / columns).ceil();
        return rows * cellHeight() + (rows - 1) * gap;
      }

      double totalHeight() => 2 * padding + headingHeight + gap + gridHeight();
      // Avoid breaking a language name across several lines on narrow panes.
      // Codes keep every choice readable; full names remain in tooltips and
      // accessibility labels. Never introduce a scrollable language list.
      compact = languages.any(
        (language) =>
            textSize(language.name, style, double.infinity).width >
            cellWidth() - 36,
      );
      if (totalHeight() > availableHeight) compact = true;
      final compactWidth = languages
          .map(
            (language) =>
                textSize(
                  language.code.toUpperCase(),
                  style,
                  double.infinity,
                ).width +
                16,
          )
          .reduce(math.max);
      final maxColumns = math.max(
        1,
        ((contentWidth + gap) / (math.max(48, compactWidth) + gap)).floor(),
      );
      if (compact) columns = math.min(columns, maxColumns);
      while (totalHeight() > availableHeight && columns < maxColumns) {
        columns++;
      }
      final height = totalHeight();
      final left =
          media.padding.left +
          (constraints.maxWidth - media.padding.horizontal - width) / 2;
      final top = (origin.dy - height - gap).clamp(
        media.padding.top + margin,
        math.max(
          media.padding.top + margin,
          constraints.maxHeight - media.padding.bottom - margin - height,
        ),
      );

      return TextFieldTapRegion(
        child: ExcludeFocus(
          child: Stack(
            children: [
              Positioned.fill(
                child: ModalBarrier(
                  color: Colors.transparent,
                  dismissible: true,
                  onDismiss: onCancel,
                  semanticsLabel: 'Dismiss keyboard layouts',
                ),
              ),
              Positioned(
                left: left,
                top: top.toDouble(),
                width: width,
                child: Semantics(
                  namesRoute: true,
                  label: 'Keyboard layout',
                  child: Material(
                    key: const ValueKey('keyboard-language-picker'),
                    color: KalinkaColors.surfaceDialog,
                    surfaceTintColor: Colors.transparent,
                    elevation: 8,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: const BorderSide(
                        color: KalinkaColors.borderDefault,
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(padding),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            height: headingHeight,
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    'Keyboard layout',
                                    style: headingStyle,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                OverlayCloseButton(
                                  onTap: onCancel,
                                  label: 'Close keyboard layouts',
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: gap),
                          Wrap(
                            key: ValueKey('keyboard-language-grid-$columns'),
                            spacing: gap,
                            runSpacing: gap,
                            children: [
                              for (final language in languages)
                                SizedBox(
                                  width: cellWidth(),
                                  height: cellHeight(),
                                  child: Semantics(
                                    selected: language.code == selectedCode,
                                    child: Tooltip(
                                      excludeFromSemantics: true,
                                      message:
                                          language.nativeName == language.name
                                          ? language.name
                                          : '${language.name} · ${language.nativeName}',
                                      child: TextButton(
                                        key: ValueKey(
                                          'keyboard-language-${language.code}',
                                        ),
                                        onPressed: () =>
                                            onSelected(language.code),
                                        style: TextButton.styleFrom(
                                          padding: const EdgeInsets.all(8),
                                          backgroundColor:
                                              KalinkaColors.surfaceElevated,
                                          foregroundColor:
                                              language.code == selectedCode
                                              ? KalinkaColors.textPrimary
                                              : KalinkaColors.textSecondary,
                                          side: BorderSide(
                                            color: language.code == selectedCode
                                                ? KalinkaColors.textPrimary
                                                : KalinkaColors.borderDefault,
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                          ),
                                          textStyle: style,
                                        ),
                                        child: compact
                                            ? Stack(
                                                fit: StackFit.expand,
                                                clipBehavior: Clip.none,
                                                children: [
                                                  Padding(
                                                    padding:
                                                        const EdgeInsets.only(
                                                          top: 8,
                                                        ),
                                                    child: Center(
                                                      child: Text(
                                                        language.code
                                                            .toUpperCase(),
                                                        semanticsLabel:
                                                            language.name,
                                                      ),
                                                    ),
                                                  ),
                                                  if (language.code ==
                                                      selectedCode)
                                                    const Positioned(
                                                      top: -4,
                                                      right: -4,
                                                      child: Icon(
                                                        Icons.check_rounded,
                                                        size: 12,
                                                      ),
                                                    ),
                                                ],
                                              )
                                            : Row(
                                                children: [
                                                  SizedBox(
                                                    width: 20,
                                                    child:
                                                        language.code ==
                                                            selectedCode
                                                        ? const Icon(
                                                            Icons.check_rounded,
                                                            size: 16,
                                                          )
                                                        : null,
                                                  ),
                                                  Expanded(
                                                    child: Text(
                                                      language.name,
                                                      semanticsLabel:
                                                          language.name,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
