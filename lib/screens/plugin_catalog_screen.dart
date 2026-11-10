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
import '../widgets/connection_banner.dart';
import '../widgets/demo_read_only_dialog.dart';
import '../widgets/kalinka_button.dart';
import '../widgets/kalinka_dialog.dart';
import '../widgets/configuration_appearance.dart';
import '../widgets/pending_changes_banner.dart';
import '../widgets/configuration_page.dart';
import '../widgets/expert_mode_toggle.dart';
import '../widgets/expert_settings_screen.dart';
import '../widgets/onboarding/step_network.dart';
import 'drives_and_shares_screen.dart';
import 'log_export_screen.dart';
import 'configuration_review_screen.dart';
import '../widgets/plugin_catalog_entry.dart';
import '../widgets/settings_top_bar.dart';
import '../widgets/section_tab_button.dart';
import '../widgets/restart_overlay.dart';
import '../widgets/restart_confirm_dialog.dart';
import 'server_configuration_screen.dart';
import '../widgets/slide_in_panel.dart';
import '../widgets/upgrade_overlay.dart';
import 'plugin_about_screen.dart';
import 'plugin_settings_screen.dart';

enum PluginTab { sources, server, devices }

/// Configuration for music sources, the server and hi-fi controls.
class PluginCatalogScreen extends ConsumerStatefulWidget {
  final VoidCallback? onClose;

  /// Whether it has a top bar, with Back; off beside the navigation rail,
  /// which names it and is how it is left there, so the tabs start at the
  /// top.
  final bool showBack;
  final ValueChanged<bool>? onCoverageChanged;
  final bool handlesBack;

  /// False switches to it in place, as to another destination.
  final bool slides;
  const PluginCatalogScreen({
    super.key,
    this.onClose,
    this.showBack = true,
    this.onCoverageChanged,
    this.handlesBack = true,
    this.slides = true,
  });
  @override
  PluginCatalogScreenState createState() => PluginCatalogScreenState();
}

