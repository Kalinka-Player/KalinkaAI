import 'dart:math';

import 'presentation_schema.dart';

/// The entries of a collection's value, as maps. Anything else in the list
/// is not an entry this app can edit and is left out.
List<Map<String, dynamic>> entriesOf(dynamic value) => [
  if (value is List)
    for (final item in value)
      if (item is Map) item.cast<String, dynamic>(),
];

/// The value at dotted [path] inside [entry], or null where any part of the
/// way is missing.
dynamic readEntryPath(Map<String, dynamic> entry, String path) {
  dynamic current = entry;
  for (final part in path.split('.')) {
    if (current is! Map || !current.containsKey(part)) return null;
    current = current[part];
  }
  return current;
}

/// The group holding the last part of dotted [path], and that part's key.
(dynamic, String) _parentOf(Map<String, dynamic> entry, String path) {
  final at = path.lastIndexOf('.');
  if (at < 0) return (entry, path);
  return (readEntryPath(entry, path.substring(0, at)), path.substring(at + 1));
}

/// Whether [entry] holds anything at [path] — a credential left out means
/// "keep the saved one", which an explicit empty value does not.
bool entryHasPath(Map<String, dynamic> entry, String path) {
  final (parent, key) = _parentOf(entry, path);
  return parent is Map && parent.containsKey(key);
}

/// Writes [value] at [path] inside [entry], creating the groups on the way.
void writeEntryPath(Map<String, dynamic> entry, String path, dynamic value) {
  final parts = path.split('.');
  var current = entry;
  for (final part in parts.sublist(0, parts.length - 1)) {
    final next = current[part];
    if (next is Map<String, dynamic>) {
      current = next;
    } else {
      final created = next is Map
          ? next.cast<String, dynamic>()
          : <String, dynamic>{};
      current[part] = created;
      current = created;
    }
  }
  current[parts.last] = value;
}

void removeEntryPath(Map<String, dynamic> entry, String path) {
  final (parent, key) = _parentOf(entry, path);
  if (parent is Map) parent.remove(key);
}

/// A copy of [entry] no later edit can reach through, nested groups included.
Map<String, dynamic> copyEntry(Map<String, dynamic> entry) =>
    _copy(entry) as Map<String, dynamic>;

dynamic _copy(dynamic value) {
  if (value is Map) {
    return <String, dynamic>{
      for (final e in value.entries) e.key.toString(): _copy(e.value),
    };
  }
  if (value is List) return [for (final item in value) _copy(item)];
  return value;
}

final _random = Random.secure();

/// An id for an entry this app adds, in the form the server accepts, so an
/// issue about the entry can name it before it has ever been saved.
String newRecordId() {
  final hex = List.generate(
    12,
    (_) => _random.nextInt(16).toRadixString(16),
  ).join();
  return 'rec_$hex';
}

extension CollectionEntries on CollectionSpec {
  /// The shape [entry] takes: the variant its discriminator names, or the
  /// only one there is.
  VariantSpec? variantOf(Map<String, dynamic> entry) {
    if (variants.isEmpty) return null;
    final key = discriminator == null ? null : entry[discriminator];
    return variants.firstWhere(
      (v) => v.key == key,
      orElse: () => variants.first,
    );
  }

  /// Where the server reports on [entry], and on its fields below that.
  String entryPath(Map<String, dynamic> entry) => '$path.${entry['id']}';

  /// [entries] in a few words: the one entry's summary, or how many there are.
  String previewOf(List<Map<String, dynamic>> entries) => switch (entries) {
    [] => '',
    [final entry] => variantOf(entry)?.summaryOf(entry) ?? '',
    _ => '${entries.length} items',
  };
}

extension GroupVariants on GroupSpec {
  /// The shape this part of [entry] takes: the one its discriminator names,
  /// else the default.
  VariantSpec? variantOf(Map<String, dynamic> entry) {
    if (discriminator == null || variants.isEmpty) return null;
    final key = readEntryPath(entry, '$path.$discriminator') ?? defaultVariant;
    return variants.firstWhere(
      (v) => v.key == key,
      orElse: () => variants.first,
    );
  }
}

extension VariantCard on VariantSpec {
  /// The card's second line: the summary fields that hold something.
  String summaryOf(Map<String, dynamic> entry) => [
    for (final field in summary)
      if (readEntryPath(entry, field) case final value?)
        if (value.toString().trim().isNotEmpty) value.toString(),
  ].join(' · ');
}
