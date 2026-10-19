import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data_model/plugin_catalog.dart';
import '../providers/connection_settings_provider.dart';
import '../providers/modules_state_provider.dart';
import '../providers/plugin_catalog_provider.dart';
import '../providers/plugin_state.dart';
import '../providers/restart_provider.dart';
import '../providers/server_info_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/supervisor_api.dart' show supervisorPort;
import '../providers/shell_nav_provider.dart';
import '../providers/server_update_provider.dart';
import '../providers/upgrade_provider.dart';
import '../providers/toast_provider.dart';
import '../theme/app_theme.dart';
import '../utils/click_cursor.dart';
import '../widgets/connection_banner.dart';
import '../widgets/demo_read_only_dialog.dart';
import '../widgets/kalinka_button.dart';
import '../widgets/kalinka_dialog.dart';
import '../widgets/configuration_appearance.dart';
import '../widgets/configuration_changes_bar.dart';
import '../widgets/configuration_page.dart';
import '../widgets/expert_settings_screen.dart';
import '../widgets/onboarding/step_network.dart';
import 'log_export_screen.dart';
import 'configuration_review_screen.dart';
import '../widgets/plugin_catalog_entry.dart';
import '../widgets/settings_top_bar.dart';
import '../widgets/restart_overlay.dart';
import '../widgets/restart_confirm_dialog.dart';
import 'server_configuration_screen.dart';
import '../widgets/slide_in_panel.dart';
import '../widgets/upgrade_overlay.dart';
import 'plugin_about_screen.dart';
import 'plugin_settings_screen.dart';

enum PluginTab { sources, server, devices }

/// Mono capitals for the tabs and section headings.
final _label = KalinkaTextStyles.sectionHeaderMuted.copyWith(
  fontSize: KalinkaTypography.baseSize + 2,
  letterSpacing: 1.4,
);

/// Configuration for music sources, the server and hi-fi controls.
class PluginCatalogScreen extends ConsumerStatefulWidget {
  final VoidCallback? onClose;
  final ValueChanged<bool>? onCoverageChanged;
  final bool handlesBack;
  const PluginCatalogScreen({
    super.key,
    this.onClose,
    this.onCoverageChanged,
    this.handlesBack = true,
  });
  @override
  ConsumerState<PluginCatalogScreen> createState() =>
      _PluginCatalogScreenState();
}

class _PluginCatalogScreenState extends ConsumerState<PluginCatalogScreen> {
  final _scroll = ScrollController();
  PluginTab _tab = PluginTab.sources;
  CatalogPlugin? _settingsFor;
  CatalogPlugin? _aboutFor;
  bool _advancedOpen = false;
  bool _logsOpen = false;
  bool _networkOpen = false;
  bool _restartOverlayOpen = false;
  List<String>? _reviewPaths;
  // The check before the restart is a round trip, and the banner stays up
  // for it; without this a second restart could start in the gap.
  bool _applying = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.invalidate(modulesStateProvider);
      ref.invalidate(serverUpdateProvider);
      // What went wrong on an earlier visit is old news.
      ref.read(pluginFailuresProvider.notifier).clear();
      // Normally read on connect. Never reread over staged edits.
      final settings = ref.read(settingsProvider);
      if (settings.schema == null && !settings.isLoading) {
        ref.read(settingsProvider.notifier).loadConfig();
      }
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _reload() {
    // Only reread the server cache, never an installation/update-check call.
    ref.invalidate(serverInfoProvider);
    ref.invalidate(pluginCatalogProvider);
    ref.invalidate(pluginUpdatesProvider);
    ref.invalidate(modulesStateProvider);
  }

  Future<void> _refresh() async {
    _reload();
    try {
      await ref.read(pluginCatalogProvider.future);
    } catch (_) {
      // Said on the page.
    }
  }

  Future<bool> _onApply() async {
    if (_applying ||
        _restartOverlayOpen ||
        await refusedAsDemo(context, ref) ||
        !mounted) {
      return false;
    }
    setState(() => _applying = true);
    try {
      final ready = await ref.read(settingsProvider.notifier).readyToApply();
      if (!mounted || !ready) return false;
      setState(() => _restartOverlayOpen = true);
      await ref.read(restartProvider.notifier).executeRestart();
      return mounted &&
          ref.read(restartProvider).isDone &&
          !ref.read(settingsProvider).hasPendingChanges;
    } finally {
      if (mounted) setState(() => _applying = false);
    }
  }

