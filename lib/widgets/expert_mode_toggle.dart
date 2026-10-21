import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/settings_provider.dart';
import '../theme/app_theme.dart';

/// Expert view control in a settings top bar, a round icon button.
/// Off = the structured page, on = the flat about:config-style list.
///
/// One switch for the whole app: expert is a disposition the user is in, not a
/// per-page mode, so the server's settings and a renderer's follow each other.
///
/// Grey while off; on, it is outlined in berry, as a mode the page stays in
/// rather than a choice being made (PALETTE.md, Fill or outline).
class ExpertModeToggle extends ConsumerWidget {
  const ExpertModeToggle({super.key});

  static const icon = Icons.data_object_rounded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final expert = ref.watch(expertModeProvider);
    final notifier = ref.read(expertModeProvider.notifier);
    // Merged: the button is its own semantics container, so the label and
    // toggled state would otherwise sit on a node that cannot be activated.
    return Tooltip(
      message: expert ? 'Expert settings, on' : 'Expert settings',
      excludeFromSemantics: true,
      child: MergeSemantics(
        child: Semantics(
          label: 'Expert settings',
          toggled: expert,
          child: IconButton(
            key: const ValueKey('expert-mode-toggle'),
            onPressed: notifier.toggle,
            style: _style(expert),
            icon: const Icon(icon, size: 20),
          ),
        ),
      ),
    );
  }

  static ButtonStyle _style(bool on) => ButtonStyle(
    fixedSize: const WidgetStatePropertyAll(Size.square(kKalinkaPillHeight)),
    minimumSize: const WidgetStatePropertyAll(Size.square(kKalinkaPillHeight)),
    padding: const WidgetStatePropertyAll(EdgeInsets.zero),
    // A 48dp target around the 40dp circle, on desktop too.
    tapTargetSize: MaterialTapTargetSize.padded,
    visualDensity: VisualDensity.standard,
    shape: const WidgetStatePropertyAll(CircleBorder()),
    backgroundColor: WidgetStatePropertyAll(
      on ? KalinkaColors.accentSubtle : KalinkaColors.surfaceElevated,
    ),
    foregroundColor: WidgetStatePropertyAll(
      on ? KalinkaColors.accentTint : KalinkaColors.textSecondary,
    ),
    side: WidgetStateProperty.resolveWith(
      (states) => states.contains(WidgetState.focused)
          ? const BorderSide(color: KalinkaColors.textPrimary, width: 2)
          : BorderSide(
              color: on
                  ? KalinkaColors.accentBorder
                  : KalinkaColors.borderDefault,
            ),
    ),
    overlayColor: WidgetStateProperty.resolveWith(
      (states) =>
          states.any({WidgetState.hovered, WidgetState.pressed}.contains)
          ? KalinkaColors.surfaceOverlay
          : null,
    ),
  );
}
