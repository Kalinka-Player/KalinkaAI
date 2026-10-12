import 'package:flutter_test/flutter_test.dart';
import 'package:kalinka/data_model/configuration_sections.dart';
import 'package:kalinka/data_model/presentation_schema.dart';

void main() {
  test(
    'moves only known fields and preserves backend definitions and new content',
    () {
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
                fields: [update],
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
      );
      final result = ConfigurationSections(schema);
      expect(result.playback.single, same(timeout));
      expect(result.updates.single, same(update));
      expect(result.banners.single, same(banner));
      final remaining = result.server.single;
      expect(remaining.id, 'base_config.device_automation');
      expect(remaining.fields.single, same(power));
      expect(remaining.sections.single.fields.single, same(future));
      expect(remaining.sections.single.collections.single, same(collection));
      expect(remaining.sections.single.banners.single, same(banner));
      expect(schema.pages.first.sections[1].fields, [power, timeout]);
    },
  );
}
