import 'package:flutter_test/flutter_test.dart';
import 'package:kalinka/data_model/configuration_sections.dart';
import 'package:kalinka/data_model/presentation_schema.dart';

void main() {
  test(
    'moves only known fields and preserves backend definitions and new content',
    () {
      const name = FieldSpec(
        path: ConfigurationSections.namePath,
        label: 'Service name',
        widget: WidgetKind.text,
        type: 'str',
        help: 'The server-provided name hint',
        constraints: Constraints(minLength: 1, maxLength: 80),
      );
      const power = FieldSpec(
        path: 'base_config.device_automation.auto_power_on',
        label: 'Backend power label',
        widget: WidgetKind.toggle,
        type: 'bool',
        readonly: true,
      );
      const timeout = FieldSpec(
        path: ConfigurationSections.timeoutPath,
        label: 'Backend timeout',
        widget: WidgetKind.numberInput,
        type: 'int',
        defaultValue: 90,
        constraints: Constraints(ge: 0, le: 3600, unit: 's'),
      );
      const future = FieldSpec(
        path: 'base_config.device_automation.future.enabled',
        label: 'New server setting',
        widget: WidgetKind.toggle,
        type: 'bool',
      );
      const collection = CollectionSpec(
        path: 'base_config.device_automation.future.entries',
        title: 'New entries',
        after: 'base_config.device_automation.future.enabled',
        replaces: ['base_config.device_automation.future.legacy'],
      );
      const banner = BannerSpec(
        text: 'Server notice',
        severity: Severity.warning,
      );
      const update = FieldSpec(
        path: ConfigurationSections.updatePath,
        label: 'Auto upgrade',
        widget: WidgetKind.toggle,
        type: 'bool',
      );
      const status = FieldSpec(
        path: ConfigurationSections.supervisorPath,
        label: 'Supervisor status',
        widget: WidgetKind.text,
        type: 'str',
        readonly: true,
        help: 'Server-provided status help',
      );
      const plugin = FieldSpec(
        path: 'input_modules.localfiles.enabled',
        label: 'Library plugin',
        widget: WidgetKind.toggle,
        type: 'bool',
      );
      const schema = PresentationSchema(
        schemaVersion: '1',
        pages: [
          PageSpec(
            id: 'general',
            title: 'General',
            banners: [banner],
            sections: [
              SectionSpec(
                id: 'base_config.server',
                title: 'Server',
                fields: [name, update, status],
              ),
              SectionSpec(
                id: 'base_config.device_automation',
                title: 'Device automation',
                fields: [power, timeout],
                sections: [
                  SectionSpec(
                    id: 'future',
                    title: 'Future',
                    banners: [banner],
                    fields: [future],
                    collections: [collection],
                  ),
                ],
              ),
              SectionSpec(
                id: 'base_config.future',
                title: 'Future settings',
                fields: [future],
                collections: [collection],
                banners: [banner],
              ),
            ],
          ),
          PageSpec(
            id: 'modules',
            title: 'Modules',
            modules: [
              ModuleSpec(
                id: 'localfiles',
                kind: 'input_module',
                title: 'My Library',
                fields: [plugin],
              ),
            ],
          ),
        ],
        expertFields: [power, timeout, future],
      );
      final result = ConfigurationSections(schema);
      expect(result.serviceName, same(name));
      expect(result.updates.single, same(update));
      expect(result.details.single, same(status));
      expect(result.banners.single, same(banner));
      final remaining = result.server.single;
      expect(remaining.id, 'base_config.future');
      expect(remaining.fields.single, same(future));
      expect(remaining.collections.single, same(collection));
      expect(remaining.banners.single, same(banner));
      expect(schema.pages.first.sections[1].fields, [power, timeout]);
      expect(schema.expertFields, [same(power), same(timeout), same(future)]);
    },
  );
}
