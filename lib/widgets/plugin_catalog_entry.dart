import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data_model/plugin_catalog.dart';
import '../data_model/plugin_compatibility.dart';
import '../theme/app_theme.dart';

// Share settings typography; the catalog owns layout, not a separate type scale.
InputDecoration catalogSearchDecoration(String hint) => InputDecoration(
  hintText: hint,
  hintStyle: KalinkaTextStyles.searchPlaceholder.copyWith(
    fontSize: KalinkaTypography.baseSize + 2,
    color: KalinkaColors.textSecondary,
  ),
  prefixIcon: const Icon(
    Icons.search,
    size: 20,
    color: KalinkaColors.textMuted,
  ),
  isDense: true,
  contentPadding: const EdgeInsets.symmetric(horizontal: 13, vertical: 13),
  filled: true,
  fillColor: KalinkaColors.surfaceInput,
  enabledBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(10),
    borderSide: const BorderSide(color: KalinkaColors.borderDefault),
  ),
  focusedBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(10),
    borderSide: const BorderSide(color: KalinkaColors.accent),
  ),
);

/// Only the expanded row gains a bordered surface. The sliver group confines
/// its pinned header to this entry; details share the catalog's single scroll.
class PluginCatalogEntry extends StatelessWidget {
  final CatalogPlugin plugin;
  final bool expanded;
  final VoidCallback onToggle;
  const PluginCatalogEntry({
    super.key,
    required this.plugin,
    required this.expanded,
    required this.onToggle,
  });
  @override
  Widget build(BuildContext context) {
    final header = _PluginHeader(
      plugin: plugin,
      expanded: expanded,
      onToggle: onToggle,
    );
    if (!expanded) return SliverToBoxAdapter(child: header);
    return SliverPadding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      sliver: DecoratedSliver(
        decoration: BoxDecoration(
          color: KalinkaColors.surfaceRaised,
          border: Border.all(color: KalinkaColors.borderDefault),
          borderRadius: BorderRadius.circular(14),
        ),
        sliver: SliverMainAxisGroup(
          slivers: [
            PinnedHeaderSliver(child: header),
            SliverToBoxAdapter(
              child: _PluginDetails(
                key: ValueKey('plugin-details-${plugin.id}'),
                plugin: plugin,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PluginHeader extends StatelessWidget {
  final CatalogPlugin plugin;
  final bool expanded;
  final VoidCallback onToggle;
  const _PluginHeader({
    required this.plugin,
    required this.expanded,
    required this.onToggle,
  });
  @override
  Widget build(BuildContext context) {
    final state = [
      if (plugin.delivery == 'bundle') 'Included with Kalinka Player',
      if (plugin.maturity != 'stable')
        '${plugin.tierLabel} · ${plugin.maturityLabel}',
      if (plugin.isDevice) 'Check your model',
    ].join(' · ');
    final icon = switch (plugin.id) {
      'localfiles' => Icons.library_music_outlined,
      'qobuz' || 'spotify' => Icons.headphones_outlined,
      'upnp' => Icons.cast,
      _ => plugin.isDevice ? Icons.speaker_outlined : Icons.music_note_outlined,
    };
    return Semantics(
      key: ValueKey('plugin-${plugin.id}'),
      button: true,
      expanded: expanded,
      label:
          '${plugin.name}. ${plugin.description}${state.isEmpty ? '' : '. $state'}',
      onTap: onToggle,
      child: Material(
        color: expanded
            ? KalinkaColors.surfaceRaised
            : KalinkaColors.background,
        shape: RoundedRectangleBorder(
          borderRadius: expanded
              ? const BorderRadius.vertical(top: Radius.circular(14))
              : BorderRadius.zero,
        ),
        child: InkWell(
          onTap: onToggle,
          excludeFromSemantics: true,
          borderRadius: BorderRadius.circular(13),
          child: ExcludeSemantics(
            child: Container(
              constraints: const BoxConstraints(minHeight: 88),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
              decoration: const BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: KalinkaColors.borderSubtle),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: KalinkaColors.surfaceElevated,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: KalinkaColors.borderSubtle),
                    ),
                    child: Icon(icon, size: 23, color: KalinkaColors.gold),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          plugin.name,
                          style: KalinkaTextStyles.trayRowLabel,
                        ),
                        const SizedBox(height: 3),
                        Text(
                          plugin.description,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: KalinkaTextStyles.trayRowSublabel,
                        ),
                        if (state.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(state, style: KalinkaTextStyles.trayRowSublabel),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  AnimatedRotation(
                    turns: expanded ? .5 : 0,
                    duration: MediaQuery.disableAnimationsOf(context)
                        ? Duration.zero
                        : const Duration(milliseconds: 180),
                    child: const Icon(
                      Icons.keyboard_arrow_down,
                      color: KalinkaColors.textSecondary,
                      size: 20,
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

class _PluginDetails extends StatelessWidget {
  final CatalogPlugin plugin;
  const _PluginDetails({super.key, required this.plugin});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (plugin.isDevice) ...[
          Text('DEVICE CONTROL', style: KalinkaTextStyles.sectionHeaderMuted),
          const SizedBox(height: 8),
        ],
        Text(plugin.description, style: KalinkaTextStyles.trayRowSublabel),
        const SizedBox(height: 9),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              plugin.isDevice
                  ? Icons.speaker_outlined
                  : Icons.music_note_outlined,
              size: 14,
              color: KalinkaColors.textSecondary,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                plugin.isDevice
                    ? 'Amplifier and AVR controls · Does not add a music source.'
                    : 'Adds a music source · No amplifier-specific support needed',
                style: KalinkaTextStyles.trayRowSublabel,
              ),
            ),
          ],
        ),
        if (plugin.isDevice) ...[
          const SizedBox(height: 14),
          Text(
            'Controls and limitations',
            style: KalinkaTextStyles.trayRowLabel,
          ),
          for (final note in plugin.deviceNotes)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(note, style: KalinkaTextStyles.trayRowSublabel),
            ),
          _ModelCoverage(plugin: plugin),
        ],
        _Facts(
          facts: [
            ('Created by', plugin.creator),
            (
              'Publisher and maturity',
              '${plugin.tierLabel} · ${plugin.maturityLabel}',
            ),
            ('License', plugin.license),
            (
              'Delivery',
              plugin.delivery == 'bundle'
                  ? 'Included with Kalinka Player'
                  : 'Independent package',
            ),
          ],
        ),
        _CompatibilityNotice(plugin: plugin),
        for (final release in plugin.releases) ...[
          _Facts(
            facts: [
              (
                'Release',
                '${release.version} · ${release.channel}${release.withdrawn ? ' · Withdrawn' : ''}',
              ),
              (
                'Server platforms',
                release.platforms
                    .map((p) => p == 'all' ? 'Cross-platform (all)' : p)
                    .join(', '),
              ),
              (
                'Architectures',
                release.architectures
                    .map(
                      (a) => a == 'all' ? 'Architecture-independent (all)' : a,
                    )
                    .join(', '),
              ),
            ],
          ),
          _RequirementsNotice(
            warning:
                plugin.compatibility
                    ?.release(release.version, release.channel)
                    ?.status !=
                'metadata_compatible',
            text: [
              [
                for (final version in release.versions.entries)
                  '${switch (version.key) {
                    'sdk' => 'SDK',
                    'server' => 'Server',
                    'python' => 'Python',
                    _ => 'Renderer',
                  }} ${version.value}',
                if (release.capabilities.isNotEmpty)
                  'Required capabilities: ${release.capabilities.join(', ')}',
              ].join(' · '),
              _releaseCheck(
                plugin.compatibility?.release(release.version, release.channel),
              ),
            ].where((text) => text.isNotEmpty).join('\n\n'),
          ),
          if (release.withdrawn)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                'Withdrawn: ${release.withdrawalReason ?? 'No reason supplied'}',
                style: KalinkaTextStyles.trayRowSublabel.copyWith(
                  color: KalinkaColors.statusPendingLight,
                ),
              ),
            ),
          if (release.packages.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              'Packages and platforms',
              style: KalinkaTextStyles.trayRowLabel,
            ),
            for (final package in release.packages)
              Padding(
                padding: const EdgeInsets.only(top: 5),
                child: Text(package, style: KalinkaTextStyles.trayRowSublabel),
              ),
          ],
          if (release.notes.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text('Requirements', style: KalinkaTextStyles.trayRowLabel),
            for (final note in release.notes)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(note, style: KalinkaTextStyles.trayRowSublabel),
              ),
          ],
          if (release.releaseNotes != null)
            Align(
              alignment: Alignment.centerLeft,
              child: _ExternalLink(
                label: 'Release notes for ${release.version}',
                uri: release.releaseNotes!,
              ),
            ),
        ],
        const SizedBox(height: 9),
        if (plugin.source != null)
          Align(
            alignment: Alignment.centerLeft,
            child: _ExternalLink(
              label: 'Source & license',
              uri: plugin.source!,
            ),
          ),
        Text(
          'Read-only preview · Installation and updates are not available. Catalog signatures are not verified. Package dependencies and actual device support have not been checked.',
          style: KalinkaTextStyles.trayRowSublabel,
        ),
      ],
    ),
  );
}

