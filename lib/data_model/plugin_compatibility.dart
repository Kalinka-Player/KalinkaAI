/// Metadata-only checks reported by the server, never install authorization.
/// Do not reimplement version or platform matching on the client device.
class PluginCompatibility {
  final String status, channel;
  final String? latestAvailableVersion, latestCompatibleVersion;
  final PluginReleaseCompatibility? newerBlockedRelease;
  final List<PluginReleaseCompatibility> releases;

  PluginCompatibility.fromJson(Map<String, dynamic> json)
    : status = json['status'] as String? ?? 'unknown',
      channel = json['channel'] as String? ?? 'stable',
      latestAvailableVersion = json['latest_available_version'] as String?,
      latestCompatibleVersion = json['latest_compatible_version'] as String?,
      newerBlockedRelease = json['newer_blocked_release'] is Map
          ? PluginReleaseCompatibility.fromJson(
              Map<String, dynamic>.from(json['newer_blocked_release'] as Map),
            )
          : null,
      releases = List.unmodifiable(
        _objects(json['releases']).map(PluginReleaseCompatibility.fromJson),
      );

  PluginReleaseCompatibility? release(String version, String channel) {
    for (final release in releases) {
      if (release.version == version && release.channel == channel) {
        return release;
      }
    }
    return null;
  }
}

class PluginReleaseCompatibility {
  final String version, channel, status;
  final List<PluginCompatibilityReason> reasons;
  final List<PluginArtifactCompatibility> artifacts;

  PluginReleaseCompatibility.fromJson(Map<String, dynamic> json)
    : version = json['version'] as String? ?? '',
      channel = json['channel'] as String? ?? '',
      status = json['status'] as String? ?? 'unknown',
      reasons = List.unmodifiable(
        _objects(json['reasons']).map(PluginCompatibilityReason.fromJson),
      ),
      artifacts = List.unmodifiable(
        _objects(json['artifacts']).map(PluginArtifactCompatibility.fromJson),
      );

  /// Artifact restrictions matter only when no package matches; packages for
  /// other platforms must not turn a successful server check into a warning.
  Iterable<String> get explanations sync* {
    yield* reasons.map((reason) => reason.message);
    if (reasons.any((reason) => reason.code == 'no_compatible_artifact')) {
      for (final artifact in artifacts) {
        for (final reason in artifact.reasons) {
          yield '${artifact.filename}: ${reason.message}';
        }
      }
    }
  }
}

class PluginArtifactCompatibility {
  final String filename, status;
  final List<PluginCompatibilityReason> reasons;

  PluginArtifactCompatibility.fromJson(Map<String, dynamic> json)
    : filename = json['filename'] as String? ?? 'Package',
      status = json['status'] as String? ?? 'unknown',
      reasons = List.unmodifiable(
        _objects(json['reasons']).map(PluginCompatibilityReason.fromJson),
      );
}

class PluginCompatibilityReason {
  final String code;
  final Map<String, dynamic> _details;

  PluginCompatibilityReason.fromJson(Map<String, dynamic> json)
    : code = json['code'] as String? ?? 'unknown',
      _details = Map.unmodifiable(json);

  String _value(String key) {
    final value = _details[key];
    if (value is List) return value.whereType<String>().join(', ');
    return value is String && value.isNotEmpty ? value : 'unknown';
  }

  String get message {
    final renderer = _details['renderer_id'];
    final suffix = renderer is String ? ' (renderer $renderer)' : '';
    return '$_message$suffix';
  }

  String get _message {
    for (final component in ['server', 'sdk', 'python', 'renderer']) {
      final label = switch (component) {
        'sdk' => 'SDK',
        'python' => 'Python',
        'renderer' => 'Renderer',
        _ => 'Server',
      };
      if (code == 'incompatible_$component') {
        return '$label ${_value('installed')} does not meet ${_value('required')}.';
      }
      if (code == '${component}_version_unknown') {
        return '$label version is unknown; requires ${_value('required')}.';
      }
    }
    return switch (code) {
      'release_withdrawn' => 'This release has been withdrawn.',
      'channel_not_selected' => 'This release is outside the selected channel.',
      'release_not_yet_published' => 'This release is not yet published.',
      'platform_unknown' =>
        'Server platform is unknown; requires ${_value('required')}.',
      'architecture_unknown' =>
        'Server architecture is unknown; requires ${_value('required')}.',
      'unsupported_platform' =>
        'Server platform ${_value('actual')} is not supported; requires ${_value('required')}.',
      'unsupported_architecture' =>
        'Server architecture ${_value('actual')} is not supported; requires ${_value('required')}.',
      'missing_capability' =>
        'Missing server capability: ${_value('capability')}.',
      'renderer_unavailable' => 'Renderer is not connected.',
      'renderer_protocol_incompatible' => 'Renderer protocol is incompatible.',
      'no_compatible_artifact' => 'No package matches this server.',
      'unsupported_package_format' =>
        'Package format ${_value('format')} is not supported by this server.',
      'invalid_package_metadata' => 'Package metadata is inconsistent.',
      'distribution_unknown' => 'Server distribution or version is unknown.',
      'unsupported_distribution' =>
        'Server distribution ${_value('id')} ${_value('version')} is not supported.',
      _ => 'The server reported a restriction the app cannot describe ($code).',
    };
  }
}

Iterable<Map<String, dynamic>> _objects(Object? value) =>
    (value as List? ?? const []).map(
      (item) => (item as Map).cast<String, dynamic>(),
    );
