import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kalinka/data_model/plugin_catalog.dart';
import 'package:kalinka/providers/connection_settings_provider.dart';
import 'package:kalinka/providers/connection_state_provider.dart';
import 'package:kalinka/providers/plugin_catalog_provider.dart';
import 'package:kalinka/providers/server_info_provider.dart';
import 'package:kalinka/screens/plugin_catalog_screen.dart';
import 'package:kalinka/theme/app_theme.dart';

class _Connected extends ConnectionStateNotifier {
  @override
  ConnectionStatus build() => ConnectionStatus.connected;
}

// Keep the approved inline layout and large display title; the remaining text
// uses the settings screen's shared type scale. Load the real bundled weights.
// Fixtures contain catalog declarations, not illustrative installed states.
// Baselines use Flutter 3.47.6, matching CI; rounded-border rasterization differs
// from 3.44.8. Review the image diffs when changing the SDK before updating them.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final manifest =
        jsonDecode(await rootBundle.loadString('FontManifest.json')) as List;
    for (final family in manifest) {
      final loader = FontLoader(family['family'] as String);
      for (final font in family['fonts'] as List) {
        loader.addFont(rootBundle.load(font['asset'] as String));
      }
      await loader.load();
    }
  });

  for (final scene in [
    'compact-catalog',
    'compact-collapsing',
    'compact-expanded',
    'phone-expanded',
    'tablet-device',
  ]) {
    testWidgets(scene, (tester) async {
      final phone = scene.startsWith('phone');
      final size = scene.startsWith('compact')
          ? const Size(483, 619)
          : phone
          ? const Size(390, 730)
          : const Size(692, 890);
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      SharedPreferences.setMockInitialValues({
        'Kalinka.name': 'My Kalinka Service',
      });
      final prefs = await SharedPreferences.getInstance();
      final json =
          jsonDecode(
                File('test/fixtures/plugin_catalog.json').readAsStringSync(),
              )
              as Map<String, dynamic>;
      final catalog = PluginCatalog.fromJson({
        ...json,
        'status': 'available',
        'last_successful_check': DateTime.now().toUtc().toIso8601String(),
      });
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPrefsProvider.overrideWithValue(prefs),
            connectionStateProvider.overrideWith(_Connected.new),
            pluginCatalogEnabledProvider.overrideWithValue(true),
            serverInfoProvider.overrideWith(
              (ref) async => const ServerInfo(
                version: '5.5.0',
                latencyMs: 12,
                pluginCatalogEnabled: true,
              ),
            ),
            pluginCatalogProvider.overrideWith((ref) async => catalog),
          ],
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: MediaQuery(
              data: MediaQueryData(size: Size(phone ? 390 : 1024, size.height)),
              child: const RepaintBoundary(
                key: ValueKey('capture'),
                child: Scaffold(body: PluginCatalogScreen()),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<Text>(find.text('Plugins')).style,
        KalinkaFonts.display(
          fontSize: phone ? 29 : 35,
          fontWeight: FontWeight.w400,
          color: KalinkaColors.frost,
          height: 1.2,
        ),
      );
      final scroll = tester
          .widget<CustomScrollView>(find.byType(CustomScrollView))
          .controller!;
      if (scene == 'tablet-device') {
        await tester.tap(find.widgetWithText(ChoiceChip, 'Device control'));
        await tester.pumpAndSettle();
      }
      if (scene == 'compact-collapsing') {
        final delegate = tester
            .widget<SliverPersistentHeader>(find.byType(SliverPersistentHeader))
            .delegate;
        scroll.jumpTo((delegate.maxExtent - delegate.minExtent) / 4);
        await tester.pumpAndSettle();
      } else if (scene != 'compact-catalog') {
        final id = scene == 'tablet-device' ? 'musiccast' : 'jamendo';
        final row = find.byKey(ValueKey('plugin-$id'));
        await tester.ensureVisible(row);
        await tester.pumpAndSettle();
        await tester.tap(
          find.descendant(of: row, matching: find.byType(Text)).first,
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(row);
        await tester.pumpAndSettle();
        if (scene == 'compact-expanded') {
          scroll.jumpTo(
            (scroll.offset + 260).clamp(0, scroll.position.maxScrollExtent),
          );
          await tester.pumpAndSettle();
        }
      }
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byKey(const ValueKey('capture')),
        matchesGoldenFile('goldens/plugin-catalog/$scene.png'),
      );
    });
  }
}
