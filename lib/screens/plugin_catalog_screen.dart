import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data_model/plugin_catalog.dart';
import '../providers/connection_settings_provider.dart';
import '../providers/connection_state_provider.dart';
import '../providers/plugin_catalog_provider.dart';
import '../providers/server_info_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/connection_banner.dart';
import '../widgets/plugin_catalog_entry.dart';
import '../widgets/slide_in_panel.dart';

/// Fixed chrome around one scrolling catalog; details never push a route.
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
  final _search = TextEditingController();
  final _scroll = ScrollController();
  final _headerKeys = <String, GlobalKey>{};
  String _type = 'input_module';
  String? _expandedId;

  @override
  void dispose() {
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _reload() {
    // Only reread the server cache, never an installation/update-check call.
    ref.invalidate(serverInfoProvider);
    ref.invalidate(pluginCatalogProvider);
  }

  void _toggle(String id) {
    // Keep the tapped row in view when a preceding long entry closes.
    final box =
        _headerKeys[id]?.currentContext?.findRenderObject() as RenderBox?;
    final before = box?.localToGlobal(Offset.zero).dy;
    setState(() => _expandedId = _expandedId == id ? null : id);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients || before == null) return;
      final afterBox =
          _headerKeys[id]?.currentContext?.findRenderObject() as RenderBox?;
      if (afterBox == null) return;
      final delta = afterBox.localToGlobal(Offset.zero).dy - before;
      _scroll.jumpTo(
        (_scroll.offset + delta).clamp(0.0, _scroll.position.maxScrollExtent),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(connectionSettingsProvider.select((s) => (s.host, s.port)), (
      _,
      next,
    ) {
      setState(() {
        _search.clear();
        _expandedId = null;
        _type = 'input_module';
        _headerKeys.clear();
      });
      if (_scroll.hasClients) _scroll.jumpTo(0);
    });
    final enabled = ref.watch(pluginCatalogEnabledProvider);
    final info = ref.watch(serverInfoProvider);
    final catalog = enabled ? ref.watch(pluginCatalogProvider) : null;
    final phone = MediaQuery.sizeOf(context).width < kKalinkaTabletBreakpoint;
    final gutter = phone ? 20.0 : 25.0;
    final name = ref.watch(connectionSettingsProvider.select((s) => s.name));
    final (connectionColor, connectionLabel) = switch (ref.watch(
      connectionStateProvider,
    )) {
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
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (_expandedId != null) _toggle(_expandedId!);
        },
      },
      child: SlideInPanel(
        onClose: widget.onClose,
        onCoverageChanged: widget.onCoverageChanged,
        handlesBack: widget.handlesBack,
        child: Material(
          color: KalinkaColors.background,
          child: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Builder(
                  builder: (context) => Padding(
                    key: const ValueKey('catalog-heading'),
                    padding: EdgeInsets.fromLTRB(6, 8, gutter, 12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Match the plain 42px Settings back control.
                        Semantics(
                          label: 'Back',
                          button: true,
                          child: GestureDetector(
                            key: const ValueKey('catalog-back'),
                            onTap: () => SlideInPanel.closeOf(context),
                            behavior: HitTestBehavior.opaque,
                            child: const SizedBox(
                              width: 42,
                              height: 42,
                              child: Icon(
                                Icons.arrow_back,
                                size: 22,
                                color: KalinkaColors.textPrimary,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      name.isEmpty || name == 'Unknown'
                                          ? 'Kalinka server'
                                          : name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: KalinkaTextStyles.trayRowLabel,
                                    ),
                                  ),
                                  Tooltip(
                                    message: connectionLabel,
                                    child: SizedBox(
                                      width: 24,
                                      height: 24,
                                      child: Center(
                                        child: DecoratedBox(
                                          key: const ValueKey(
                                            'catalog-connection-status',
                                          ),
                                          decoration: BoxDecoration(
                                            color: connectionColor,
                                            shape: BoxShape.circle,
                                          ),
                                          child: const SizedBox(
                                            width: 8,
                                            height: 8,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 2),
                              SizedBox(
                                width: double.infinity,
                                child: Wrap(
                                  alignment: WrapAlignment.spaceBetween,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  spacing: 12,
                                  runSpacing: 4,
                                  children: [
                                    Text(
                                      'Plugins',
                                      style: KalinkaFonts.display(
                                        fontSize: phone ? 29 : 35,
                                        fontWeight: FontWeight.w400,
                                        color: KalinkaColors.frost,
                                        height: 1.2,
                                      ),
                                    ),
                                    Text(
                                      'Read-only preview',
                                      textAlign: TextAlign.end,
                                      style: KalinkaTextStyles.trayRowSublabel,
                                    ),
                                  ],
                                ),
                              ),
                              if (!phone) ...[
                                const SizedBox(height: 6),
                                Text(
                                  'Music sources and controls for your hi-fi.',
                                  style: KalinkaTextStyles.trayRowSublabel,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const ConnectionBanner(),
                Container(
                  key: const ValueKey('catalog-browse-bar'),
                  margin: EdgeInsets.symmetric(horizontal: gutter),
                  decoration: const BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: KalinkaColors.borderDefault),
                    ),
                  ),
                  alignment: Alignment.centerLeft,
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 48),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: const BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: KalinkaColors.accent,
                          width: 2,
                        ),
                      ),
                    ),
                    child: Text(
                      'BROWSE',
                      style: KalinkaTextStyles.sectionHeaderMuted.copyWith(
                        letterSpacing: 1.0,
                        color: KalinkaColors.textPrimary,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: info.isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : !enabled
                      ? const _Notice(
                          'Plugin catalog preview is off or unavailable on this server. Enable it in Server settings → General, using expert mode.',
                        )
                      : catalog!.when(
                          skipLoadingOnRefresh: false,
                          data: (data) => _catalog(data, gutter),
                          loading: () =>
                              const Center(child: CircularProgressIndicator()),
                          error: (error, _) => _Notice(
                            error is PluginCatalogException
                                ? error.message
                                : 'Could not read the plugin catalog. Try reloading.',
                          ),
                        ),
                ),
                _CatalogFooter(
                  catalog: catalog?.value,
                  enabled: enabled,
                  loading: info.isLoading || (catalog?.isLoading ?? false),
                  onReload: _reload,
                  gutter: gutter,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _catalog(PluginCatalog catalog, double gutter) {
    if (catalog.status == 'disabled') {
      return const _Notice(
        'Public catalog fetching is disabled on this server.',
      );
    }
    if (catalog.status == 'unavailable') {
      return const _Notice(
        'The public catalog is not available yet. '
        'The server may be fetching it or unable to reach the feed. Try reloading shortly.',
      );
    }
    final filtered = catalog.plugins
        .where(
          (p) => (_type == 'all' || p.type == _type) && p.matches(_search.text),
        )
        .toList();
    return CustomScrollView(
      key: const ValueKey('catalog-scroll'),
      controller: _scroll,
      slivers: [
        SliverPadding(
          padding: EdgeInsets.symmetric(horizontal: gutter),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (catalog.status == 'stale')
                  Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: Text(
                      'Showing a cached catalog. The latest refresh failed or the data is old.',
                      style: KalinkaTextStyles.trayRowSublabel.copyWith(
                        color: KalinkaColors.statusPendingLight,
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final choice in const {
                      'all': 'All',
                      'input_module': 'Input sources',
                      'output_device': 'Device control',
                    }.entries)
                      ChoiceChip(
                        label: Text(choice.value),
                        selected: _type == choice.key,
                        avatar: choice.key == 'all'
                            ? null
                            : Icon(
                                choice.key == 'input_module'
                                    ? Icons.music_note_outlined
                                    : Icons.speaker_outlined,
                                size: 17,
                              ),
                        showCheckmark: false,
                        labelStyle: _type == choice.key
                            ? KalinkaTextStyles.filterPillActive.copyWith(
                                color: KalinkaColors.textPrimary,
                              )
                            : KalinkaTextStyles.filterPillInactive,
                        iconTheme: IconThemeData(
                          color: _type == choice.key
                              ? KalinkaColors.textPrimary
                              : KalinkaColors.textSecondary,
                        ),
                        backgroundColor: KalinkaColors.surfaceElevated,
                        selectedColor: KalinkaColors.accent,
                        color: WidgetStateProperty.resolveWith(
                          (states) => states.contains(WidgetState.selected)
                              ? KalinkaColors.accent
                              : KalinkaColors.surfaceElevated,
                        ),
                        side: BorderSide(
                          color: _type == choice.key
                              ? KalinkaColors.accent
                              : KalinkaColors.borderDefault,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 12,
                        ),
                        materialTapTargetSize: MaterialTapTargetSize.padded,
                        onSelected: (_) => setState(() {
                          _type = choice.key;
                          _expandedId = null;
                        }),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(switch (_type) {
                  'input_module' =>
                    'Music services and libraries, independent of your amplifier.',
                  'output_device' =>
                    'Optional controls for your amplifier or AVR. Check your model.',
                  _ => 'Music sources and optional controls for your hi-fi.',
                }, style: KalinkaTextStyles.trayRowSublabel),
                const SizedBox(height: 18),
                TextField(
                  key: const ValueKey('plugin-search'),
                  controller: _search,
                  style: KalinkaTextStyles.textFieldInput,
                  decoration: catalogSearchDecoration(
                    _type == 'output_device'
                        ? 'Search plugins, models or families'
                        : 'Search plugins',
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 9),
                Text(
                  'Tap a plugin to see details',
                  style: KalinkaTextStyles.trayRowSublabel.copyWith(
                    color: KalinkaColors.textMuted,
                  ),
                ),
                if (filtered.isEmpty)
                  Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Text(
                      'No matching plugins. Try another search or type filter.',
                      style: KalinkaTextStyles.trayRowSublabel,
                    ),
                  ),
              ],
            ),
          ),
        ),
        for (final type
            in _type == 'all'
                ? ['input_module', 'output_device']
                : [_type]) ...[
          if (_type == 'all' && filtered.any((p) => p.type == type))
            _heading(
              type == 'input_module' ? 'Input sources' : 'Device control',
              gutter,
            ),
          for (final section in [
            'Official',
            'Unofficial',
            'Experimental',
            'Deprecated',
          ])
            if (filtered.any(
              (p) => p.type == type && p.section == section,
            )) ...[
              _heading(
                '$section  ${filtered.where((p) => p.type == type && p.section == section).length}',
                gutter,
              ),
              for (final plugin in filtered.where(
                (p) => p.type == type && p.section == section,
              ))
                SliverPadding(
                  padding: EdgeInsets.symmetric(horizontal: gutter),
                  sliver: PluginCatalogEntry(
                    key: ValueKey('entry-${plugin.id}'),
                    plugin: plugin,
                    expanded: _expandedId == plugin.id,
                    headerKey: _headerKeys.putIfAbsent(
                      plugin.id,
                      GlobalKey.new,
                    ),
                    onToggle: () => _toggle(plugin.id),
                  ),
                ),
            ],
        ],
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }

  Widget _heading(String title, double gutter) => SliverToBoxAdapter(
    child: Padding(
      padding: EdgeInsets.fromLTRB(gutter, 22, gutter, 8),
      child: Text(
        title.toUpperCase(),
        style: KalinkaTextStyles.sectionHeaderMuted,
      ),
    ),
  );
}

class _CatalogFooter extends StatelessWidget {
  final PluginCatalog? catalog;
  final bool enabled, loading;
  final VoidCallback onReload;
  final double gutter;
  const _CatalogFooter({
    required this.catalog,
    required this.enabled,
    required this.loading,
    required this.onReload,
    required this.gutter,
  });
  String get _status {
    if (loading) return 'Reading catalog…';
    if (!enabled || catalog?.status == 'disabled') {
      return 'Catalog preview unavailable';
    }
    if (catalog?.status == 'stale') return 'Cached catalog · refresh failed';
    final checked = catalog?.checkedAt;
    if (checked == null) return 'Catalog not checked yet';
    final minutes = DateTime.now().difference(checked).inMinutes;
    if (minutes < 1) return 'Catalog checked just now';
    if (minutes < 60) return 'Catalog checked ${minutes}m ago';
    if (minutes < 1440) return 'Catalog checked ${minutes ~/ 60}h ago';
    return 'Catalog checked ${checked.toLocal().toString().split(' ').first}';
  }

  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('catalog-footer'),
    constraints: const BoxConstraints(minHeight: 76),
    padding: EdgeInsets.symmetric(horizontal: gutter, vertical: 8),
    decoration: const BoxDecoration(
      color: KalinkaColors.surfaceBase,
      border: Border(top: BorderSide(color: KalinkaColors.borderSubtle)),
    ),
    child: Row(
      children: [
        Expanded(
          child: Tooltip(
            message: catalog?.checkedAt?.toLocal().toString() ?? _status,
            child: Text(
              _status,
              style: KalinkaTextStyles.trayRowSublabel.copyWith(
                color: KalinkaColors.textMuted,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        TextButton.icon(
          onPressed: loading ? null : onReload,
          style: TextButton.styleFrom(
            foregroundColor: KalinkaColors.textSecondary,
            minimumSize: const Size(48, 48),
            padding: const EdgeInsets.symmetric(horizontal: 4),
            textStyle: KalinkaTextStyles.trayRowSublabel,
          ),
          icon: const Icon(Icons.sync, size: 15),
          label: const Text('Reload'),
        ),
      ],
    ),
  );
}

class _Notice extends StatelessWidget {
  final String message;
  const _Notice(this.message);
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.all(24),
    child: Text(message, style: KalinkaTextStyles.trayRowSublabel),
  );
}
