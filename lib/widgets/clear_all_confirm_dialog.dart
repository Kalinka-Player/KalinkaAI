import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/toast_provider.dart';
import '../theme/app_theme.dart';
import 'kalinka_button.dart';
import 'kalinka_dialog.dart';

/// Confirmation dialog for clearing the entire queue.
///
/// Returns `true` if the user confirmed and the clear succeeded,
/// `false` or `null` if cancelled. Shows over the player panel of the tablet
/// layout, where the queue lives. Show via [showKalinkaDialog].
class ClearAllConfirmDialog extends ConsumerWidget {
  final Future<void> Function() onConfirmClearAll;

  const ClearAllConfirmDialog({super.key, required this.onConfirmClearAll});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return KalinkaDialog(
      side: KalinkaDialogSide.left,
      icon: Icons.delete_outline,
      iconColor: KalinkaColors.actionDelete,
      title: 'Clear entire queue?',
      message:
          'This will remove all tracks including your play history. '
          'This cannot be undone.',
      actions: [
        KalinkaButton(
          label: 'Cancel',
          variant: KalinkaButtonVariant.neutral,
          fullWidth: true,
          onTap: () => Navigator.pop(context, false),
        ),
        KalinkaButton(
          label: 'Clear queue',
          variant: KalinkaButtonVariant.accent,
          fullWidth: true,
          onTap: () async {
            try {
              await onConfirmClearAll();
              if (context.mounted) Navigator.pop(context, true);
            } catch (e) {
              if (context.mounted) {
                ref
                    .read(toastProvider.notifier)
                    .show('Failed to clear queue: $e', isError: true);
              }
            }
          },
        ),
      ],
    );
  }
}