String _releaseCheck(PluginReleaseCompatibility? result) => [
  switch (result?.status) {
    'metadata_compatible' => 'Server check: declared requirements match.',
    'blocked' => 'Server check: requirements not met.',
    _ => 'Server check: result unavailable.',
  },
  if (result != null)
    ...result.explanations.map((explanation) => '• $explanation'),
].join('\n');

class _CompatibilityNotice extends StatelessWidget {
  final CatalogPlugin plugin;
  const _CompatibilityNotice({required this.plugin});

  @override
  Widget build(BuildContext context) {
    final result = plugin.compatibility;
    // Bundled delivery describes how requirements are managed, not a locally
    // inferred compatibility or installed-plugin identity check.
    final status =
        result?.status ??
        (plugin.delivery == 'bundle'
            ? 'bundle_managed'
            : plugin.releases.isEmpty
            ? 'no_releases'
            : 'unknown');
    final (title, text) = switch (status) {
      'bundle_managed' => (
        'Managed with Kalinka Player',
        'Requirements and updates follow the server bundle. This plugin is not checked as a separate package.',
      ),
      'no_releases' => (
        'No release available',
        'No independent catalog release has been published to check.',
      ),
      'metadata_compatible' => (
        'Declared requirements match',
        result?.latestCompatibleVersion != null
            ? 'The server reports a requirements match for version ${result!.latestCompatibleVersion} (${result.channel} channel).'
            : 'The server reports a match for the declared requirements.',
      ),
      'blocked' => (
        'Requirements not met',
        'No release in the ${result!.channel} channel matches all declared requirements. See the release checks below.',
      ),
      _ => (
        'Compatibility unavailable',
        'This server has not supplied a compatibility result the app can display.',
      ),
    };
    return _RequirementsNotice(
      title: title,
      warning: !const [
        'bundle_managed',
        'no_releases',
        'metadata_compatible',
      ].contains(status),
      text: [
        text,
        if (status == 'metadata_compatible' &&
            result?.newerBlockedRelease != null)
          'Newer version ${result!.newerBlockedRelease!.version} does not meet the requirements. See its release check below.',
      ].join('\n\n'),
    );
  }
}

