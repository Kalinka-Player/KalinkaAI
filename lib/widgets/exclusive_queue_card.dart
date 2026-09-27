import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data_model/data_model.dart';
import '../providers/source_modules_provider.dart';
import '../theme/app_theme.dart';

/// Heads the queue screen while a plugin plays exclusively: the queue that
/// plays now is the plugin's, managed in its own app, not Kalinka's.
class ExclusiveQueueCard extends ConsumerWidget {
  final PlaybackControl control;

  const ExclusiveQueueCard({super.key, required this.control});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final source = ref.watch(sourceDisplayInfoProvider)[control.pluginId];
    final appName = source?.title ?? control.title ?? '';

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: KalinkaColors.surfaceRaised,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: KalinkaColors.borderSubtle),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.format_list_bulleted_rounded,
            size: 24,
            color: KalinkaColors.textSecondary,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              'Playback queue is managed by $appName',
              style: KalinkaTextStyles.trayRowLabel,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
