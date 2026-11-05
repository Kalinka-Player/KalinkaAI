import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// A failure told where it happened, under the row it belongs to: what went
/// wrong in red-edged quiet, optionally dismissible, with [footer] under the
/// words for a way to the details.
class FailureNote extends StatelessWidget {
  /// Said first, in the brighter text, where the failure has a name.
  final String? title;
  final String message;
  final TextStyle? textStyle;
  final Key? messageKey;
  final VoidCallback? onDismiss;
  final Key? dismissKey;
  final Widget? footer;

  const FailureNote({
    super.key,
    this.title,
    required this.message,
    this.textStyle,
    this.messageKey,
    this.onDismiss,
    this.dismissKey,
    this.footer,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.fromLTRB(10, 9, onDismiss == null ? 12 : 2, 9),
    decoration: BoxDecoration(
      color: KalinkaColors.statusOfflineSurface,
      border: Border.all(
        color: KalinkaColors.actionDelete.withValues(alpha: .25),
      ),
      borderRadius: BorderRadius.circular(9),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(
          Icons.error_outline,
          size: 17,
          color: KalinkaColors.actionDelete,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text.rich(
                TextSpan(
                  children: [
                    if (title case final title?)
                      TextSpan(
                        text: '$title. ',
                        style: const TextStyle(
                          color: KalinkaColors.textPrimary,
                        ),
                      ),
                    TextSpan(text: message),
                  ],
                ),
                key: messageKey,
                style: textStyle ?? KalinkaTextStyles.trayRowSublabel,
              ),
              ?footer,
            ],
          ),
        ),
        if (onDismiss != null)
          IconButton(
            key: dismissKey,
            tooltip: 'Dismiss',
            onPressed: onDismiss,
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
            style: IconButton.styleFrom(
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            color: KalinkaColors.textSecondary,
            icon: const Icon(Icons.close_rounded, size: 18),
          ),
      ],
    ),
  );
}