class _Facts extends StatelessWidget {
  final List<(String, String)> facts;
  const _Facts({required this.facts});
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final columns =
          constraints.maxWidth >= 280 &&
              MediaQuery.textScalerOf(
                    context,
                  ).scale(KalinkaTextStyles.trayRowSublabel.fontSize!) <
                  KalinkaTextStyles.trayRowSublabel.fontSize! * 1.5
          ? 2
          : 1;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 17),
        child: Wrap(
          spacing: 20,
          runSpacing: 13,
          children: [
            for (final (label, value) in facts)
              SizedBox(
                width: (constraints.maxWidth - 20 * (columns - 1)) / columns,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: KalinkaTextStyles.trayRowSublabel),
                    const SizedBox(height: 2),
                    Text(
                      value,
                      style: KalinkaTextStyles.trayRowSublabel.copyWith(
                        color: KalinkaColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      );
    },
  );
}

class _RequirementsNotice extends StatelessWidget {
  final String title, text;
  final bool warning;
  const _RequirementsNotice({
    this.title = 'Declared requirements',
    required this.text,
    this.warning = true,
  });
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: warning
          ? KalinkaColors.statusPendingSurface
          : KalinkaColors.surfaceBase,
      border: Border.all(
        color: warning
            ? KalinkaColors.statusPending.withValues(alpha: .2)
            : KalinkaColors.borderDefault,
      ),
      borderRadius: BorderRadius.circular(9),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.info_outline,
          size: 18,
          color: warning
              ? KalinkaColors.statusPendingLight
              : KalinkaColors.textSecondary,
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: KalinkaTextStyles.trayRowLabel.copyWith(
                  color: warning
                      ? KalinkaColors.statusPendingLight
                      : KalinkaColors.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(text, style: KalinkaTextStyles.trayRowSublabel),
            ],
          ),
        ),
      ],
    ),
  );
}