class PluginCatalogScreenState extends ConsumerState<PluginCatalogScreen> {
  final _scroll = ScrollController();
  PluginTab _tab = PluginTab.sources;
  CatalogPlugin? _settingsFor;
  CatalogPlugin? _aboutFor;
  bool _logsOpen = false;
  bool _networkOpen = false;
  bool _drivesOpen = false;
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
      // What went wrong on an earlier visit is old news; what is still
      // under way on the server is followed again from where it has got.
      ref.read(pluginFailuresProvider.notifier).clear();
      ref.read(pluginOperationsProvider.notifier).reattach();
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
    ref.invalidate(serverUpdateProvider);
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
      final notifier = ref.read(settingsProvider.notifier);
      final ready = await notifier.readyToApply();
      if (!mounted || !ready) return false;
      if (ref.read(settingsProvider).onlyLiveChanges) {
        await notifier.applyChanges();
        if (!mounted) return false;
        await notifier.loadConfig(preserveStagedChanges: true);
        ref.invalidate(modulesStateProvider);
        return mounted && !ref.read(settingsProvider).hasPendingChanges;
      }
      setState(() => _restartOverlayOpen = true);
      await ref.read(restartProvider.notifier).executeRestart();
      return mounted &&
          ref.read(restartProvider).isDone &&
          !ref.read(settingsProvider).hasPendingChanges;
    } catch (error) {
      showSafeToast('Could not apply settings: $error');
      return false;
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
    final restarts = !ref.read(settingsProvider).onlyLiveChanges;
    final choice = await showKalinkaDialog<String>(
      context: context,
      builder: (context) => KalinkaDialog(
        side: KalinkaDialogSide.browsing,
        icon: Icons.tune,
        title: 'Apply your changes?',
        message: restarts
            ? 'You have changes that have not been applied. Applying them restarts Kalinka and briefly stops the music.'
            : 'These changes apply without restarting Kalinka.',
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
              label: restarts ? 'Apply & restart' : 'Apply',
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

  /// Shell destinations use the same pending-change and operation guard as
  /// Back, including when a nested Configuration page is open.
  Future<bool> prepareToNavigate() => _beforeClose();

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
              'Anything playing from it stops; the rest plays on. You can '
              'install it again from Settings.',
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
    // A failure stays with the plugin, where it was asked for; the row
    // says the rest by where it now sits.
    if (outcome != PluginOutcome.done || !mounted) return;
    // Its pages went with it.
    if (operation == PluginOperation.uninstall) {
      setState(() {
        _settingsFor = null;
        _aboutFor = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Home's gear asks for Music sources even while another tab is open.
    ref.listen(musicSourcesSettingsRequestProvider, (_, _) {
      setState(() {
        _tab = PluginTab.sources;
        _settingsFor = null;
        _aboutFor = null;
        _logsOpen = false;
        _networkOpen = false;
        _drivesOpen = false;
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
        _logsOpen = false;
        _networkOpen = false;
        _drivesOpen = false;
        _reviewPaths = null;
      });
      ref.read(pluginFailuresProvider.notifier).clear();
      if (_scroll.hasClients) _scroll.jumpTo(0);
    });
    final available = ref.watch(pluginCatalogAvailableProvider);
    final info = ref.watch(serverInfoProvider);
    final catalog = available ? ref.watch(pluginCatalogProvider) : null;
    final updateCounts = _updateCounts(catalog?.value);
    final settings = ref.watch(settingsProvider);
    final upgrading = ref.watch(upgradeProvider).isUpgrading;
    final expert = ref.watch(expertModeProvider);

    final issuePaths = settings.issues.entries
        .where((entry) => entry.value.any((issue) => issue.isBlocking))
        .map((entry) => entry.key)
        .toList();
    final issueLabel = issuePaths.isEmpty
        ? null
        : '${configurationIssueLabel(settings.schema, issuePaths.first)}'
              '${issuePaths.length > 1 ? ' and ${issuePaths.length - 1} more' : ''}';
    return ConfigurationAppearance(
      child: Builder(
        builder: (context) {
          // Under the appearance, which sets how wide the gutter is.
          final gutter = ConfigurationAppearance.gutter(context);
          return Column(
            children: [
              Expanded(
                child: SlideInPanel(
                  slides: widget.slides,
                  onClose: widget.onClose,
                  beforeClose: _beforeClose,
                  onCoverageChanged: widget.onCoverageChanged,
                  handlesBack:
                      widget.handlesBack &&
                      _settingsFor == null &&
                      _aboutFor == null &&
                      !_logsOpen &&
                      !_networkOpen &&
                      !_drivesOpen &&
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
                    if (_drivesOpen)
                      DrivesAndSharesScreen(
                        key: const ValueKey('server-drives-and-shares'),
                        onClose: () => setState(() => _drivesOpen = false),
                        handlesBack:
                            widget.handlesBack &&
                            _reviewPaths == null &&
                            !_restartOverlayOpen &&
                            !upgrading,
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
                      // Without its bar the tabs take the top inset.
                      top: !widget.showBack,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Beside the rail, which names it and is how it is
                          // left, the tabs start at the top.
                          if (widget.showBack)
                            SettingsTopBar(
                              title: 'Settings',
                              // With its bar, the Expert switch moves up into
                              // it.
                              action: _tab == PluginTab.server
                                  ? const ExpertModeToggle()
                                  : null,
                            ),
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
                                  _tabs(_tab, gutter, updateCounts),
                                  if (_sectionDescription(_tab, gutter)
                                      case final description?)
                                    SliverToBoxAdapter(child: description),
                                  // Expert, the tab is the flat list of
                                  // every setting, found by name.
                                  if (_tab == PluginTab.server && expert)
                                    const ExpertSettingsScreen(sliver: true)
                                  else if (_tab == PluginTab.server)
                                    ..._serverSlivers()
                                  else if (info.isLoading)
                                    const SliverFillRemaining(
                                      hasScrollBody: false,
                                      child: Center(
                                        child: CircularProgressIndicator(),
                                      ),
                                    )
                                  else if (!available)
                                    ..._catalogSlivers(
                                      const PluginCatalog(status: 'disabled'),
                                      gutter,
                                      // A failed capability check says
                                      // nothing about what the server offers.
                                      notice: info.hasError
                                          ? _Notice(
                                              'Could not check what this server offers. Try again.',
                                              onRetry: _reload,
                                            )
                                          : info.value?.pluginCatalogOff == true
                                          ? const _Notice(
                                              'The plugin catalog is turned off on this server.',
                                            )
                                          // It lists one, but the connection
                                          // is down for now.
                                          : info.value?.pluginCatalog == true
                                          ? const _Notice(
                                              'The plugin catalog is unavailable until the server is connected again.',
                                            )
                                          : const _Notice(
                                              'This server does not offer the plugin catalog.',
                                            ),
                                    )
                                  else
                                    ...catalog!.when<List<Widget>>(
                                      skipLoadingOnRefresh: false,
                                      data: (data) =>
                                          _catalogSlivers(data, gutter),
                                      loading: () => _catalogSlivers(
                                        const PluginCatalog(
                                          status: 'unavailable',
                                        ),
                                        gutter,
                                        notice: const Center(
                                          child: CircularProgressIndicator(),
                                        ),
                                      ),
                                      error: (error, _) => _catalogSlivers(
                                        const PluginCatalog(
                                          status: 'unavailable',
                                        ),
                                        gutter,
                                        notice: _Notice(
                                          error is PluginCatalogException
                                              ? error.message
                                              : 'Could not read the plugin catalog. Try again.',
                                          onRetry: _reload,
                                        ),
                                      ),
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
              // Under every page Configuration opens, the page shrinking
              // to make room for it.
              PendingChangesBanner(
                key: const ValueKey('configuration-changes'),
                pendingCount: settings.pendingCount,
                consequence: settings.onlyLiveChanges
                    ? null
                    : 'restart required',
                busy: _applying || _restartOverlayOpen || upgrading,
                blocked: issueLabel != null,
                blockedReason: issueLabel == null ? null : 'check $issueLabel',
                onReview: () => setState(() => _reviewPaths = issuePaths),
                onDiscard: ref.read(settingsProvider.notifier).discardAll,
                onApply: _onApply,
              ),
            ],
          );
        },
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
    canManage: plugin.listed && ref.watch(pluginInstallationProvider),
  );

  List<Widget> _catalogSlivers(
    PluginCatalog catalog,
    double gutter, {
    Widget? notice,
  }) {
    if (catalog.status == 'disabled') {
      notice ??= const _Notice(
        'Public catalog fetching is disabled on this server.',
      );
    }
    if (catalog.status == 'unavailable') {
      notice ??= _Notice(
        'The public catalog is not available yet. '
        'The server may be fetching it or unable to reach the feed. Try again shortly.',
        onRetry: _reload,
      );
    }
    final modules = ref.watch(modulesStateProvider).value;
    final settings = ref.watch(settingsProvider);
    final plugins = pluginsWithInstalledModules(
      catalog.plugins,
      modules,
      settings.schema,
    );
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
      for (final plugin in plugins)
        plugin.id: PluginState.of(
          plugin,
          modules: modules,
          settings: settings,
          update: updates[plugin.id],
          inFlight: operations[plugin.id],
          failure: failures[plugin.id],
        ),
    };
    bool inTab(CatalogPlugin plugin) => switch (_tab) {
      PluginTab.sources => !plugin.isDevice,
      PluginTab.server => false,
      PluginTab.devices => plugin.isDevice,
    };
    final order = {for (final (i, plugin) in plugins.indexed) plugin.id: i};
    // Official and stable first, else as the catalog lists them.
    final listed = plugins.where(inTab).toList()
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
      if (listed.isEmpty && notice == null)
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
      if (notice != null) SliverToBoxAdapter(child: notice),
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

  Map<PluginTab, int> _updateCounts(PluginCatalog? catalog) {
    final counts = {for (final tab in PluginTab.values) tab: 0};
    final systemUpdate = ref.watch(serverUpdateProvider).value;
    if (systemUpdate != null &&
        systemUpdate.updateAvailable &&
        systemUpdate.upgradeSupported) {
      counts[PluginTab.server] = 1;
    }
    if (!ref.watch(pluginUpdateChecksProvider)) return counts;
    // Use the same installed-plugin state as the update sections, including
    // while Streamer is open and neither plugin list is being built.
    for (final plugin in catalog?.plugins ?? const <CatalogPlugin>[]) {
      if (ref.watch(pluginStateProvider(plugin)).update == null) continue;
      final tab = plugin.isDevice ? PluginTab.devices : PluginTab.sources;
      counts[tab] = counts[tab]! + 1;
    }
    return counts;
  }

  Widget _tabs(
    PluginTab tab,
    double gutter,
    Map<PluginTab, int> updateCounts,
  ) => PinnedHeaderSliver(
    child: ColoredBox(
      key: const ValueKey('catalog-tabs'),
      color: KalinkaColors.background,
      // All three destinations stay visible, including their update badges.
      // Longer labels receive proportionally more room and ellipsize as needed.
      child: Padding(
        padding: EdgeInsets.only(
          left: gutter - SectionTabButton.horizontalPadding,
          right: gutter,
        ),
        child: Row(
          children: [
            Expanded(
              child: Row(
                spacing: SectionTabButton.spacing,
                children: [
                  for (final (option, label) in [
                    (PluginTab.sources, 'Music sources'),
                    (PluginTab.devices, 'HiFi control'),
                    (PluginTab.server, 'Streamer'),
                  ])
                    Expanded(
                      flex: label.length,
                      child: SectionTabButton(
                        key: ValueKey('catalog-tab-${option.name}'),
                        label: label,
                        overflow: TextOverflow.ellipsis,
                        showBadge: updateCounts[option]! > 0,
                        semanticLabel: updateCounts[option]! > 0
                            ? option == PluginTab.server
                                  ? '$label, system update available'
                                  : '$label, ${updateCounts[option]} '
                                        '${updateCounts[option] == 1 ? 'update' : 'updates'} available'
                            : label,
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
            if (tab == PluginTab.server && !widget.showBack) ...[
              const SizedBox(width: 8),
              const ExpertModeToggle(),
            ],
          ],
        ),
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
        onDrivesAndShares: () => setState(() => _drivesOpen = true),
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
