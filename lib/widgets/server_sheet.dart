import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/app_version_provider.dart';
import '../providers/connection_settings_provider.dart';
import '../providers/connection_state_provider.dart';
import '../providers/server_info_provider.dart';
import '../theme/app_theme.dart';
import '../utils/haptics.dart';
import 'kalinka_bottom_sheet.dart';

/// Actions that can be returned from the server sheet.
enum ServerSheetAction { openSettings, openDiscovery, openPlugins }

/// Content body for the server sheet — used directly by [showKalinkaBottomSheet]
/// on phone, and wrapped by [ServerSheet] (with animation/scrim) on tablet.
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
          // Server settings row
          SheetRow(
            icon: Icons.settings_outlined,
            iconBackground: KalinkaColors.surfaceOverlay,
            iconColor: KalinkaColors.textSecondary,
            label: 'Server settings',
            sublabel: 'Modules, audio, enrichment',
            trailing: const SheetChevron(),
            onTap: () {
              KalinkaHaptics.lightImpact();
              Navigator.pop(context, ServerSheetAction.openSettings);
            },
          ),
          if (ref.watch(pluginCatalogEnabledProvider))
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
                KalinkaHaptics.lightImpact();
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
                KalinkaHaptics.heavyImpact();
                await ref
                    .read(connectionSettingsProvider.notifier)
                    .clearDevice();
                ref.read(connectionStateProvider.notifier).disconnected();
                if (context.mounted) Navigator.pop(context);
              },
            ),
          ],
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

class _ServerStatusCard extends StatelessWidget {
  final ConnectionStatus connectionState;
  final ConnectionSettings settings;
  final AsyncValue<ServerInfo> serverInfo;

  const _ServerStatusCard({
    required this.connectionState,
    required this.settings,
    required this.serverInfo,
  });

  @override
  Widget build(BuildContext context) {
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
      if (settings.host.isNotEmpty) '${settings.host}:${settings.port}',
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
                  Text(
                    settings.name.isNotEmpty
                        ? settings.name
                        : 'No server configured',
                    style: KalinkaTextStyles.trayRowLabel.copyWith(
                      fontSize: KalinkaTypography.baseSize + 3,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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

/// Tablet-only: server sheet with its own animation and scrim.
///
/// On phone, use [showKalinkaBottomSheet] with [ServerSheetContent] instead.
class ServerSheet extends ConsumerStatefulWidget {
  final VoidCallback onClose;
  final VoidCallback onOpenDiscovery;
  final VoidCallback onOpenSettings;
  final VoidCallback onOpenPlugins;

  const ServerSheet({
    super.key,
    required this.onClose,
    required this.onOpenDiscovery,
    required this.onOpenSettings,
    required this.onOpenPlugins,
  });

  @override
  ConsumerState<ServerSheet> createState() => _ServerSheetState();
}

class _ServerSheetState extends ConsumerState<ServerSheet>
    with SingleTickerProviderStateMixin {
  late AnimationController _slideController;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    _slideAnimation = Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero)
        .animate(
          CurvedAnimation(
            parent: _slideController,
            curve: const Cubic(0.4, 0, 0.2, 1),
          ),
        );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _slideController,
        curve: const Interval(0.0, 0.75, curve: Curves.easeOut),
      ),
    );
    _slideController.forward();
  }

  @override
  void dispose() {
    _slideController.dispose();
    super.dispose();
  }

