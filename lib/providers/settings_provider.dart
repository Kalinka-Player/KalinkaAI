import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logger/logger.dart' show Logger;
import '../data_model/presentation_schema.dart';
import 'kalinka_player_api_provider.dart';
import 'settings_binding.dart';

/// How long an edit settles before the server is asked what it thinks of it.
const _validationDelay = Duration(milliseconds: 300);

final _logger = Logger();

/// Settings state keyed entirely by flat dotted paths (`base_config.server.port`,
/// `input_modules.qobuz.email`, …). The backend owns the presentation schema —
/// we never regroup, relabel, or re-derive anything on the client.
class SettingsState {
  final PresentationSchema? schema;
  final String? schemaVersion;
  final Map<String, dynamic> values; // Path → server value
  // Credentials the server holds a value for. It never sends the value, so
  // these paths are absent from [values].
  final Set<String> secretsSet;
  // Per-path option lists for enum widgets whose choices are resolved
  // live by the backend (ALSA devices today). When an entry exists for
  // a field's path, the renderer uses it in preference to the schema's
  // static enum_values. Refreshed on every loadConfig — hot-plug shows
  // up on the next refresh.
  final Map<String, List<OptionSpec>> enumOptions;
  final Map<String, dynamic> stagedChanges;
  // What the server says is wrong with the staged values, by field path.
  // Replaced wholesale on every check — a fixed row just stops appearing.
  final Map<String, List<ConfigIssue>> issues;
  final bool isLoading;
  final String? error;

  const SettingsState({
    this.schema,
    this.schemaVersion,
    this.values = const {},
    this.secretsSet = const {},
    this.enumOptions = const {},
    this.stagedChanges = const {},
    this.issues = const {},
    this.isLoading = false,
    this.error,
  });

  int get pendingCount => stagedChanges.length;
  bool get hasPendingChanges => stagedChanges.isNotEmpty;

  /// Staged value if present, else the last-known server value.
  dynamic getEffective(String path) {
    if (stagedChanges.containsKey(path)) return stagedChanges[path];
    return values[path];
  }

  bool isStaged(String path) => stagedChanges.containsKey(path);

  bool hasHiddenSecret(String path) =>
      !stagedChanges.containsKey(path) && secretsSet.contains(path);

  /// Live option list for [path] if the backend resolved one this
  /// refresh, else null (caller should fall back to the schema's
  /// static enum_values).
  List<OptionSpec>? optionsFor(String path) => enumOptions[path];

  List<ConfigIssue> issuesFor(String path) => issues[path] ?? const [];

  /// True while something staged cannot be saved as written. Apply stays out
  /// of reach until it is fixed: a batch is refused whole, so sending it
  /// would spend a restart to be told the same thing.
  bool get hasBlockingIssues =>
      issues.values.any((forPath) => forPath.any((i) => i.isBlocking));

