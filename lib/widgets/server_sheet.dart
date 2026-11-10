import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/app_version_provider.dart';
import '../providers/box_control_provider.dart';
import '../providers/power_off_status_provider.dart';
import '../providers/connection_settings_provider.dart';
import '../providers/connection_state_provider.dart';
import '../providers/demo_mode.dart';
import '../providers/server_info_provider.dart';
import '../providers/shell_nav_provider.dart';
import '../providers/supervisor_api.dart';
import '../theme/app_theme.dart';
import 'kalinka_bottom_sheet.dart';

/// Actions that can be returned from the server sheet.
enum ServerSheetAction { openDiscovery, openPlugins, powerOff }

/// The server menu's body, shown through [showKalinkaBottomSheet]: a bottom
/// sheet on phone, a dialog on wider windows.
class ServerSheetContent extends ConsumerWidget {
  const ServerSheetContent({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connectionState = ref.watch(connectionStateProvider);
    final settings = ref.watch(connectionSettingsProvider);
    final serverInfo = ref.watch(serverInfoProvider);

    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Section label
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
            child: Text('SERVER', style: KalinkaTextStyles.sectionHeaderMuted),
          ),
          // Status card
          _ServerStatusCard(
            connectionState: connectionState,
            settings: settings,
            serverInfo: serverInfo,
          ),
          const SizedBox(height: 4),
          // Separator
          const SheetDivider(),
          if (ref.watch(configurationAvailableProvider))
            _PluginsRow(
              onTap: () =>
                  Navigator.pop(context, ServerSheetAction.openPlugins),
            ),
          // Web is bound to its serving origin — no discovery, no disconnect.
          if (!kIsWeb) ...[
            const SheetDivider(),
            // Connect to different server
            SheetRow(
              icon: Icons.language,
              iconBackground: KalinkaColors.surfaceOverlay,
              iconColor: KalinkaColors.textSecondary,
              label: 'Connect to different server',
              sublabel: 'Scan network for other instances',
              trailing: const SheetChevron(),
              onTap: () {
                Navigator.pop(context, ServerSheetAction.openDiscovery);
              },
            ),
            const SheetDivider(),
            // Disconnect
            SheetRow(
              icon: Icons.logout,
              iconBackground: KalinkaColors.accent.withValues(alpha: 0.14),
              iconColor: KalinkaColors.accent,
              label: 'Disconnect',
              onTap: () async {
                await ref
                    .read(connectionSettingsProvider.notifier)
                    .clearDevice();
                ref.read(connectionStateProvider.notifier).disconnected();
                if (context.mounted) Navigator.pop(context);
              },
            ),
          ],
          _PowerOffRow(
            onTap: () => Navigator.pop(context, ServerSheetAction.powerOff),
          ),
          const _AppVersionFooter(),
        ],
      ),
    );
  }
}

/// Muted app version line at the bottom of the sheet.
class _AppVersionFooter extends ConsumerWidget {
  const _AppVersionFooter();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final info = ref.watch(appVersionProvider).value;
    if (info == null) return const SizedBox.shrink();

    // Prefer the git-derived version when the build embedded one (release
    // script); it carries commits-since-tag + hash for untagged builds.
    final label = gitDescribe.isNotEmpty
        ? 'Kalinka $gitDescribe'
        : 'Kalinka v${info.version}';

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 4),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: KalinkaTextStyles.timeLabel.copyWith(
          color: KalinkaColors.textMuted,
        ),
      ),
    );
  }
}

class _ServerStatusCard extends ConsumerWidget {
  final ConnectionStatus connectionState;
  final ConnectionSettings settings;
  final AsyncValue<ServerInfo> serverInfo;

