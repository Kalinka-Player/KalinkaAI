import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
import '../widgets/plugin_catalog_header.dart';
import '../widgets/slide_in_panel.dart';

/// A collapsing header and inline details share one scrolling catalog.
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
  final _headingKey = GlobalKey();
  final _browseKey = GlobalKey();
  final _entryKeys = <String, GlobalKey>{};
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

  double get _pinnedExtent =>
      [_headingKey, _browseKey].fold(0.0, (extent, key) {
        final sliver = key.currentContext?.findRenderObject();
        return extent +
            (sliver is RenderSliver
                ? sliver.geometry?.maxScrollObstructionExtent ?? 0
                : 0);
      });

  void _toggle(String id) {
    final key = _entryKeys[id];
    final entry = key?.currentContext?.findRenderObject();
    final opening = _expandedId != id;
    // These keyed slivers are direct viewport children. Their scroll extent
    // locates the entry's real start even when its header is pinned elsewhere.
    final before = entry is RenderSliver && _scroll.hasClients
        ? (entry.constraints.precedingScrollExtent -
                  _scroll.offset -
                  _pinnedExtent)
              .clamp(0.0, _scroll.position.viewportDimension)
        : 0.0;
    final expandedId = opening ? id : null;
    setState(() => _expandedId = expandedId);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients || _expandedId != expandedId) return;
      final entry = key?.currentContext?.findRenderObject();
      if (entry is! RenderSliver || !entry.attached) return;
      // Reveal the beginning of newly opened details after the old entry has
      // collapsed. On collapse, keep the row at its previous visible position.
      final offset =
          entry.constraints.precedingScrollExtent -
          _pinnedExtent -
          (opening ? 0.0 : before);
      _scroll.jumpTo(
        offset.clamp(
          _scroll.position.minScrollExtent,
          _scroll.position.maxScrollExtent,
        ),
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
        _entryKeys.clear();
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
            child: CustomScrollView(
              key: const ValueKey('catalog-scroll'),
              controller: _scroll,
              slivers: [
                PluginCatalogHeader(
                  key: _headingKey,
                  serverName: name.isEmpty || name == 'Unknown'
                      ? 'Kalinka Player server'
                      : name,
                  connectionLabel: connectionLabel,
                  connectionColor: connectionColor,
                  phone: phone,
                  gutter: gutter,
                ),
                PinnedHeaderSliver(
                  key: _browseKey,
                  child: ColoredBox(
                    color: KalinkaColors.background,
                    child: Column(
                      children: [
                        const ConnectionBanner(),
                        Container(
                          key: const ValueKey('catalog-browse-bar'),
                          margin: EdgeInsets.symmetric(horizontal: gutter),
                          decoration: const BoxDecoration(
                            border: Border(
                              bottom: BorderSide(
                                color: KalinkaColors.borderDefault,
                              ),
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                constraints: const BoxConstraints(
                                  minHeight: 48,
                                ),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
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
                                  style: KalinkaTextStyles.sectionHeaderMuted
                                      .copyWith(
                                        letterSpacing: 1.0,
                                        color: KalinkaColors.textPrimary,
                                      ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Align(
                                  alignment: Alignment.centerRight,
                                  child: Tooltip(
                                    message: 'Reload catalog',
                                    child: TextButton.icon(
                                      key: const ValueKey('catalog-reload'),
                                      onPressed:
                                          info.isLoading ||
                                              (catalog?.isLoading ?? false)
                                          ? null
                                          : _reload,
                                      style: TextButton.styleFrom(
                                        foregroundColor:
                                            KalinkaColors.textSecondary,
                                        minimumSize: const Size(48, 48),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 4,
                                        ),
                                        textStyle:
                                            KalinkaTextStyles.trayRowSublabel,
                                      ),
                                      icon: const Icon(Icons.sync, size: 15),
                                      label: const Text(
                                        'Reload',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (info.isLoading)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (!enabled)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: _Notice(
                      'Plugin catalog preview is off or unavailable on this server. Enable it in Server settings → General, using expert mode.',
                    ),
                  )
                else
                  ...catalog!.when<List<Widget>>(
                    skipLoadingOnRefresh: false,
                    data: (data) => _catalogSlivers(data, gutter),
                    loading: () => const [
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: Center(child: CircularProgressIndicator()),
                      ),
                    ],
                    error: (error, _) => [
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: _Notice(
                          error is PluginCatalogException
                              ? error.message
                              : 'Could not read the plugin catalog. Try reloading.',
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

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
      return const [
        SliverFillRemaining(
          hasScrollBody: false,
          child: _Notice(
            'The public catalog is not available yet. '
            'The server may be fetching it or unable to reach the feed. Try reloading shortly.',
          ),
        ),
      ];
    }
    final filtered = catalog.plugins
        .where(
          (p) => (_type == 'all' || p.type == _type) && p.matches(_search.text),
        )
        .toList();
    return [
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
                decoration:
                    catalogSearchDecoration(
                      _type == 'output_device'
                          ? 'Search plugins, models or families'
                          : 'Search plugins',
                    ).copyWith(
                      suffixIcon: _search.text.isEmpty
                          ? null
                          : IconButton(
                              key: const ValueKey('plugin-search-clear'),
                              tooltip: 'Clear search',
                              onPressed: () => setState(_search.clear),
                              constraints: const BoxConstraints(
                                minWidth: 48,
                                minHeight: 48,
                              ),
                              color: KalinkaColors.textSecondary,
                              icon: const Icon(Icons.close_rounded, size: 20),
                            ),
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
          in _type == 'all' ? ['input_module', 'output_device'] : [_type]) ...[
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
          if (filtered.any((p) => p.type == type && p.section == section)) ...[
            _heading(
              '$section  ${filtered.where((p) => p.type == type && p.section == section).length}',
              gutter,
            ),
            for (final plugin in filtered.where(
              (p) => p.type == type && p.section == section,
            ))
              SliverPadding(
                key: _entryKeys.putIfAbsent(plugin.id, GlobalKey.new),
                padding: EdgeInsets.symmetric(horizontal: gutter),
                sliver: PluginCatalogEntry(
                  key: ValueKey('entry-${plugin.id}'),
                  plugin: plugin,
                  expanded: _expandedId == plugin.id,
                  onToggle: () => _toggle(plugin.id),
                ),
              ),
          ],
      ],
      const SliverToBoxAdapter(child: SizedBox(height: 24)),
    ];
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

class _Notice extends StatelessWidget {
  final String message;
  const _Notice(this.message);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(24),
    child: Text(message, style: KalinkaTextStyles.trayRowSublabel),
  );
}
