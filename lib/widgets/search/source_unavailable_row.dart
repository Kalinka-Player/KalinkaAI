import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../hover_text_action.dart';
import '../source_badge.dart';

/// A source that could not answer, in the place its rows would be. It says
/// so rather than reading as "nothing found", and offers the one thing that
/// helps: asking that source again.
class SourceUnavailableRow extends StatelessWidget {
  final String source;
  final String title;
  final VoidCallback onRetry;

  const SourceUnavailableRow({
    super.key,
    required this.source,
    required this.title,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          SourceTile(source: source),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '$title · Source unavailable',
              style: KalinkaTextStyles.trackRowSubtitle.copyWith(
                color: KalinkaColors.textSecondary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 12),
          HoverTextAction(
            label: 'RETRY',
            semanticsLabel: 'Retry $title',
            onTap: onRetry,
            color: KalinkaColors.accentTint,
            hoverColor: KalinkaColors.textPrimary,
          ),
        ],
      ),
    );
  }
}
