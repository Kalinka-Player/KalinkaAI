import 'presentation_schema.dart';

/// Presentation only: fields retain their backend paths, types and constraints.
class ConfigurationSections {
  static const namePath = 'base_config.server.service_name';
  static const timeoutPath =
      'base_config.device_automation.auto_off_timeout_seconds';
  static const updatePath = 'base_config.server.auto_upgrade';
  static const supervisorPath = 'base_config.server.supervisor_status';

  final List<BannerSpec> banners = [];
  final List<SectionSpec> server = [];
  final List<FieldSpec> details = [];
  final List<FieldSpec> updates = [];
  FieldSpec? serviceName;

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
    // Automation stays in the server's complete expert field list. Hide the
    // whole section here, including any nested settings added by the server.
    if (section.id == 'base_config.device_automation') return null;

    final fields = <FieldSpec>[];
    for (final field in section.fields) {
      if (field.path == namePath) {
        serviceName = field;
      } else if (field.path == updatePath) {
        updates.add(field);
      } else if (field.path == supervisorPath) {
        details.add(field);
      } else {
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
