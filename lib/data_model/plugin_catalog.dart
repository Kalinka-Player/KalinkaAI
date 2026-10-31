import 'plugin_compatibility.dart';
import 'module_icons.dart';

/// Display metadata only. No identity, compatibility or install decisions are
/// inferred from names, version strings or a plugin's official/unofficial tier.
class PluginCatalog {
  final String status;
  final String? error;
  final DateTime? checkedAt;
  final List<CatalogPlugin> plugins;

  const PluginCatalog({
    required this.status,
    this.error,
    this.checkedAt,
    this.plugins = const [],
  });

  factory PluginCatalog.fromJson(Map<String, dynamic> json) {
    final status = json['status'];
    if (!const [
      'available',
      'stale',
      'unavailable',
      'disabled',
    ].contains(status)) {
      throw const FormatException('Unsupported plugin catalog response');
    }
    return PluginCatalog(
      status: status as String,
      error: json['error'] as String?,
      checkedAt: DateTime.tryParse(
        json['last_successful_check'] as String? ?? '',
      ),
      plugins: List.unmodifiable(
        _maps(json['plugins']).map(CatalogPlugin.fromJson),
      ),
    );
  }
}

class CatalogPlugin {
  final String id, name, description, type, tier, maturity, delivery;
  final String creator, license, distribution;

  /// One short line for its row, where the catalog has one. `{player}` stands
  /// for the streamer it runs on.
  final String? summary;
  final ModuleIcons? icons;

  /// What it lets people do, by name: `browse`, `direct_playback`.
  final List<String> provides;
  final Uri? source;
  final List<String> models, families, deviceNotes;
  final List<CatalogPluginRelease> releases;
  final PluginCompatibility? compatibility;

  const CatalogPlugin({
    required this.id,
    required this.name,
    required this.description,
    required this.type,
    required this.tier,
    required this.maturity,
    required this.delivery,
    required this.creator,
    required this.license,
    required this.distribution,
    this.summary,
    this.icons,
    this.provides = const [],
    this.source,
    this.models = const [],
    this.families = const [],
    this.deviceNotes = const [],
    this.releases = const [],
    this.compatibility,
  });

  factory CatalogPlugin.fromJson(Map<String, dynamic> json) {
    final support = _map(json['device_support']);
    return CatalogPlugin(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String,
      type: json['type'] as String,
      tier: json['tier'] as String,
      maturity: json['maturity'] as String,
      delivery: json['delivery'] as String,
      creator: _map(json['creator'])['name'] as String? ?? 'Not supplied',
      license: json['license'] as String? ?? 'Not supplied',
      distribution: json['distribution'] as String? ?? '',
      summary: json['summary'] as String?,
      icons: ModuleIcons.tryParse(json['icons']),
      provides: _strings(json['provides']),
      source: _publicLink(_map(json['source'])['repository']),
      models: _strings(support['models']),
      families: _strings(support['families']),
      deviceNotes: _strings(support['notes']),
      releases: List.unmodifiable(
        _maps(json['releases']).map(CatalogPluginRelease.fromJson),
      ),
      compatibility: json['compatibility'] is Map
          ? PluginCompatibility.fromJson(_map(json['compatibility']))
          : null,
    );
  }

  bool get isDevice => type == 'output_device';

  /// The `kind` its module carries in `/server/modules` and the settings schema.
  String get moduleKind => isDevice ? 'device' : 'input_module';

  /// Part of the server install rather than a package of its own.
  bool get bundled => delivery == 'bundle';
  bool get unofficial => tier != 'official';

  /// Official and stable first, then unofficial, experimental, deprecated.
  int get rank => switch (maturity) {
    'deprecated' => 3,
    'experimental' => 2,
    _ => unofficial ? 1 : 0,
  };

  String get tierLabel => unofficial ? 'Unofficial' : 'Official';
  String get maturityLabel => switch (maturity) {
    'experimental' => 'Experimental',
    'deprecated' => 'Deprecated',
    _ => 'Stable',
  };

