import '../data_model/presentation_schema.dart' show ConfigIssue, OptionSpec;

/// Live option lists for fields the backend has values to offer, by field path.
///
/// Split out from [SettingsBinding] because the control dispatcher needs only
/// this much: it reads options, it never stages or reads values.
abstract interface class EnumOptionSource {
  /// Options the backend resolved for [path] this refresh, or null when the
  /// field's choices are static (the caller falls back to the schema's
  /// `enum_values`).
  List<OptionSpec>? optionsFor(String path);
}

/// Everything a schema-rendered settings page needs from the store behind it.
///
/// The schema widgets depend on this, not on a particular provider, so the
/// same rendering code draws the server's settings and a renderer's — two
/// stores with different transports, different save semantics, and no shared
/// state.
///
/// Implementations are immutable snapshots: a new binding instance means the
/// page below should rebuild.
abstract interface class SettingsBinding implements EnumOptionSource {
  /// Staged value if the user changed it, else the last-known stored value.
  dynamic effectiveValue(String path);

  /// True while [path] holds an edit that has not been saved.
  bool isStaged(String path);

  /// True when the store holds a credential at [path] that it never sends,
  /// and no edit replaces it: the field can show that one is set, never
  /// what it is.
  bool hasHiddenSecret(String path);

  /// Record an edit. Staging, not saving — the page's apply action commits.
  void stage(String path, dynamic value);

  /// What the backend says is wrong with the value staged at [path].
  /// Recomputed as the user types, so a row stops complaining once it is fixed.
  List<ConfigIssue> issuesFor(String path);

  /// Asks the backend for its suggestions again — a server on the network
  /// may answer after the page was read. What it finds arrives in a later
  /// binding; staged edits are left alone.
  Future<void> refreshOptions();
}
