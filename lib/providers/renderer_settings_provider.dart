import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data_model/presentation_schema.dart'
    show ConfigIssue, FieldSpec, OptionSpec, SectionSpec;
import '../data_model/renderer_config.dart';
import '../data_model/renderer_config_adapter.dart';
import 'kalinka_player_api_provider.dart';
import 'settings_binding.dart';

/// One renderer's settings page: what the renderer reported, plus the edits
/// the user has staged but not applied.
///
/// Deliberately not folded into [settingsProvider]: these values live on the
/// renderer, are written path by path with no schema-version precondition, and
/// apply without restarting the server. Only the *rendering* is shared, via
/// [SettingsBinding].
class RendererSettingsState {
  /// The simple page — expert-tier fields are not in it.
  final List<SectionSpec> sections;

  /// Every field the renderer declared, flat and sorted by path, for the
  /// expert list.
  final List<FieldSpec> expertFields;

  /// Path → value as the renderer reported it, typed for the controls.
  final Map<String, dynamic> values;
  final Map<String, List<OptionSpec>> options;
  final Map<String, RendererApplyCost> applyCosts;
  final Map<String, dynamic> staged;

  final bool loading;
  final bool saving;

  /// Set when loading or saving failed; already phrased for the user.
  final String? error;

  /// True once a load has completed, so an empty page can be told apart from
  /// one that has not arrived yet.
  final bool loaded;

  const RendererSettingsState({
    this.sections = const [],
    this.expertFields = const [],
    this.values = const {},
    this.options = const {},
    this.applyCosts = const {},
    this.staged = const {},
    this.loading = false,
    this.saving = false,
    this.error,
    this.loaded = false,
  });

  int get pendingCount => staged.length;
  bool get hasPendingChanges => staged.isNotEmpty;

  /// The worst cost among the staged fields — what applying them will cost.
  RendererApplyCost get pendingCost {
    var worst = RendererApplyCost.unknown;
    for (final path in staged.keys) {
      final cost = applyCosts[path] ?? RendererApplyCost.unknown;
      if (cost.severity > worst.severity) worst = cost;
    }
    return worst;
  }

  RendererSettingsState copyWith({
    List<SectionSpec>? sections,
    List<FieldSpec>? expertFields,
    Map<String, dynamic>? values,
    Map<String, List<OptionSpec>>? options,
    Map<String, RendererApplyCost>? applyCosts,
    Map<String, dynamic>? staged,
    bool? loading,
    bool? saving,
    String? error,
    bool clearError = false,
    bool? loaded,
  }) => RendererSettingsState(
    sections: sections ?? this.sections,
    expertFields: expertFields ?? this.expertFields,
    values: values ?? this.values,
    options: options ?? this.options,
    applyCosts: applyCosts ?? this.applyCosts,
    staged: staged ?? this.staged,
    loading: loading ?? this.loading,
    saving: saving ?? this.saving,
    error: clearError ? null : (error ?? this.error),
    loaded: loaded ?? this.loaded,
  );
}

class RendererSettingsNotifier extends Notifier<RendererSettingsState> {
  RendererSettingsNotifier(this.rendererId);

  final String rendererId;

  /// Bumped per load so a slow response can't overwrite a newer one.
  int _generation = 0;

  @override
  RendererSettingsState build() => const RendererSettingsState();

  Future<void> load() async {
    final generation = ++_generation;
    state = state.copyWith(loading: true, clearError: true);
    try {
      final snapshot = await ref
          .read(kalinkaProxyProvider)
          .getRendererConfig(rendererId);
      if (_stale(generation)) return;
      final view = adaptRendererConfig(snapshot);
      state = RendererSettingsState(
        sections: view.sections,
        expertFields: view.expertFields,
        values: view.values,
        options: view.options,
        applyCosts: view.applyCosts,
        // A reload is the renderer's word on what is in effect; edits that
        // were never applied do not survive it.
        staged: const {},
        loaded: true,
      );
    } on RendererConfigException catch (e) {
      if (_stale(generation)) return;
      state = state.copyWith(loading: false, error: e.message, loaded: true);
    } catch (e) {
      if (_stale(generation)) return;
      state = state.copyWith(
        loading: false,
        error: 'Couldn’t load settings: $e',
        loaded: true,
      );
    }
  }

  /// Record an edit. Staging back to the stored value unstages instead, so
  /// typing your way back to the original clears the pending count.
  void stage(String path, dynamic value) {
    if (value == state.values[path]) {
      if (!state.staged.containsKey(path)) return;
      final next = Map<String, dynamic>.from(state.staged)..remove(path);
      state = state.copyWith(staged: next);
      return;
    }
    if (state.staged.containsKey(path) && state.staged[path] == value) return;
    state = state.copyWith(
      staged: Map<String, dynamic>.from(state.staged)..[path] = value,
    );
  }

  void discard() {
    if (state.staged.isEmpty) return;
    state = state.copyWith(staged: const {}, clearError: true);
  }

  /// Write the staged edits, then re-read.
  ///
  /// The reply carries what actually took effect, but a change can also
  /// reshape the page — a driver switch reveals different fields, the device
  /// list moves — so the renderer's next snapshot, not the reply, becomes the
  /// new page. The reply is kept only to report what it refused.
  Future<void> save() async {
    if (state.staged.isEmpty || state.saving) return;
    final changes = {
      for (final entry in state.staged.entries)
        entry.key: encodeRendererValue(entry.value),
    };
    state = state.copyWith(saving: true, clearError: true);
    final List<RendererConfigOutcome> rejected;
    try {
      final result = await ref
          .read(kalinkaProxyProvider)
          .updateRendererConfig(rendererId, changes);
      rejected = result.rejected.toList();
    } on RendererConfigException catch (e) {
      state = state.copyWith(saving: false, error: e.message);
      return;
    } catch (e) {
      state = state.copyWith(saving: false, error: 'Couldn’t save: $e');
      return;
    }
    await load();
    if (!ref.mounted || rejected.isEmpty) return;
    // Reported after the reload, which clears the error it would otherwise
    // land in.
    state = state.copyWith(error: _rejectionMessage(rejected));
  }

  static String _rejectionMessage(List<RendererConfigOutcome> rejected) {
    final first = rejected.first;
    final detail = first.error.isEmpty
        ? 'the renderer refused it'
        : first.error;
    if (rejected.length == 1) return '${first.path}: $detail';
    return '${rejected.length} settings were refused — ${first.path}: $detail';
  }

  bool _stale(int generation) => !ref.mounted || generation != _generation;
}

final rendererSettingsProvider =
    NotifierProvider.family<
      RendererSettingsNotifier,
      RendererSettingsState,
      String
    >(RendererSettingsNotifier.new);

/// A renderer's settings as a [SettingsBinding], so the schema widgets render
/// them without knowing where they came from.
class RendererSettingsBinding implements SettingsBinding {
  final RendererSettingsState state;
  final RendererSettingsNotifier notifier;

  const RendererSettingsBinding(this.state, this.notifier);

  @override
  dynamic effectiveValue(String path) =>
      state.staged.containsKey(path) ? state.staged[path] : state.values[path];

  @override
  bool isStaged(String path) => state.staged.containsKey(path);

  @override
  List<OptionSpec>? optionsFor(String path) => state.options[path];

  /// A renderer answers per write; there is no dry run to ask beforehand.
  @override
  List<ConfigIssue> issuesFor(String path) => const [];

  @override
  void stage(String path, dynamic value) => notifier.stage(path, value);
}
