import '../data_model/collection_entry.dart';
import '../data_model/presentation_schema.dart';
import '../utils/json_equality.dart';
import 'settings_binding.dart';

/// One entry of a collection as a [SettingsBinding], so the page's own
/// controls edit it in a sheet. Paths are relative to the entry.
///
/// Values are read from [entry], the sheet's working copy, which is always
/// current; everything the store answers — issues, suggestions, which
/// credentials it holds — comes from [page], which may lag a frame behind.
class CollectionEntryBinding implements SettingsBinding {
  final SettingsBinding page;
  final CollectionSpec collection;
  final Map<String, dynamic> entry;

  /// The entry as the sheet opened on it, which an edit is told apart from.
  final Map<String, dynamic> before;
  final void Function(String path, dynamic value) onStage;

  const CollectionEntryBinding({
    required this.page,
    required this.collection,
    required this.entry,
    required this.before,
    required this.onStage,
  });

  String _reported(String path) => '${collection.entryPath(entry)}.$path';

  @override
  dynamic effectiveValue(String path) => readEntryPath(entry, path);

  @override
  bool isStaged(String path) =>
      entryHasPath(entry, path) != entryHasPath(before, path) ||
      !jsonEquals(readEntryPath(entry, path), readEntryPath(before, path));

  /// A credential the entry leaves out is the one the store keeps; one it
  /// holds, even empty, was typed here and replaces it.
  @override
  bool hasHiddenSecret(String path) =>
      !entryHasPath(entry, path) && page.hasHiddenSecret(_reported(path));

  @override
  List<OptionSpec>? optionsFor(String path) =>
      page.optionsFor('${collection.path}.$path');

  @override
  List<ConfigIssue> issuesFor(String path) => page.issuesFor(_reported(path));

  @override
  void stage(String path, dynamic value) => onStage(path, value);

  @override
  Future<void> refreshOptions() => page.refreshOptions();
}
