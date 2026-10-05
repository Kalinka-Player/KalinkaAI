import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/demo_mode.dart';
import '../theme/app_theme.dart';
import 'kalinka_button.dart';
import 'kalinka_dialog.dart';

/// On the demo server, shows [DemoReadOnlyDialog] in place of a save; true
/// when it did, so the caller goes no further.
Future<bool> refusedAsDemo(BuildContext context, WidgetRef ref) async {
  if (!ref.read(demoModeProvider)) return false;
  await showKalinkaDialog<void>(
    context: context,
    builder: (_) => const DemoReadOnlyDialog(),
  );
  return true;
}

/// Says why settings cannot be applied on the demo server, in place of the
/// save or restart the user asked for. Launched from Settings, which lives in
/// the left panel on tablet. Show via [showKalinkaDialog].
class DemoReadOnlyDialog extends StatelessWidget {
  const DemoReadOnlyDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return KalinkaDialog(
      side: KalinkaDialogSide.left,
      icon: Icons.lock_outline_rounded,
      iconGlyphColor: KalinkaColors.accentTint,
      title: 'This is the demo server',
      message:
          'You can explore and change settings here, but they can’t be saved '
          'or applied, and the server can’t be restarted. Connect to your own '
          'Kalinka server to keep your changes.',
      actions: [
        KalinkaButton(
          label: 'Got it',
          variant: KalinkaButtonVariant.accent,
          fullWidth: true,
          onTap: () => Navigator.pop(context),
        ),
      ],
    );
  }
}
