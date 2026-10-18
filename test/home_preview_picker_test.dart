import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kalinka/data_model/browse_filters.dart';
import 'package:kalinka/data_model/data_model.dart';
import 'package:kalinka/providers/connection_settings_provider.dart';
import 'package:kalinka/providers/connection_state_provider.dart';
import 'package:kalinka/providers/pinned_catalogs_provider.dart';
import 'package:kalinka/providers/search_session_provider.dart';
import 'package:kalinka/providers/source_modules_provider.dart';
import 'package:kalinka/theme/app_theme.dart';
import 'package:kalinka/widgets/home/catalog_pin_button.dart';
import 'package:kalinka/widgets/home/home_preview_illustration.dart';
import 'package:kalinka/widgets/sheet_anchor.dart';

class _Connected extends ConnectionStateNotifier {
  @override
  ConnectionStatus build() => ConnectionStatus.connected;
}

final _page = CatalogPage.category(
  id: 'kalinka:example:catalog:recent',
  title: 'Recently added',
  provider: 'Example Music',
);

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  Size size = const Size(375, 812),
  double textScale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({
    'Kalinka.host': 'localhost',
    'Kalinka.port': 8080,
    'Kalinka.name': 'Test',
  });
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      sharedPrefsProvider.overrideWithValue(prefs),
      connectionStateProvider.overrideWith(_Connected.new),
      sourceModulesProvider.overrideWith(
        (ref) => [
          ModuleInfo(
            name: 'example',
            title: 'Example Music',
            enabled: true,
            state: ModuleState.ready,
            capabilities: const [ModuleCapability.catalogs],
          ),
        ],
      ),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.dark(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
            disableAnimations: true,
          ),
          child: child!,
        ),
        home: Scaffold(
          body: Row(
            children: [
              if (size.width >= 900) const Expanded(child: SizedBox()),
              Expanded(
                child: SheetAnchor(
                  child: Center(
                    child: CatalogPinButton(
                      page: _page,
                      filter: const BrowseFilterQuery(),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  for (final type in HomePreviewType.values) {
    testWidgets(
      'pinning with the ${type.label} illustration saves that layout',
      (tester) async {
        final container = await _pump(tester);
        await tester.tap(find.byTooltip('Pin catalog to Home'));
        await tester.pumpAndSettle();
        expect(find.text('Pin to Home'), findsOneWidget);
        expect(find.byType(HomePreviewIllustration), findsNWidgets(4));
        expect(container.read(pinnedCatalogsProvider), isEmpty);
        final option = find.byKey(ValueKey('home-preview-option-${type.name}'));
        await tester.ensureVisible(option);
        await tester.pumpAndSettle();
        expect(tester.getSize(option).height, greaterThanOrEqualTo(48));
        await tester.tap(option);
        await tester.pumpAndSettle();
        expect(container.read(pinnedCatalogsProvider).single.preview, type);
        expect(find.byType(BottomSheet), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final size in [
    const Size(375, 812),
    const Size(812, 375),
    const Size(1200, 800),
  ]) {
    testWidgets(
      'pin choices scroll, dismiss and support keyboard at $size with large text',
      (tester) async {
        final container = await _pump(tester, size: size, textScale: 2);
        await tester.tap(find.byTooltip('Pin catalog to Home'));
        await tester.pumpAndSettle();
        final compact = find.byKey(
          const ValueKey('home-preview-option-compact'),
        );
        await tester.ensureVisible(compact);
        await tester.pumpAndSettle();
        expect(compact.hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
        if (size.width >= 900) {
          expect(tester.getRect(compact).left, greaterThanOrEqualTo(600));
          expect(tester.getRect(compact).right, lessThanOrEqualTo(1200));
        }
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(container.read(pinnedCatalogsProvider), isEmpty);
        await tester.tap(find.byTooltip('Pin catalog to Home'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Close'));
        await tester.pumpAndSettle();
        expect(container.read(pinnedCatalogsProvider), isEmpty);
        await tester.tap(find.byTooltip('Pin catalog to Home'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(compact);
        await tester.pumpAndSettle();
        final label = find.descendant(
          of: compact,
          matching: find.text('Compact'),
        );
        Focus.of(tester.element(label)).requestFocus();
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.space);
        await tester.pumpAndSettle();
        expect(
          container.read(pinnedCatalogsProvider).single.preview,
          HomePreviewType.compact,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}