  Future<void> _animateClose() async {
    await _slideController.reverse();
    widget.onClose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: GestureDetector(
        onTap: _animateClose,
        child: Container(
          color: Colors.black.withValues(alpha: 0.60),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Flexible(
                child: SlideTransition(
                  position: _slideAnimation,
                  child: GestureDetector(
                    onTap: () {}, // Prevent backdrop tap from passing through
                    child: Container(
                      decoration: BoxDecoration(
                        color: KalinkaColors.surfaceRaised,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(24),
                        ),
                        border: const Border(
                          top: BorderSide(color: KalinkaColors.borderDefault),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.7),
                            blurRadius: 60,
                            offset: const Offset(0, -20),
                          ),
                        ],
                      ),
                      child: SafeArea(
                        top: false,
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // Drag handle
                              Center(
                                child: Container(
                                  width: 36,
                                  height: 4,
                                  margin: const EdgeInsets.only(top: 12),
                                  decoration: BoxDecoration(
                                    color: KalinkaColors.surfaceOverlay,
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                              ),
                              Flexible(
                                child: SingleChildScrollView(
                                  child: _TabletServerSheetContent(
                                    onClose: _animateClose,
                                    onOpenPlugins: () async {
                                      await _animateClose();
                                      widget.onOpenPlugins();
                                    },
                                    onOpenSettings: () async {
                                      await _animateClose();
                                      widget.onOpenSettings();
                                    },
                                    onOpenDiscovery: () async {
                                      await _animateClose();
                                      widget.onOpenDiscovery();
                                    },
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
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

/// Tablet-specific content that uses callback-based actions (animate-close
/// before triggering the next screen), unlike [ServerSheetContent] which
/// uses Navigator.pop with result values.
class _TabletServerSheetContent extends ConsumerWidget {
  final Future<void> Function() onClose;
  final VoidCallback onOpenSettings;
  final VoidCallback onOpenDiscovery;
  final VoidCallback onOpenPlugins;

  const _TabletServerSheetContent({
    required this.onClose,
    required this.onOpenSettings,
    required this.onOpenDiscovery,
    required this.onOpenPlugins,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connectionState = ref.watch(connectionStateProvider);
    final settings = ref.watch(connectionSettingsProvider);
    final serverInfo = ref.watch(serverInfoProvider);

    return Column(
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
        const SheetDivider(),
        SheetRow(
          icon: Icons.settings_outlined,
          iconBackground: KalinkaColors.surfaceOverlay,
          iconColor: KalinkaColors.textSecondary,
          label: 'Server settings',
          sublabel: 'Modules, audio, enrichment',
          trailing: const SheetChevron(),
          onTap: () {
            KalinkaHaptics.lightImpact();
            onOpenSettings();
          },
        ),
        if (ref.watch(pluginCatalogEnabledProvider))
          _PluginsRow(onTap: onOpenPlugins),
        // Web is bound to its serving origin — no discovery, no disconnect.
        if (!kIsWeb) ...[
          const SheetDivider(),
          SheetRow(
            icon: Icons.language,
            iconBackground: KalinkaColors.surfaceOverlay,
            iconColor: KalinkaColors.textSecondary,
            label: 'Connect to different server',
            sublabel: 'Scan network for other instances',
            trailing: const SheetChevron(),
            onTap: () {
              KalinkaHaptics.lightImpact();
              onOpenDiscovery();
            },
          ),
          const SheetDivider(),
          SheetRow(
            icon: Icons.logout,
            iconBackground: KalinkaColors.accent.withValues(alpha: 0.14),
            iconColor: KalinkaColors.accent,
            label: 'Disconnect',
            onTap: () async {
              KalinkaHaptics.heavyImpact();
              await ref.read(connectionSettingsProvider.notifier).clearDevice();
              ref.read(connectionStateProvider.notifier).disconnected();
              await onClose();
            },
          ),
        ],
        const _AppVersionFooter(),
      ],
    );
  }
}

class _PluginsRow extends StatelessWidget {
  final VoidCallback onTap;
  const _PluginsRow({required this.onTap});

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      const SheetDivider(),
      SheetRow(
        icon: Icons.extension_outlined,
        iconBackground: KalinkaColors.surfaceOverlay,
        iconColor: KalinkaColors.textSecondary,
        label: 'Plugins',
        sublabel: 'Browse sources and device controls · Preview',
        trailing: const SheetChevron(),
        onTap: () {
          KalinkaHaptics.lightImpact();
          onTap();
        },
      ),
    ],
  );
}
