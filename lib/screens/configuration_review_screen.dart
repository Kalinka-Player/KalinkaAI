import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data_model/presentation_schema.dart';
import '../providers/settings_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/configuration_page.dart';
import '../widgets/settings_collection.dart';
import '../widgets/settings_controls/issue_notes.dart';
import '../widgets/settings_controls/settings_binding.dart';
import '../widgets/settings_controls/settings_card.dart';
import '../widgets/settings_renderer.dart';

Iterable<FieldSpec> configurationFields(PresentationSchema? schema) sync* {
  Iterable<FieldSpec> within(List<SectionSpec> sections) sync* {
    for (final section in sections) {
      yield* section.fields;
      yield* within(section.sections);
    }
  }

  for (final page in schema?.pages ?? const <PageSpec>[]) {
    yield* within(page.sections);
    for (final module in page.modules) {
      yield* module.fields;
      yield* within(module.sections);
    }
  }
  yield* schema?.expertFields ?? const <FieldSpec>[];
}

CollectionSpec? _collectionFor(PresentationSchema? schema, String path) {
  var candidate = path;
  while (candidate.isNotEmpty) {
    final collection = schema?.collection(candidate);
    if (collection != null) return collection;
    final dot = candidate.lastIndexOf('.');
    if (dot < 0) break;
    candidate = candidate.substring(0, dot);
  }
  return null;
}

String configurationIssueLabel(PresentationSchema? schema, String path) {
  final field = configurationFields(schema)
      .where((field) => field.path == path)
      .firstOrNull;
  return field == null
      ? _collectionFor(schema, path)?.title ?? path
      : field.label;
}

/// A stable set of affected settings, so fixing one never removes its input.
class ConfigurationReviewScreen extends ConsumerWidget {
  final List<String> paths;
  final VoidCallback onClose;
  final bool handlesBack;

  const ConfigurationReviewScreen({
    super.key,
    required this.paths,
    required this.onClose,
    required this.handlesBack,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final fields = {
      for (final f in configurationFields(settings.schema)) f.path: f,
    };
    final collections = <String, CollectionSpec>{};
    for (final path in paths) {
      final collection = _collectionFor(settings.schema, path);
      if (collection != null) collections[collection.path] = collection;
    }
    return ConfigurationPage(
      title: 'Check your changes',
      description: 'Correct the settings below, then apply your changes.',
      icon: Icons.edit_note,
      parent: 'Configuration',
      onClose: onClose,
      handlesBack: handlesBack,
      bodyBuilder: (heading) => SettingsScope(
        binding: ServerSettingsBinding(
          settings,
          ref.read(settingsProvider.notifier),
        ),
        child: ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            heading,
            for (final collection in collections.values)
              SettingsCard(
                children: [SchemaCollectionRenderer(collection: collection)],
              ),
            for (final path in paths)
              if (!collections.keys.any(
                (c) => path == c || path.startsWith('$c.'),
              ))
                SettingsCard(
                  children: [
                    if (fields[path] case final field?)
                      SchemaFieldRenderer(
                        key: ValueKey('review-$path'),
                        field: field,
                      )
                    else
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              configurationIssueLabel(settings.schema, path),
                              style: KalinkaTextStyles.trayRowLabel,
                            ),
                            IssueNotes(issues: settings.issuesFor(path)),
                          ],
                        ),
                      ),
                  ],
                ),
          ],
        ),
      ),
    );
  }
}