  const _ServerStatusCard({
    required this.connectionState,
    required this.settings,
    required this.serverInfo,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDemo = ref.watch(demoModeProvider);
    Color dotColor;
    String stateLabel;
    switch (connectionState) {
      case ConnectionStatus.connected:
        dotColor = KalinkaColors.statusOnline;
        stateLabel = 'Online';
      case ConnectionStatus.reconnecting:
        dotColor = KalinkaColors.statusPending;
        stateLabel = 'Reconnecting';
      case ConnectionStatus.offline:
        dotColor = KalinkaColors.statusOffline;
        stateLabel = 'Offline';
      case ConnectionStatus.connecting:
        dotColor = KalinkaColors.statusPending;
        stateLabel = 'Connecting';
      case ConnectionStatus.none:
        dotColor = KalinkaColors.textMuted;
        stateLabel = 'Not connected';
    }

    final latencyText = serverInfo.whenOrNull(
      data: (info) => '${info.latencyMs}ms',
    );
    final versionText = serverInfo.whenOrNull(data: (info) => info.version);

    final detailParts = <String>[
      if (settings.host.isNotEmpty) settings.displayAddress,
      if (versionText != null) 'v$versionText',
      if (latencyText != null && connectionState == ConnectionStatus.connected)
        latencyText,
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: KalinkaColors.surfaceInput,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: KalinkaColors.borderDefault),
        ),
        child: Row(
          children: [
            // State dot
            const SizedBox(width: 4),
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: dotColor,
                shape: BoxShape.circle,
                boxShadow: connectionState == ConnectionStatus.connected
                    ? [
                        BoxShadow(
                          color: dotColor.withValues(alpha: 0.6),
                          blurRadius: 6,
                        ),
                      ]
                    : null,
              ),
            ),
            const SizedBox(width: 28),
            // Server name + details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          settings.name.isNotEmpty
                              ? settings.name
                              : 'No server configured',
                          style: KalinkaTextStyles.trayRowLabel.copyWith(
                            fontSize: KalinkaTypography.baseSize + 3,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (isDemo) ...[
                        const SizedBox(width: 8),
                        const _DemoPill(),
                      ],
                    ],
                  ),
                  if (detailParts.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      detailParts.join(' \u00b7 '),
                      style: KalinkaTextStyles.trayRowSublabel.copyWith(
                        color: KalinkaColors.textMuted,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            // State label
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: dotColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: dotColor.withValues(alpha: 0.25)),
              ),
              child: Text(
                stateLabel,
                style: KalinkaTextStyles.tagPill.copyWith(
                  color: dotColor,
                  fontSize: KalinkaTypography.baseSize - 2,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Marks the read-only demo server, so a visitor knows why changes are
/// refused.
class _DemoPill extends StatelessWidget {
  const _DemoPill();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: KalinkaColors.surfaceElevated,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: KalinkaColors.borderDefault),
      ),
      child: Text(
        'DEMO',
        style: KalinkaTextStyles.tagPill.copyWith(
          color: KalinkaColors.textMuted,
          fontSize: KalinkaTypography.baseSize - 2,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

/// The same capability-gated shutdown action on phone, tablet and web.
class _PowerOffRow extends ConsumerWidget {
  final VoidCallback onTap;

  const _PowerOffRow({required this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final control = ref.watch(boxControlProvider);
    if (control.isLoading ||
        control.hasError ||
        control.value?.offers(BoxAction.powerOff) != true) {
      return const SizedBox.shrink();
    }
    return Column(
      children: [
        const SheetDivider(),
        SheetRow(
          icon: Icons.power_settings_new,
          iconBackground: KalinkaColors.actionDelete.withValues(alpha: 0.14),
          iconColor: KalinkaColors.actionDelete,
          label:
              ref.watch(currentPowerOffStatusProvider)?.countdownLabel ??
              'Power off',
          onTap: onTap,
        ),
      ],
    );
  }
}

class _PluginsRow extends StatelessWidget {
  final VoidCallback onTap;
  const _PluginsRow({required this.onTap});

  @override
  Widget build(BuildContext context) => SheetRow(
    icon: Icons.settings_outlined,
    iconBackground: KalinkaColors.surfaceOverlay,
    iconColor: KalinkaColors.textSecondary,
    label: 'Settings',
    sublabel: 'Music sources, your player and hi-fi controls',
    trailing: const SheetChevron(),
    onTap: onTap,
  );
}
