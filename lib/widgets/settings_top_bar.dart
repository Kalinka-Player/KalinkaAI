import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/connection_settings_provider.dart';
import '../providers/connection_state_provider.dart';
import '../theme/app_theme.dart';
import 'configuration_appearance.dart';
import 'slide_in_panel.dart';

/// Back to the previous page, the current page title and a connection dot.
/// Owns the top safe inset so the header background reaches the screen edge.
class SettingsTopBar extends ConsumerWidget {
  final String title;

  /// At most one icon action.
  final Widget? action;

  /// Off where the page is left another way, such as the navigation rail.
  final bool showBack;

  const SettingsTopBar({
    super.key,
    required this.title,
    this.action,
    this.showBack = true,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (color, label) = switch (ref.watch(connectionStateProvider)) {
      ConnectionStatus.connected => (
        KalinkaColors.statusOnline,
        'Server online',
      ),
      ConnectionStatus.connecting => (
        KalinkaColors.statusPending,
        'Connecting',
      ),
      ConnectionStatus.reconnecting => (
        KalinkaColors.statusPending,
        'Reconnecting',
      ),
      ConnectionStatus.offline => (
        KalinkaColors.statusOffline,
        'Server offline',
      ),
      ConnectionStatus.none => (KalinkaColors.textMuted, 'Not connected'),
    };
    final saved = ref.watch(connectionSettingsProvider.select((s) => s.name));
    final name = saved == 'Unknown' ? '' : saved;
    final heading = Semantics(
      header: true,
      child: Text(title, style: KalinkaTextStyles.settingsPageTitle),
    );
    return Material(
      color: KalinkaColors.surfaceBase,
      child: SafeArea(
        bottom: false,
        child: DecoratedBox(
          decoration: const BoxDecoration(
            border: Border(
              bottom: BorderSide(color: KalinkaColors.borderSubtle),
            ),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: kKalinkaTopBarHeight),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(6, 2, 16, 2),
              child: IconButtonTheme(
                data: IconButtonThemeData(style: settingsIconButtonStyle),
                child: Builder(
                  builder: (context) {
                    // Large type gets the full panel width instead of a narrow
                    // column between Back, About and the status indicator.
                    final stacked =
                        MediaQuery.textScalerOf(context).scale(18) > 27;
                    final gutter = ConfigurationAppearance.gutter(context);
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            if (showBack)
                              IconButton(
                                key: const ValueKey('settings-back'),
                                tooltip: 'Back',
                                onPressed: () => SlideInPanel.closeOf(context),
                                constraints: const BoxConstraints(
                                  minWidth: 48,
                                  minHeight: 48,
                                ),
                                icon: const Icon(
                                  Icons.arrow_back,
                                  size: 22,
                                  color: KalinkaColors.textPrimary,
                                ),
                              )
                            else
                              // The title on the content's gutter.
                              SizedBox(width: gutter - 14),
                            if (stacked)
                              const Spacer()
                            else ...[
                              const SizedBox(width: 8),
                              Expanded(child: heading),
                            ],
                            if (action != null) ...[
                              const SizedBox(width: 8),
                              action!,
                            ],
                            const SizedBox(width: 12),
                            Tooltip(
                              message: label,
                              child: Semantics(
                                label: name.isEmpty ? label : '$name, $label',
                                excludeSemantics: true,
                                child: SizedBox(
                                  height: 48,
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      DecoratedBox(
                                        key: const ValueKey(
                                          'settings-connection-status',
                                        ),
                                        decoration: BoxDecoration(
                                          color: color,
                                          shape: BoxShape.circle,
                                        ),
                                        child: const SizedBox(
                                          width: 8,
                                          height: 8,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (stacked)
                          Padding(
                            padding: EdgeInsets.fromLTRB(
                              gutter - 6,
                              0,
                              gutter - 16,
                              10,
                            ),
                            child: heading,
                          ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Native keyboard/tooltip behaviour, with the same 48dp target and focus ring
/// for Back, About and other settings icon actions.
final settingsIconButtonStyle = ButtonStyle(
  minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
  padding: const WidgetStatePropertyAll(EdgeInsets.all(12)),
  foregroundColor: const WidgetStatePropertyAll(KalinkaColors.textPrimary),
  shape: WidgetStatePropertyAll(
    RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
  ),
  side: WidgetStateProperty.resolveWith(
    (states) => states.contains(WidgetState.focused)
        ? const BorderSide(color: KalinkaColors.textPrimary, width: 2)
        : BorderSide.none,
  ),
  overlayColor: WidgetStateProperty.resolveWith(
    (states) => states.any({WidgetState.hovered, WidgetState.pressed}.contains)
        ? KalinkaColors.surfaceOverlay
        : null,
  ),
);
