import 'package:flutter/material.dart';
import '../../data_model/presentation_schema.dart' show ConfigIssue;
import '../../theme/app_theme.dart';
import 'inline_markdown.dart';
import 'issue_notes.dart';

/// A single setting row with label, optional sublabel, staged/non-default pills,
/// and a control widget on the right.
///
/// Use [isVertical] for controls that need full width (enum pills, list editors).
class SettingsRow extends StatelessWidget {
  final String label;
  final String? sublabel;
  final bool isStaged;
  final bool differsFromDefault;
  final Widget control;
  final bool isVertical;

  /// What the backend said is wrong with this field's staged value, shown
  /// under the control. A control that can place them more precisely — a
  /// list editor, which puts each one under its own item — takes them
  /// itself and leaves this empty.
  final List<ConfigIssue> issues;

  const SettingsRow({
    super.key,
    required this.label,
    this.sublabel,
    this.isStaged = false,
    this.differsFromDefault = false,
    required this.control,
    this.isVertical = false,
    this.issues = const [],
  });

  @override
  Widget build(BuildContext context) {
    final showAmber = isStaged || differsFromDefault;
    final pillText = isStaged ? 'Staged' : 'Differs from Default';

    return Container(
      decoration: showAmber
          ? BoxDecoration(
              color: KalinkaColors.statusPending.withValues(alpha: 0.04),
            )
          : null,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Amber left bar
          if (showAmber)
            Container(
              width: 1,
              constraints: const BoxConstraints(minHeight: 44),
              decoration: BoxDecoration(
                color: KalinkaColors.statusPending,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          // Content
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: isVertical
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildInfoBlock(showAmber, pillText),
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
                            Expanded(
                              child: _buildInfoBlock(showAmber, pillText),
                            ),
                            const SizedBox(width: 12),
                            control,
                          ],
                        ),
                        IssueNotes(issues: issues),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoBlock(bool showAmber, String pillText) {
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
        if (showAmber) ...[
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: KalinkaColors.statusPending.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: KalinkaColors.statusPending.withValues(alpha: 0.2),
              ),
            ),
            child: Text(
              pillText,
              style: KalinkaTextStyles.tagPill.copyWith(
                color: KalinkaColors.statusPending,
                letterSpacing: 0.8,
              ),
            ),
          ),
        ],
      ],
    );
  }
}
