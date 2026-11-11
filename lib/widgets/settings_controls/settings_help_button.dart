import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/app_theme.dart';
import '../kalinka_button.dart';
import '../kalinka_dialog.dart';
import 'inline_markdown.dart';

/// Opens detailed help and restores focus after keyboard dismissal.
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
    var restoreKeyboardFocus = false;
    _focusNode.unfocus();
    await showKalinkaDialog<void>(
      context: context,
      builder: (context) => PopScope<void>(
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) {
            restoreKeyboardFocus =
                HardwareKeyboard.instance.logicalKeysPressed.isNotEmpty;
          }
        },
        child: KalinkaDialog(
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
      ),
    );
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (restoreKeyboardFocus) {
        _focusNode.requestFocus();
      } else {
        _focusNode.unfocus();
      }
    });
  }

  @override
  Widget build(BuildContext context) => IconButton(
    focusNode: _focusNode,
    tooltip: 'About ${widget.label}',
    icon: const Icon(Icons.info_outline, size: 18),
    style: ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
      foregroundColor: WidgetStateProperty.resolveWith(
        (states) =>
            states.any(
              {
                WidgetState.hovered,
                WidgetState.pressed,
                WidgetState.focused,
              }.contains,
            )
            ? KalinkaColors.textPrimary
            : KalinkaColors.textSecondary,
      ),
      backgroundColor: const WidgetStatePropertyAll(Colors.transparent),
      overlayColor: const WidgetStatePropertyAll(Colors.transparent),
      splashFactory: NoSplash.splashFactory,
      shape: const WidgetStatePropertyAll(
        RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(8)),
        ),
      ),
      side: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.focused)
            ? const BorderSide(color: KalinkaColors.textPrimary, width: 2)
            : BorderSide.none,
      ),
      animationDuration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 130),
    ),
    onPressed: _showHelp,
  );
}
