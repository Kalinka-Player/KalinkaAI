import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/connection_settings_provider.dart';
import '../providers/connection_state_provider.dart';
import '../theme/app_theme.dart';
import 'crumb_trail.dart';
import 'slide_in_panel.dart';

/// Back, the configuration breadcrumb and a connection dot.
class PluginTopBar extends ConsumerWidget {
  final List<String> trail;

  /// Called with the depth of the crumb tapped, never the last.
  final ValueChanged<int> onNavigate;

  /// The parent supplies the background; no fill or rule beneath.
  final bool transparent;

  const PluginTopBar({
    super.key,
    required this.trail,
    required this.onNavigate,
    this.transparent = false,
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
    return DecoratedBox(
      decoration: transparent
          ? const BoxDecoration()
          : const BoxDecoration(
              color: KalinkaColors.background,
              border: Border(
                bottom: BorderSide(color: KalinkaColors.borderSubtle),
              ),
            ),
      child: SizedBox(
        height: kKalinkaTopBarHeight,
        child: Padding(
          padding: const EdgeInsets.only(left: 6, right: 16),
          child: Row(
            children: [
              IconButton(
                key: const ValueKey('catalog-back'),
                tooltip: 'Back',
                onPressed: () => SlideInPanel.closeOf(context),
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                icon: const Icon(
                  Icons.arrow_back,
                  size: 22,
                  color: KalinkaColors.textPrimary,
                ),
              ),
              // 2, not 8: the first crumb brings 7 of its own so its hover
              // outline has somewhere to sit.
              const SizedBox(width: 2),
              Expanded(
                child: trail.length == 1
                    ? Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 7),
                        child: Semantics(
                          header: true,
                          child: Text(
                            trail.single,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: KalinkaTextStyles.trayRowLabel.copyWith(
                              fontSize: KalinkaTypography.baseSize + 6,
                            ),
                          ),
                        ),
                      )
                    : CrumbTrail(
                        names: trail,
                        onNavigate: onNavigate,
                        // Two steps at most: the page's name gets the room.
                        maxCrumbWidth: double.infinity,
                      ),
              ),
              const SizedBox(width: 12),
              Tooltip(
                message: label,
                child: Semantics(
                  label: name.isEmpty ? label : '$name, $label',
                  excludeSemantics: true,
                  child: SizedBox(
                    height: 42,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        DecoratedBox(
                          key: const ValueKey('catalog-connection-status'),
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                          ),
                          child: const SizedBox(width: 8, height: 8),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