  SettingsState copyWith({
    PresentationSchema? schema,
    String? schemaVersion,
    Map<String, dynamic>? values,
    Set<String>? secretsSet,
    Map<String, List<OptionSpec>>? enumOptions,
    Map<String, dynamic>? stagedChanges,
    Map<String, List<ConfigIssue>>? issues,
    bool? isLoading,
    String? error,
  }) {
    return SettingsState(
      schema: schema ?? this.schema,
      schemaVersion: schemaVersion ?? this.schemaVersion,
      values: values ?? this.values,
      secretsSet: secretsSet ?? this.secretsSet,
      enumOptions: enumOptions ?? this.enumOptions,
      stagedChanges: stagedChanges ?? this.stagedChanges,
      issues: issues ?? this.issues,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

final settingsProvider = NotifierProvider<SettingsNotifier, SettingsState>(
  SettingsNotifier.new,
);

/// The server's own settings as a [SettingsBinding], so the schema widgets
/// render `/server/config` without depending on this provider directly.
class ServerSettingsBinding implements SettingsBinding {
  final SettingsState state;
  final SettingsNotifier notifier;

  const ServerSettingsBinding(this.state, this.notifier);

  @override
  dynamic effectiveValue(String path) => state.getEffective(path);

  @override
  bool isStaged(String path) => state.isStaged(path);

  @override
  bool hasHiddenSecret(String path) => state.hasHiddenSecret(path);

  @override
  List<OptionSpec>? optionsFor(String path) => state.optionsFor(path);

  @override
  List<ConfigIssue> issuesFor(String path) => state.issuesFor(path);

  @override
  void stage(String path, dynamic value) => notifier.stageChange(path, value);
}

/// Global toggle for "expert" importance fields.
class ExpertModeNotifier extends Notifier<bool> {
  @override
  bool build() => false;
  void toggle() => state = !state;
  void set(bool value) => state = value;
}

final expertModeProvider = NotifierProvider<ExpertModeNotifier, bool>(
  ExpertModeNotifier.new,
);

class SettingsNotifier extends Notifier<SettingsState> {
  Timer? _validationTimer;
  // Bumped on every check so a slow answer cannot land on top of a newer one.
  int _validationGeneration = 0;

  @override
  SettingsState build() {
    ref.onDispose(() => _validationTimer?.cancel());
    return const SettingsState();
  }

  Future<void> loadConfig() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final api = ref.read(kalinkaProxyProvider);
      // Fetch schema + values in parallel.
      final results = await Future.wait([
        api.getSettingsSchema(),
        api.getSettings(),
      ]);
      final schema = results[0] as PresentationSchema;
      final envelope = (results[1] as Map).cast<String, dynamic>();
      final values = (envelope['values'] as Map? ?? {}).cast<String, dynamic>();
      final secretsSet = (envelope['secrets_set'] as List? ?? const [])
          .cast<String>()
          .toSet();
      // Dynamic options: `{path: [{value, label}, …]}`. Present only for
      // fields the server resolves live (shares it found, drives plugged
      // in); absent fields fall back to the schema's static enum_values.
      final enumOptions = _optionsFromEnvelope(envelope);

      state = state.copyWith(
        schema: schema,
        // The values endpoint reports its own schema_version; if the two
        // disagree (plugin reloaded between the two fetches), the schema's
        // version wins — UI rendering is driven by it.
        schemaVersion: schema.schemaVersion,
        values: values,
        secretsSet: secretsSet,
        enumOptions: enumOptions,
        stagedChanges: {},
        issues: {},
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  static Map<String, List<OptionSpec>> _optionsFromEnvelope(
    Map<String, dynamic> envelope,
  ) {
    final raw = (envelope['enum_options'] as Map? ?? {})
        .cast<String, dynamic>();
    final parsed = <String, List<OptionSpec>>{};
    raw.forEach((path, options) {
      if (options is List) {
        parsed[path] = options
            .whereType<Map>()
            .map((e) => OptionSpec.fromJson(e.cast<String, dynamic>()))
            .toList();
      }
    });
    return parsed;
  }

  /// Stage a change for ``path``. If the new value matches the current
  /// server-side value (i.e. the user just typed their way back to the
  /// original), the entry is *unstaged* instead — the row no longer
  /// shows the "Staged" pill and the pending-changes counter goes back
  /// down. Without this, manually reverting an edit would leave a
  /// no-op change in the staging area and dirty the apply button.
  void stageChange(String path, dynamic value) {
    if (_valuesEqual(value, _stored(path))) {
      if (state.stagedChanges.containsKey(path)) unstageChange(path);
      return;
    }
    final existing = state.stagedChanges[path];
    if (_valuesEqual(value, existing)) return; // No-op write
    final newStaged = Map<String, dynamic>.from(state.stagedChanges);
    newStaged[path] = value;
    state = state.copyWith(stagedChanges: newStaged);
    _scheduleValidation();
  }

  /// The server's value at [path] for telling a revert from an edit. An unset
  /// credential is empty; a held one is unknown and matches nothing.
  dynamic _stored(String path) {
    if (state.values.containsKey(path) || state.secretsSet.contains(path)) {
      return state.values[path];
    }
    return _isSecret(path) ? '' : null;
  }

  bool _isSecret(String path) =>
      state.schema?.field(path)?.widget == WidgetKind.password;

  void unstageChange(String path) {
    final newStaged = Map<String, dynamic>.from(state.stagedChanges);
    newStaged.remove(path);
    state = state.copyWith(stagedChanges: newStaged);
    _scheduleValidation();
  }

  void discardAll() {
    _validationTimer?.cancel();
    _validationGeneration++;
    state = state.copyWith(stagedChanges: {}, issues: {});
  }

  void _scheduleValidation() {
    _validationTimer?.cancel();
    if (state.stagedChanges.isEmpty) {
      _validationGeneration++;
      state = state.copyWith(issues: {});
      return;
    }
    // Nothing to check against until the schema has been read.
    if (state.schemaVersion == null) return;
    _validationTimer = Timer(_validationDelay, validateStaged);
  }

  /// Ask the server what it makes of everything staged, and show its answer.
  /// The whole set goes every time, not just the field that changed: a value
  /// can be fine beside one edit and wrong beside another.
  Future<void> validateStaged() async {
    _validationTimer?.cancel();
    final version = state.schemaVersion;
    final staged = Map<String, dynamic>.from(state.stagedChanges);
    final generation = ++_validationGeneration;
    if (version == null || staged.isEmpty) return;
    try {
      final api = ref.read(kalinkaProxyProvider);
      final issues = await api.validateSettings(
        schemaVersion: version,
        changes: staged,
      );
      if (generation != _validationGeneration) return;
      state = state.copyWith(issues: _byPath(issues));
    } catch (e) {
      // Not worth reporting: a page that cannot reach the server has bigger
      // news to show, and the save refuses on its own if the value is bad.
      _logger.d('Validating staged settings failed: $e');
      if (generation == _validationGeneration) {
        state = state.copyWith(issues: {});
      }
    }
  }

  static Map<String, List<ConfigIssue>> _byPath(List<ConfigIssue> issues) {
    final grouped = <String, List<ConfigIssue>>{};
    for (final issue in issues) {
      grouped.putIfAbsent(issue.path, () => []).add(issue);
    }
    return grouped;
  }

  /// Deep equality for the JSON-ish values we receive over the wire
  /// (primitives, lists, maps). Used by [stageChange] so reverting a
  /// folder list or any other collection back to the server value
  /// reliably unstages, even though `List<dynamic>` identities differ.
  static bool _valuesEqual(dynamic a, dynamic b) {
    if (identical(a, b)) return true;
    if (a == null || b == null) return a == b;
    if (a is num && b is num) return a == b;
    if (a is List && b is List) {
      if (a.length != b.length) return false;
      for (var i = 0; i < a.length; i++) {
        if (!_valuesEqual(a[i], b[i])) return false;
      }
      return true;
    }
    if (a is Map && b is Map) {
      if (a.length != b.length) return false;
      for (final key in a.keys) {
        if (!b.containsKey(key)) return false;
        if (!_valuesEqual(a[key], b[key])) return false;
      }
      return true;
    }
    return a == b;
  }

  Future<void> applyChanges() async {
    final version = state.schemaVersion;
    if (version == null || state.stagedChanges.isEmpty) return;
    // Only what is sent here is saved; an edit staged during the round trip
    // stays pending.
    final changes = Map<String, dynamic>.from(state.stagedChanges);
    try {
      final api = ref.read(kalinkaProxyProvider);
      await api.saveSettings(schemaVersion: version, changes: changes);
      // Fold staged → values on success; a credential is kept only as set.
      final newValues = Map<String, dynamic>.from(state.values);
      final newSecrets = Set<String>.from(state.secretsSet);
      changes.forEach((path, value) {
        if (!_isSecret(path)) {
          newValues[path] = value;
          return;
        }
        newValues.remove(path);
        if (value is String && value.isNotEmpty) {
          newSecrets.add(path);
        } else {
          newSecrets.remove(path);
        }
      });
      final unsent = {
        for (final e in state.stagedChanges.entries)
          if (!changes.containsKey(e.key) ||
              !_valuesEqual(changes[e.key], e.value))
            e.key: e.value,
      };
      _validationGeneration++;
      state = state.copyWith(
        values: newValues,
        secretsSet: newSecrets,
        stagedChanges: unsent,
        issues: {},
      );
      if (unsent.isNotEmpty) _scheduleValidation();
    } on SettingsValidationException catch (e) {
      // Nothing was saved, so the staged set stands; mark the rows it is about.
      _validationGeneration++;
      state = state.copyWith(issues: _byPath(e.issues), error: e.detail);
      rethrow;
    } catch (e) {
      state = state.copyWith(error: 'Failed to save: $e');
      rethrow;
    }
  }
}