class _ModelCoverage extends StatefulWidget {
  final CatalogPlugin plugin;
  const _ModelCoverage({required this.plugin});
  @override
  State<_ModelCoverage> createState() => _ModelCoverageState();
}

class _ModelCoverageState extends State<_ModelCoverage> {
  String _query = '';
  @override
  Widget build(BuildContext context) {
    final models = widget.plugin.models
        .where((s) => s.toLowerCase().contains(_query.toLowerCase()))
        .toList();
    final families = widget.plugin.families
        .where((s) => s.toLowerCase().contains(_query.toLowerCase()))
        .toList();
    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: KalinkaColors.surfaceBase,
        border: Border.all(color: KalinkaColors.borderDefault),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Will it work with my device?',
            style: KalinkaTextStyles.trayRowLabel,
          ),
          const SizedBox(height: 10),
          TextField(
            key: ValueKey('model-search-${widget.plugin.id}'),
            style: KalinkaTextStyles.textFieldInput,
            decoration: catalogSearchDecoration('Search a model or family'),
            onChanged: (value) => setState(() => _query = value),
          ),
          const SizedBox(height: 10),
          Text(
            _query.isNotEmpty && models.isEmpty && families.isEmpty
                ? 'No catalog match · Not verified'
                : 'Check your exact model',
            style: KalinkaTextStyles.trayRowLabel.copyWith(
              color: KalinkaColors.statusPendingLight,
            ),
          ),
          const SizedBox(height: 8),
          Text('Supported models', style: KalinkaTextStyles.trayRowSublabel),
          Text(
            models.isEmpty
                ? (widget.plugin.models.isEmpty
                      ? 'No exact models listed; see family coverage.'
                      : 'No matching model listed.')
                : models.join(', '),
            style: KalinkaTextStyles.trayRowSublabel,
          ),
          const SizedBox(height: 8),
          Text('Supported families', style: KalinkaTextStyles.trayRowSublabel),
          Text(
            families.isEmpty
                ? (widget.plugin.families.isEmpty
                      ? 'No family-wide claim.'
                      : 'No matching family listed.')
                : families.join(', '),
            style: KalinkaTextStyles.trayRowSublabel,
          ),
          const SizedBox(height: 10),
          Text(
            'Catalog declarations only · No connected-device check in this preview.',
            style: KalinkaTextStyles.trayRowSublabel,
          ),
        ],
      ),
    );
  }
}

class _ExternalLink extends StatelessWidget {
  final String label;
  final Uri uri;
  const _ExternalLink({required this.label, required this.uri});
  @override
  Widget build(BuildContext context) => TextButton(
    style: TextButton.styleFrom(
      foregroundColor: KalinkaColors.textSecondary,
      minimumSize: const Size(48, 48),
      padding: EdgeInsets.zero,
      textStyle: KalinkaTextStyles.trayRowSublabel,
    ),
    onPressed: () async {
      try {
        if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
          throw StateError('No browser');
        }
      } catch (_) {
        if (context.mounted) {
          ScaffoldMessenger.maybeOf(context)?.showSnackBar(
            const SnackBar(content: Text('Could not open this link.')),
          );
        }
      }
    },
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(child: Text(label)),
        const SizedBox(width: 8),
        const Icon(Icons.open_in_new, size: 14),
      ],
    ),
  );
}