  /// What its row says it does, naming the [player] it runs on.
  String blurb(String player) {
    final short = summary?.trim();
    if (short != null && short.isNotEmpty) {
      return short.replaceAll('{player}', player);
    }
    // Older catalogs only supply the full description. Keep its opening sentence.
    final text = description.trim();
    final sentence = RegExp(r'[.!?](?:\s|$)').firstMatch(text);
    return sentence == null ? text : text.substring(0, sentence.start + 1);
  }

  /// What it lets people do, in the words its row uses.
  List<String> get uses => [
    if (provides.contains('browse')) 'Browse in Kalinka',
    if (provides.contains('direct_playback')) 'Play from another app',
  ];
}

/// A newer release the server offers for a plugin it has installed. Only the
/// server decides this; the app never compares version strings itself.
class PluginUpdate {
  final String pluginId, version;
  final String? installedVersion;

  const PluginUpdate({
    required this.pluginId,
    required this.version,
    this.installedVersion,
  });

  factory PluginUpdate.fromJson(Map<String, dynamic> json) => PluginUpdate(
    pluginId: json['plugin_id'] as String,
    version: json['version'] as String,
    installedVersion: json['installed_version'] as String?,
  );
}

class CatalogPluginRelease {
  final String version, channel;
  final Uri? releaseNotes;
  final bool withdrawn;
  final String? withdrawalReason;
  final Map<String, String> versions;
  final List<String> platforms, architectures, capabilities, notes, packages;

  const CatalogPluginRelease({
    required this.version,
    required this.channel,
    this.releaseNotes,
    this.withdrawn = false,
    this.withdrawalReason,
    this.versions = const {},
    this.platforms = const [],
    this.architectures = const [],
    this.capabilities = const [],
    this.notes = const [],
    this.packages = const [],
  });

  factory CatalogPluginRelease.fromJson(Map<String, dynamic> json) {
    final requires = _map(json['requires']);
    final packages = <String>[];
    for (final artifact in _maps(json['artifacts'])) {
      final targets = _maps(artifact['targets'])
          .map(
            (target) =>
                '${target['id']} ${_strings(target['versions']).join(', ')}',
          )
          .join('; ');
      packages.add(
        [
          (artifact['format'] as String? ?? '').toUpperCase(),
          artifact['platform'] as String? ?? '',
          _strings(artifact['architectures']).join(', '),
          if (targets.isNotEmpty) targets,
        ].where((value) => value.isNotEmpty).join(' · '),
      );
    }
    return CatalogPluginRelease(
      version: json['version'] as String,
      channel: json['channel'] as String? ?? 'stable',
      releaseNotes: _publicLink(json['release_notes']),
      withdrawn: json['withdrawn'] == true,
      withdrawalReason: json['withdrawal_reason'] as String?,
      versions: Map.unmodifiable({
        for (final name in ['server', 'sdk', 'python', 'renderer'])
          if (requires[name] is String) name: requires[name] as String,
      }),
      platforms: _strings(requires['platforms']),
      architectures: _strings(requires['architectures']),
      capabilities: _strings(requires['capabilities']),
      notes: _strings(requires['notes']),
      packages: List.unmodifiable(packages),
    );
  }
}

Map<String, dynamic> _map(Object? value) =>
    value is Map ? value.cast<String, dynamic>() : const {};
Iterable<Map<String, dynamic>> _maps(Object? value) =>
    (value as List? ?? const []).map(
      (item) => (item as Map).cast<String, dynamic>(),
    );
List<String> _strings(Object? value) =>
    List.unmodifiable((value as List? ?? const []).cast<String>());
Uri? _publicLink(Object? value) {
  final uri = value is String ? Uri.tryParse(value) : null;
  return uri != null &&
          uri.scheme == 'https' &&
          uri.host.isNotEmpty &&
          uri.userInfo.isEmpty
      ? uri
      : null;
}
