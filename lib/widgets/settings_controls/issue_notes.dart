import 'package:flutter/material.dart';
import '../../data_model/presentation_schema.dart' show ConfigIssue;
import '../../theme/app_theme.dart';
import 'inline_markdown.dart';

/// The colour a control takes on while something is wrong with its value,
/// or null when nothing is. Red refuses the save, amber does not.
Color? issueBorderColor(List<ConfigIssue> issues) {
  if (issues.isEmpty) return null;
  return issues.any((issue) => issue.isBlocking)
      ? KalinkaColors.actionDelete
      : KalinkaColors.statusPending;
}

/// What the backend said about a value, one line each, under the control it
/// belongs to.
class IssueNotes extends StatelessWidget {
  final List<ConfigIssue> issues;
  final EdgeInsets padding;

  const IssueNotes({
    super.key,
    required this.issues,
    this.padding = const EdgeInsets.only(top: 5, left: 2),
  });

  @override
  Widget build(BuildContext context) {
    if (issues.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final issue in issues)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Icon(
                      issue.isBlocking
                          ? Icons.error_outline
                          : Icons.warning_amber_rounded,
                      size: 13,
                      color: issue.isBlocking
                          ? KalinkaColors.actionDelete
                          : KalinkaColors.statusPending,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Expanded(
                    child: InlineMarkdown(
                      text: issue.message,
                      style: KalinkaTextStyles.trayRowSublabel.copyWith(
                        color: issue.isBlocking
                            ? KalinkaColors.actionDelete
                            : KalinkaColors.statusPendingLight,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
