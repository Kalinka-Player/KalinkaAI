import 'package:flutter/material.dart' show Color, IconData;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data_model/data_model.dart';
import '../utils/schema_icons.dart';
import 'connection_settings_provider.dart';
import 'kalinka_player_api_provider.dart';

/// Display metadata for a single source.
class SourceDisplayInfo {
  final String name;
  final String title;
  final String abbreviation;

  /// Drawn in place of [abbreviation] where the source declares an icon this
  /// app has.
  final IconData? icon;
  final Color color;

  /// The server's own source, which wears no badge: it is the app itself
  /// speaking, not somewhere the music came from.
  final bool builtin;

  const SourceDisplayInfo({
    required this.name,
    required this.title,
    required this.abbreviation,
    this.icon,
    required this.color,
    this.builtin = false,
  });
}

/// Backend identifier for the local-files source.
const kLocalSourceName = 'localfiles';

/// Whether [name] is the on-device/local-files source. It is attributed like
/// any other source; this only says which one comes first in a list.
bool isLocalSource(String name) => name.toLowerCase() == kLocalSourceName;

/// The source segment of an entity id, or null for an id that has none.
String? sourceOfId(String entityId) {
  try {
    return EntityId.fromString(entityId).source;
  } catch (_) {
    return null;
  }
}

/// Curated palette of muted colors for source badges on dark backgrounds.
///
/// Slots are ordered so the alphabet-position mapping in [colorForSourceName]
/// lands well-known sources on their established colours:
///   Q (Qobuz) -> slot 0 gold, J (Jamendo) -> slot 1 blue,
///   L (Localfiles) -> slot 3 neutral gray.
const _sourceColors = [
  Color(0xFFE8C87A), // gold
  Color(0xFF5B8DEF), // soft blue
  Color(0xFF4ADE80), // green
  Color(0xFFBBBBC0), // neutral gray
  Color(0xFFAB7BF5), // purple
  Color(0xFFEF8B5B), // coral
  Color(0xFF5BE8C8), // teal
  Color(0xFFE85B8D), // pink
];

/// Returns a stable badge colour for a source based on the first letter of its
/// name. Each letter maps into the palette by its position in the alphabet, so
/// a source's colour never depends on the order the backend returns modules in.
Color colorForSourceName(String name) {
  final letter = name.isNotEmpty ? name[0].toLowerCase() : '?';
  final code = letter.codeUnitAt(0) - 'a'.codeUnitAt(0);
  final index = code >= 0 && code < 26 ? code : _sourceColors.length - 1;
  return _sourceColors[index % _sourceColors.length];
}

/// Fetches enabled input modules from the backend.
final sourceModulesProvider = FutureProvider<List<ModuleInfo>>((ref) async {
  final settings = ref.watch(connectionSettingsProvider);
  if (!settings.isSet) return <ModuleInfo>[];
  final api = ref.read(kalinkaProxyProvider);
  final modulesAndDevices = await api.listModules();
  return modulesAndDevices.inputModules.where((m) => m.enabled).toList();
});

/// Number of enabled input sources. Returns 0 while loading.
///
/// Selects the count off [sourceModulesProvider] rather than watching the whole
/// AsyncValue: on (re)connect the future reloads (data → loading → data), and a
/// plain watch would re-notify this provider mid-build whenever a widget pulled
/// it in during that reload — `setState() called during build`. Loading states
/// carry the previous value forward, so the selected count is stable across the
/// transition and only changes when the module list actually does.
final sourceCountProvider = Provider<int>((ref) {
  return ref.watch(sourceModulesProvider.select((m) => m.value?.length ?? 0));
});

/// Maps source name -> display info (title, abbreviation, color).
/// Returns empty map while loading.
///
/// Selects the module list (see [sourceCountProvider] for why) so reload
/// transitions don't trigger a rebuild-during-build.
final sourceDisplayInfoProvider = Provider<Map<String, SourceDisplayInfo>>((
  ref,
) {
  final modules = ref.watch(sourceModulesProvider.select((m) => m.value));
  if (modules == null) return {};
  final map = <String, SourceDisplayInfo>{};
  for (final m in modules) {
    map[m.name] = SourceDisplayInfo(
      name: m.name,
      title: m.title,
      abbreviation: m.title.isNotEmpty ? m.title[0].toUpperCase() : '?',
      icon: iconNamed(m.icon),
      color: colorForSourceName(m.name),
      builtin: m.builtin,
    );
  }
  return map;
});

/// The sources the server provides itself, as the module list declares them.
/// Empty while the list loads. Their shelves are the user's own and are laid
/// out as such, not among the catalogs to explore.
final builtinSourcesProvider = Provider<Set<String>>((ref) {
  final modules = ref.watch(sourceModulesProvider.select((m) => m.value));
  return {
    for (final m in modules ?? const <ModuleInfo>[])
      if (m.builtin) m.name,
  };
});

/// Whether [entityId] comes from a source the server keeps for the listener
/// (a collection), which is written to and so may change between reads.
bool ownedByServer(Set<String> builtinSources, String entityId) {
  final source = sourceOfId(entityId);
  return source != null && builtinSources.contains(source);
}