  Future<bool> _beforeClose() async {
    if (_applying ||
        _restartOverlayOpen ||
        ref.read(upgradeProvider).isUpgrading) {
      return false;
    }
    if (!ref.read(settingsProvider).hasPendingChanges) return true;
    final choice = await showKalinkaDialog<String>(
      context: context,
      builder: (context) => KalinkaDialog(
        side: KalinkaDialogSide.browsing,
        icon: Icons.tune,
        title: 'Apply your changes?',
        message: 'You have changes that have not been applied. Applying them restarts Kalinka and briefly stops the music.',
        content: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: 10,
          children: [
            KalinkaButton(
              label: 'Cancel',
              variant: KalinkaButtonVariant.neutral,
              fullWidth: true,
              onTap: () => Navigator.pop(context),
            ),
            KalinkaButton(
              key: const ValueKey('configuration-discard'),
              label: 'Discard',
              variant: KalinkaButtonVariant.neutral,
              fullWidth: true,
              onTap: () => Navigator.pop(context, 'discard'),
            ),
            KalinkaButton(
              key: const ValueKey('configuration-apply'),
              label: 'Apply & restart',
              fullWidth: true,
              onTap: () => Navigator.pop(context, 'apply'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return false;
    if (choice == 'discard') {
      ref.read(settingsProvider.notifier).discardAll();
      return true;
    }
    return choice == 'apply' ? _onApply() : false;
  }

  Future<void> _onRestart() async {
    final confirmed = await showKalinkaDialog<bool>(
      context: context,
      builder: (_) => const RestartConfirmDialog(),
    );
    if (mounted && confirmed == true) await _onApply();
  }

  Future<void> _run(CatalogPlugin plugin, PluginOperation operation) async {
    if (await refusedAsDemo(context, ref) || !mounted) return;
    if (operation == PluginOperation.uninstall) {
      final confirmed = await showKalinkaDialog<bool>(
        context: context,
        builder: (context) => KalinkaDialog(
          side: KalinkaDialogSide.browsing,
          icon: Icons.delete_outline,
          iconColor: KalinkaColors.actionDelete,
          title: 'Uninstall ${plugin.name}?',
          message:
              'The server restarts without it, which stops playback for a '
              'moment. You can add it again from Configuration.',
          actions: [
            KalinkaButton(
              label: 'Cancel',
              variant: KalinkaButtonVariant.neutral,
              fullWidth: true,
              onTap: () => Navigator.pop(context, false),
            ),
            KalinkaButton(
              label: 'Uninstall',
              fullWidth: true,
              onTap: () => Navigator.pop(context, true),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    // Already running: its own call reports how it ends.
    if (ref.read(pluginOperationsProvider).containsKey(plugin.id)) return;
    final outcome = await ref
        .read(pluginOperationsProvider.notifier)
        .run(plugin.id, operation, name: plugin.name);
    // A failure stays with the plugin, where it was asked for.
    if (outcome != PluginOutcome.done || !mounted) return;
    // Its pages went with it.
    if (operation == PluginOperation.uninstall) {
      setState(() {
        _settingsFor = null;
        _aboutFor = null;
      });
    }
    showSafeToast(switch (operation) {
      PluginOperation.install => '${plugin.name} installed',
      PluginOperation.uninstall => '${plugin.name} uninstalled',
      PluginOperation.update => '${plugin.name} updated',
    });
  }

  @override
  Widget build(BuildContext context) {
    // Home's gear asks for Music sources even while another tab is open.
    ref.listen(musicSourcesSettingsRequestProvider, (_, _) {
      setState(() {
        _tab = PluginTab.sources;
        _settingsFor = null;
        _aboutFor = null;
        _advancedOpen = false;
        _logsOpen = false;
        _networkOpen = false;
      });
      if (_scroll.hasClients) _scroll.jumpTo(0);
    });
    // The server restarts to carry a plugin operation out; that restart shows
    // here as one started by Apply does.
    ref.listen(restartProvider.select((s) => s.isRestarting), (_, restarting) {
      if (restarting && !_restartOverlayOpen) {
        setState(() => _restartOverlayOpen = true);
      }
    });
    ref.listen(connectionSettingsProvider.select((s) => (s.host, s.port)), (
      _,
      next,
    ) {
      setState(() {
        _settingsFor = null;
        _aboutFor = null;
        _tab = PluginTab.sources;
        _advancedOpen = false;
        _logsOpen = false;
        _networkOpen = false;
        _reviewPaths = null;
      });
      ref.read(pluginFailuresProvider.notifier).clear();
      if (_scroll.hasClients) _scroll.jumpTo(0);
    });
    final enabled = ref.watch(pluginCatalogEnabledProvider);
    final info = ref.watch(serverInfoProvider);
    final catalog = enabled ? ref.watch(pluginCatalogProvider) : null;
    final settings = ref.watch(settingsProvider);
    final gutter = ConfigurationAppearance.gutter(context);
    final upgrading = ref.watch(upgradeProvider).isUpgrading;

    final issuePaths = settings.issues.entries
        .where((entry) => entry.value.any((issue) => issue.isBlocking))
        .map((entry) => entry.key)
        .toList();
    final issueLabel = issuePaths.isEmpty
        ? null
        : '${configurationIssueLabel(settings.schema, issuePaths.first)}'
              '${issuePaths.length > 1 ? ' and ${issuePaths.length - 1} more' : ''}';
    return ConfigurationAppearance(
      child: Column(
        children: [
          Expanded(
            child: SlideInPanel(
              onClose: widget.onClose,
              beforeClose: _beforeClose,
              onCoverageChanged: widget.onCoverageChanged,
              handlesBack:
                  widget.handlesBack &&
                  _settingsFor == null &&
                  _aboutFor == null &&
                  !_advancedOpen &&
                  !_logsOpen &&
                  !_networkOpen &&
                  _reviewPaths == null &&
                  !_restartOverlayOpen &&
                  !upgrading,
              overlays: [
                if (_settingsFor case final plugin?)
                  PluginSettingsScreen(
                    key: ValueKey('plugin-settings-${plugin.id}'),
                    plugin: plugin,
                    actions: _actionsFor(plugin),
                    // About, over it, owns Back while open.
                    handlesBack:
                        widget.handlesBack &&
                        _aboutFor == null &&
                        _reviewPaths == null &&
                        !_restartOverlayOpen &&
                        !upgrading,
                    onClose: () => setState(() => _settingsFor = null),
                  ),
                if (_aboutFor case final plugin?)
                  PluginAboutScreen(
                    key: ValueKey('plugin-about-${plugin.id}'),
                    plugin: plugin,
                    actions: _actionsFor(plugin),
                    handlesBack:
                        widget.handlesBack &&
                        _reviewPaths == null &&
                        !_restartOverlayOpen &&
                        !upgrading,
                    onClose: () => setState(() => _aboutFor = null),
                  ),
                if (_advancedOpen)
                  ConfigurationPage(
                    key: const ValueKey('server-expert'),
                    title: 'Advanced settings',
                    description:
                        'All player settings. Search for the setting you need.',
                    onClose: () => setState(() => _advancedOpen = false),
                    handlesBack:
                        widget.handlesBack &&
                        _reviewPaths == null &&
                        !_restartOverlayOpen &&
                        !upgrading,
                    bodyBuilder: (heading) =>
                        ExpertSettingsScreen(heading: heading),
                  ),
                if (_networkOpen)
                  ConfigurationPage(
                    key: const ValueKey('server-network'),
                    title: 'Network',
                    description:
                        'How your streamer connects to your home network, '
                        'and the Wi-Fi network it joins.',
                    onClose: () => setState(() => _networkOpen = false),
                    handlesBack:
                        widget.handlesBack &&
                        _reviewPaths == null &&
                        !_restartOverlayOpen &&
                        !upgrading,
                    bodyBuilder: (heading) => ListView(
                      padding: const EdgeInsets.only(bottom: 32),
                      children: [
                        heading,
                        // The panel brings its own 20dp inset.
                        Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: gutter - 20,
                          ),
                          child: NetworkSetupPanel(
                            endpoint: ref
                                .read(connectionSettingsProvider)
                                .baseUrl
                                .replace(port: supervisorPort),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (_logsOpen)
                  LogExportScreen(
                    key: const ValueKey('server-logs'),
                    onClose: () => setState(() => _logsOpen = false),
                    handlesBack:
                        widget.handlesBack &&
                        _reviewPaths == null &&
                        !_restartOverlayOpen &&
                        !upgrading,
                  ),
                if (_reviewPaths case final paths?)
                  ConfigurationReviewScreen(
                    key: const ValueKey('configuration-review'),
                    paths: paths,
                    onClose: () => setState(() => _reviewPaths = null),
                    handlesBack:
                        widget.handlesBack &&
                        !_restartOverlayOpen &&
                        !upgrading,
                  ),
                if (_restartOverlayOpen)
                  RestartOverlay(
                    onDismiss: () {
                      setState(() => _restartOverlayOpen = false);
                      ref.invalidate(modulesStateProvider);
                      ref.invalidate(pluginUpdatesProvider);
                    },
                  ),
                if (upgrading)
                  UpgradeOverlay(
                    onDismiss: () {
                      if (!ref.read(settingsProvider).hasPendingChanges) {
                        ref.read(settingsProvider.notifier).loadConfig();
                      }
                    },
                  ),
              ],
              child: Material(
                color: KalinkaColors.background,
                child: SafeArea(
                  top: false,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SettingsTopBar(title: 'Configuration'),
                      ColoredBox(
                        color: KalinkaColors.background,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [const ConnectionBanner()],
                        ),
                      ),
                      Expanded(
                        child: RefreshIndicator(
                          onRefresh: _refresh,
                          color: KalinkaColors.accent,
                          backgroundColor: KalinkaColors.surfaceRaised,
                          child: CustomScrollView(
                            key: const ValueKey('catalog-scroll'),
                            controller: _scroll,
                            physics: const AlwaysScrollableScrollPhysics(),
                            slivers: [
                              _tabs(_tab, gutter),
                              if (_sectionDescription(_tab, gutter)
                                  case final description?)
                                SliverToBoxAdapter(child: description),
                              if (_tab == PluginTab.server)
                                ..._serverSlivers()
                              else if (info.isLoading)
                                const SliverFillRemaining(
                                  hasScrollBody: false,
                                  child: Center(
                                    child: CircularProgressIndicator(),
                                  ),
                                )
                              else if (!enabled)
                                const SliverFillRemaining(
                                  hasScrollBody: false,
                                  child: _Notice(
                                    'Plugin catalog preview is off or unavailable on this server. Enable it in Streamer → Advanced settings.',
                                  ),
                                )
                              else
                                ...catalog!.when<List<Widget>>(
                                  skipLoadingOnRefresh: false,
                                  data: (data) => _catalogSlivers(data, gutter),
                                  loading: () => const [
                                    SliverFillRemaining(
                                      hasScrollBody: false,
                                      child: Center(
                                        child: CircularProgressIndicator(),
                                      ),
                                    ),
                                  ],
                                  error: (error, _) => [
                                    SliverFillRemaining(
                                      hasScrollBody: false,
                                      child: _Notice(
                                        error is PluginCatalogException
                                            ? error.message
                                            : 'Could not read the plugin catalog. Try again.',
                                        onRetry: _reload,
                                      ),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          ConfigurationChangesBar(
            key: const ValueKey('configuration-changes'),
            count: settings.pendingCount,
            busy: _applying || _restartOverlayOpen || upgrading,
            issueLabel: issueLabel,
            onReview: () => setState(() => _reviewPaths = issuePaths),
            onDiscard: ref.read(settingsProvider.notifier).discardAll,
            onApply: _onApply,
          ),
        ],
      ),
    );
  }

  /// Called while building.
  PluginEntryActions _actionsFor(CatalogPlugin plugin) => PluginEntryActions(
    onEnabledChanged: (value) {
      final path = ref.read(pluginStateProvider(plugin)).enabledPath;
      if (path != null) {
        ref.read(settingsProvider.notifier).stageChange(path, value);
      }
    },
    onOpenSettings: () => setState(() => _settingsFor = plugin),
    onOpenAbout: () => setState(() => _aboutFor = plugin),
    onOperation: (operation) => _run(plugin, operation),
    onDismissFailure: () =>
        ref.read(pluginFailuresProvider.notifier).dismiss(plugin.id),
    canManage: ref.watch(pluginInstallationProvider),
  );

  List<Widget> _catalogSlivers(PluginCatalog catalog, double gutter) {
    if (catalog.status == 'disabled') {
      return const [
        SliverFillRemaining(
          hasScrollBody: false,
          child: _Notice('Public catalog fetching is disabled on this server.'),
        ),
      ];
    }
    if (catalog.status == 'unavailable') {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: _Notice(
            'The public catalog is not available yet. '
            'The server may be fetching it or unable to reach the feed. Try again shortly.',
            onRetry: _reload,
          ),
        ),
      ];
    }
    final modules = ref.watch(modulesStateProvider).value;
    final settings = ref.watch(settingsProvider);
    final updates = ref.watch(pluginUpdatesProvider).value ?? const {};
    final operations = ref.watch(pluginOperationsProvider);
    final failures = ref.watch(pluginFailuresProvider);
    final canManage = ref.watch(pluginInstallationProvider);
    final playerName = ref.watch(
      connectionSettingsProvider.select((s) => s.name),
    );
    final player = playerName.trim().isEmpty || playerName == 'Unknown'
        ? 'your player'
        : playerName;
    final states = {
      for (final plugin in catalog.plugins)
        plugin.id: PluginState.of(
          plugin,
          modules: modules,
          settings: settings,
          update: updates[plugin.id],
          operation: operations[plugin.id],
          failure: failures[plugin.id],
        ),
    };
    bool inTab(CatalogPlugin plugin) => switch (_tab) {
      PluginTab.sources => !plugin.isDevice,
      PluginTab.server => false,
      PluginTab.devices => plugin.isDevice,
    };
    final order = {
      for (final (i, plugin) in catalog.plugins.indexed) plugin.id: i,
    };
    // Official and stable first, else as the catalog lists them.
    final listed = catalog.plugins.where(inTab).toList()
      ..sort(
        (a, b) => a.rank != b.rank
            ? a.rank.compareTo(b.rank)
            : order[a.id]!.compareTo(order[b.id]!),
      );
    // Listed once each: those with a newer release first, with Update.
    final outdated = [
      for (final p in listed)
        if (states[p.id]!.update != null) p,
    ];
    // Switched off is still installed.
    final installed = [
      for (final p in listed)
        if (states[p.id]!.installed && states[p.id]!.update == null) p,
    ];
    final available = [
      for (final p in listed)
        if (!states[p.id]!.installed) p,
    ];
    // Said once, under the heading it holds back, not on every row.
    const manageNote = PluginNote(
      'This server cannot install, remove or update plugins yet.',
      key: ValueKey('catalog-manage-note'),
    );
    Widget row(CatalogPlugin plugin) => SliverPadding(
      padding: EdgeInsets.symmetric(horizontal: gutter),
      sliver: SliverToBoxAdapter(
        child: PluginRow(
          key: ValueKey('entry-${plugin.id}'),
          plugin: plugin,
          state: states[plugin.id]!,
          summary: plugin.blurb(player),
          actions: _actionsFor(plugin),
        ),
      ),
    );
    Widget note(Widget child) => SliverPadding(
      padding: EdgeInsets.fromLTRB(gutter, 12, gutter, 4),
      sliver: SliverToBoxAdapter(child: child),
    );

    return [
      if (catalog.status == 'stale')
        note(
          Text(
            'Showing a cached catalog. The latest refresh failed or the data is old.',
            style: KalinkaTextStyles.trayRowSublabel.copyWith(
              color: KalinkaColors.statusPendingLight,
            ),
          ),
        ),
      if (listed.isEmpty)
        note(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              'The catalog lists no plugins of this kind yet.',
              style: KalinkaTextStyles.trayRowSublabel,
            ),
          ),
        ),
      if (outdated.isNotEmpty) ...[
        _heading(
          outdated.length == 1 ? 'Update available' : 'Updates available',
          outdated.length,
          gutter,
          first: true,
        ),
        if (!canManage) note(manageNote),
        for (final plugin in outdated) row(plugin),
      ],
      if (installed.isNotEmpty) ...[
        _heading(
          _tab == PluginTab.devices ? 'Your controls' : 'Your sources',
          installed.length,
          gutter,
          first: outdated.isEmpty,
        ),
        for (final plugin in installed) row(plugin),
      ],
      if (available.isNotEmpty) ...[
        _heading(
          _tab == PluginTab.devices ? 'More controls' : 'More sources',
          available.length,
          gutter,
          first: outdated.isEmpty && installed.isEmpty,
        ),
        if (!canManage && outdated.isEmpty && available.any((p) => !p.bundled))
          note(manageNote),
        for (final plugin in available) row(plugin),
      ],
      const SliverToBoxAdapter(child: SizedBox(height: 32)),
    ];
  }

  Widget _tabs(PluginTab tab, double gutter) => PinnedHeaderSliver(
    child: ColoredBox(
      color: KalinkaColors.background,
      child: Stack(
        key: const ValueKey('catalog-tabs'),
        children: [
          // The grey rule the selected tab's berry line sits on.
          const Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SizedBox(
              height: 1,
              child: ColoredBox(color: KalinkaColors.borderDefault),
            ),
          ),
          // Each tab as wide as its label, an even gap apart, from the
          // content's inset. Short of room, all three truncate alike: the
          // labels are monospace, so their shares follow their lengths.
          Padding(
            padding: EdgeInsets.symmetric(horizontal: gutter),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                spacing: 24,
                children: [
                  for (final (option, label) in [
                    (PluginTab.sources, 'Music sources'),
                    (PluginTab.devices, 'HiFi control'),
                    (PluginTab.server, 'Streamer'),
                  ])
                    Flexible(
                      flex: label.length,
                      child: _PluginTabButton(
                        key: ValueKey('catalog-tab-${option.name}'),
                        label: label,
                        selected: tab == option,
                        onTap: () {
                          setState(() => _tab = option);
                          _scroll.jumpTo(0);
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );

  Widget? _sectionDescription(PluginTab tab, double gutter) {
    final description = switch (tab) {
      PluginTab.sources || PluginTab.server => null,
      PluginTab.devices =>
        'Let Kalinka adjust your amplifier’s volume and switch inputs.',
    };
    if (description == null) return null;
    return Padding(
      key: const ValueKey('catalog-description'),
      padding: EdgeInsets.fromLTRB(gutter, 16, gutter, 0),
      child: Text(
        description,
        style: KalinkaTextStyles.trayRowSublabel,
        softWrap: true,
        overflow: TextOverflow.clip,
      ),
    );
  }

  List<Widget> _serverSlivers() => [
    SliverToBoxAdapter(
      child: ServerSettingsBody(
        onRestart: _onRestart,
        onDownloadLogs: () => setState(() => _logsOpen = true),
        onNetwork: () => setState(() => _networkOpen = true),
        onAdvanced: () => setState(() => _advancedOpen = true),
      ),
    ),
    const SliverToBoxAdapter(child: SizedBox(height: 32)),
  ];

  /// The two sections stand further apart than the rows within them.
  Widget _heading(
    String title,
    int count,
    double gutter, {
    required bool first,
  }) => SliverPadding(
    padding: EdgeInsets.fromLTRB(gutter, first ? 24 : 36, gutter, 0),
    sliver: SliverToBoxAdapter(
      child: Semantics(
        header: true,
        label: '$title, $count',
        excludeSemantics: true,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 8),
          // Set as ShelfHeading sets tracks and albums; wraps rather than
          // overflows at large text sizes.
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: title.toUpperCase(),
                  style: KalinkaTextStyles.sectionLabel.copyWith(
                    color: KalinkaColors.textPrimary,
                  ),
                ),
                TextSpan(
                  text: ' · $count',
                  style: KalinkaTextStyles.sectionLabel.copyWith(
                    color: KalinkaColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

/// A mono label over a berry underline while selected.
class _PluginTabButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _PluginTabButton({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: Tooltip(
        message: label,
        excludeFromSemantics: true,
        child: MouseRegion(
          cursor: clickCursor(interactive: true),
          child: GestureDetector(
            onTap: onTap,
            behavior: HitTestBehavior.opaque,
            child: Container(
              constraints: const BoxConstraints(minHeight: 44),
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: selected ? KalinkaColors.accent : Colors.transparent,
                    width: 2,
                  ),
                ),
              ),
              // As wide as the label, so the underline is too.
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      label.toUpperCase(),
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                      style: _label.copyWith(
                        fontSize: KalinkaTypography.baseSize + 1,
                        letterSpacing: 1,
                        color: selected
                            ? KalinkaColors.textPrimary
                            : KalinkaColors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;
  const _Notice(this.message, {this.onRetry});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(message, style: KalinkaTextStyles.trayRowSublabel),
        if (onRetry != null) ...[
          const SizedBox(height: 14),
          KalinkaButton(
            key: const ValueKey('catalog-retry'),
            label: 'Try again',
            variant: KalinkaButtonVariant.neutral,
            size: KalinkaButtonSize.compact,
            onTap: onRetry,
          ),
        ],
      ],
    ),
  );
}
