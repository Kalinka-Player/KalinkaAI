import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import 'inline_markdown.dart';

/// Tinted note displayed above cards or inside module bodies to surface
/// errors and warnings.
///
/// Severity controls the tint (amber for warnings, red for errors).
/// Message accepts the same minimal markdown as `InlineMarkdown`
/// (`**bold**`, `` `code` ``) so backend status messages render with
/// emphasis intact.
enum WarningNoteSeverity { warning, error }

class WarningNote extends StatelessWidget {
  final String message;
  final WarningNoteSeverity severity;

  /// Only as wide as [message] needs, rather than the whole width given.
  final bool fitsContent;
  final EdgeInsetsGeometry margin;

  const WarningNote({
    super.key,
    required this.message,
    this.severity = WarningNoteSeverity.error,
    this.fitsContent = false,
    this.margin = const EdgeInsets.fromLTRB(16, 0, 16, 12),
  });

  @override
  Widget build(BuildContext context) {
    final tint = switch (severity) {
      WarningNoteSeverity.warning => KalinkaColors.statusPending,
      WarningNoteSeverity.error => KalinkaColors.statusOffline,
    };

    final text = InlineMarkdown(
      text: message,
      style: KalinkaTextStyles.trayRowSublabel.copyWith(
        fontSize: KalinkaTypography.baseSize + 2,
        height: 1.6,
      ),
    );
    final note = Container(
      margin: margin,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: tint.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisSize: fitsContent ? MainAxisSize.min : MainAxisSize.max,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: KalinkaColors.goldSubtle.withValues(alpha: 0.28),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.warning_amber_outlined, size: 24, color: tint),
          ),
          const SizedBox(width: 8),
          if (fitsContent) Flexible(child: text) else Expanded(child: text),
        ],
      ),
    );
    return fitsContent
        ? Align(alignment: AlignmentDirectional.centerStart, child: note)
        : note;
  }
}
