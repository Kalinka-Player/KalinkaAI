import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../kalinka_button.dart';
import '../kalinka_dialog.dart';
import 'inline_markdown.dart';

/// Opens a setting's detailed help and restores focus when it closes.
class SettingsHelpButton extends StatefulWidget {
  final String label;
  final String details;

  const SettingsHelpButton({
    super.key,
    required this.label,
    required this.details,
  });

  @override
  State<SettingsHelpButton> createState() => _SettingsHelpButtonState();
}

class _SettingsHelpButtonState extends State<SettingsHelpButton> {
  final _focusNode = FocusNode();

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _showHelp() async {
    await showKalinkaDialog<void>(
      context: context,
      builder: (context) => KalinkaDialog(
        side: KalinkaDialogSide.full,
        title: widget.label,
        content: InlineMarkdown(
          text: widget.details,
          style: KalinkaTextStyles.dialogBody,
        ),
        actions: [
          KalinkaButton(
            label: 'Close',
            variant: KalinkaButtonVariant.neutral,
            fullWidth: true,
            autofocus: true,
            onTap: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
    if (mounted) _focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) => IconButton(
    focusNode: _focusNode,
    tooltip: 'About ${widget.label}',
    icon: const Icon(Icons.info_outline, size: 18),
    style: ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
      foregroundColor: const WidgetStatePropertyAll(
        KalinkaColors.textSecondary,
      ),
      overlayColor: const WidgetStatePropertyAll(KalinkaColors.surfaceOverlay),
      side: WidgetStateProperty.resolveWith(
        (states) => BorderSide(
          color: states.contains(WidgetState.focused)
              ? KalinkaColors.textPrimary
              : Colors.transparent,
          width: 2,
        ),
      ),
    ),
    onPressed: _showHelp,
  );
}
