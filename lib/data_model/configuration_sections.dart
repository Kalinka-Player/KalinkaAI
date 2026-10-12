import 'presentation_schema.dart';

/// Presentation only: fields retain their backend paths, types and constraints.
class ConfigurationSections {
  static const timeoutPath =
      'base_config.device_automation.auto_off_timeout_seconds';
  static const updatePath = 'base_config.server.auto_upgrade';
  static const supervisorPath = 'base_config.server.supervisor_status';

  final List<BannerSpec> banners = [];
  final List<SectionSpec> server = [];
  final List<FieldSpec> playback = [];
  final List<FieldSpec> updates = [];

  ConfigurationSections(PresentationSchema? schema) {
    for (final page in schema?.pages ?? const <PageSpec>[]) {
      if (page.id != 'base_config' &&
          page.id != 'server' &&
          page.id != 'general' &&
          !(page.modules.isEmpty && page.sections.isNotEmpty)) {
        continue;
      }
      banners.addAll(page.banners);
      for (final section in page.sections) {
        final remaining = _partition(section);
        if (remaining != null) server.add(remaining);
      }
    }
  }

  SectionSpec? _partition(SectionSpec section) {
    final fields = <FieldSpec>[];
    for (final field in section.fields) {
      if (field.path == timeoutPath) {
        playback.add(field);
      } else if (field.path == updatePath) {
        updates.add(field);
      } else if (field.path != supervisorPath) {
        fields.add(field);
      }
    }
    final children = [for (final child in section.sections) ?_partition(child)];
    if (fields.isEmpty &&
        children.isEmpty &&
        section.collections.isEmpty &&
        section.banners.isEmpty) {
      return null;
    }
    return SectionSpec(
      id: section.id,
      title: section.title,
      icon: section.icon,
      importance: section.importance,
      banners: section.banners,
      fields: fields,
      collections: section.collections,
      sections: children,
    );
  }
}
