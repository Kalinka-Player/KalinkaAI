import 'package:flutter/material.dart';
import '../../data_model/presentation_schema.dart' show ConfigIssue;
import '../../theme/app_theme.dart';
import 'inline_markdown.dart';
import 'issue_notes.dart';

/// Space either side of a settings card's rows.
const double kSettingsGutter = 16;

/// A single setting row with label, optional sublabel, and a control widget on
/// the right. A staged row is tinted amber, without changing its layout.
///
/// Use [isVertical] for controls that need full width (enum pills, list editors).
class SettingsRow extends StatelessWidget {
  final String label;
  final String? sublabel;
  final bool isStaged;
  final Widget control;
  final bool isVertical;

  /// What the backend said is wrong with this field's staged value, shown
  /// under the control. Left empty by controls that place them per item.
  final List<ConfigIssue> issues;

  /// A button beside the label of a vertical row, acting on the whole of it.
  final Widget? action;

  /// Space either side of the content: [kSettingsGutter] in a settings card,
  /// a sheet's own gutter in a sheet.
  final double gutter;

  const SettingsRow({
    super.key,
    required this.label,
    this.sublabel,
    this.isStaged = false,
    required this.control,
    this.isVertical = false,
    this.issues = const [],
    this.action,
    this.gutter = kSettingsGutter,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: isStaged
          ? KalinkaColors.statusPending.withValues(alpha: 0.04)
          : null,
      // Painted over the row rather than laid out with it, so staging never
      // shifts the content off its gutter.
      foregroundDecoration: isStaged
          ? const BoxDecoration(
              border: Border(
                left: BorderSide(color: KalinkaColors.statusPending),
              ),
            )
          : null,
      padding: EdgeInsets.symmetric(horizontal: gutter, vertical: 12),
      child: isVertical
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: _buildInfoBlock()),
                    if (action != null) ...[const SizedBox(width: 12), action!],
                  ],
                ),
                const SizedBox(height: 10),
                SizedBox(width: double.infinity, child: control),
                IssueNotes(issues: issues),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: _buildInfoBlock()),
                    const SizedBox(width: 12),
                    control,
                  ],
                ),
                IssueNotes(issues: issues),
              ],
            ),
    );
  }

  Widget _buildInfoBlock() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: KalinkaTextStyles.trayRowLabel),
        if (sublabel != null) ...[
          const SizedBox(height: 2),
          InlineMarkdown(
            text: sublabel!,
            style: KalinkaTextStyles.trayRowSublabel,
          ),
        ],
      ],
    );
  }
}
