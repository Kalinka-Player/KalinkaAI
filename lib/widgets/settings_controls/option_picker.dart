import 'package:flutter/material.dart';
import '../../data_model/presentation_schema.dart' show OptionSpec;
import '../../theme/app_theme.dart';
import '../../utils/click_cursor.dart';
import '../../utils/haptics.dart';
import '../tap_highlight.dart';
import 'inline_markdown.dart';

/// The list of choices a settings control opens in a bottom sheet.
///
/// Shared by the dropdown, whose options are the only values the field may
/// hold, and by the combo, whose options are suggestions beside what the
/// user can type. The difference between those two is the caller's: this
/// draws rows and returns the one that was tapped.
///
/// [emptyMessage] is what stands in for the rows when there are none, which
/// only a suggestion list reaches — a list found on the network starts empty
/// and may stay that way.
class OptionPicker extends StatelessWidget {
  final List<OptionSpec> options;
  final String? selectedValue;
  final String? emptyMessage;

  const OptionPicker({
    super.key,
    required this.options,
    this.selectedValue,
    this.emptyMessage,
  });

  @override
  Widget build(BuildContext context) {
    // Cap height to about 70% of the screen so the sheet doesn't
    // dominate when there are many options (HDMI heavy systems can
    // produce 10+ entries). Built-in scrolling handles the overflow.
    final maxHeight = MediaQuery.of(context).size.height * 0.7;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: options.isEmpty
                ? _EmptyMessage(text: emptyMessage ?? 'Nothing to choose from')
                : ListView.builder(
                    shrinkWrap: true,
                    padding: const EdgeInsets.only(top: 8, bottom: 4),
                    itemCount: options.length,
                    itemBuilder: (ctx, i) => _OptionRow(
                      option: options[i],
                      selected: options[i].value == selectedValue,
                    ),
                  ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _OptionRow extends StatelessWidget {
  final OptionSpec option;
  final bool selected;

  const _OptionRow({required this.option, required this.selected});

  @override
  Widget build(BuildContext context) {
    final hasDescription =
        option.description != null && option.description!.isNotEmpty;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          KalinkaHaptics.selectionClick();
          Navigator.of(context).pop(option.value);
        },
        mouseCursor: clickCursor(interactive: true),
        overlayColor: kalinkaOverlay,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      option.label,
                      style: KalinkaTextStyles.trayRowLabel.copyWith(
                        color: selected
                            ? KalinkaColors.accent
                            : KalinkaColors.textPrimary,
                        fontSize: KalinkaTypography.baseSize + 3,
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.w400,
                      ),
                    ),
                    if (hasDescription)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: InlineMarkdown(
                          text: option.description!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: KalinkaTextStyles.trayRowLabel.copyWith(
                            color: KalinkaColors.textSecondary,
                            fontSize: KalinkaTypography.baseSize - 1,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (selected) ...[
                const SizedBox(width: 8),
                const Icon(Icons.check, size: 18, color: KalinkaColors.accent),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyMessage extends StatelessWidget {
  final String text;

  const _EmptyMessage({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: KalinkaTextStyles.trayRowSublabel.copyWith(
          fontSize: KalinkaTypography.baseSize + 1,
        ),
      ),
    );
  }
}
