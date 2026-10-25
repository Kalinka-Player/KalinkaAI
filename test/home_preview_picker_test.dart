import 'dart:convert';

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
import 'package:kalinka/screens/customise_home_screen.dart';
import 'package:kalinka/theme/app_theme.dart';
import 'package:kalinka/widgets/browse_rows_shimmer.dart' show LoadingSpinner;
import 'package:kalinka/widgets/home/catalog_pin_button.dart';
import 'package:kalinka/widgets/home/home_preview_illustration.dart';
import 'package:kalinka/widgets/sheet_anchor.dart';

import 'support/home_shell.dart' show SettableConnection;
import 'support/server_answer.dart';

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
  ServersByHost? servers,
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
      if (servers == null) ...[
        connectionStateProvider.overrideWith(_Connected.new),
        serverAnswering('box-1'),
      ] else ...[
        connectionStateProvider.overrideWith(SettableConnection.new),
        servers.client,
      ],
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
        expect(container.read(pinnedCatalogsProvider)!.single.preview, type);
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
          container.read(pinnedCatalogsProvider)!.single.preview,
          HomePreviewType.compact,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('pinning waits for the server to be known', (tester) async {
    final servers = ServersByHost()
      ..ids['localhost'] = 'box-a'
      ..silent.add('localhost');
    await _pump(tester, servers: servers);
    VoidCallback? pin() =>
        tester.widget<IconButton>(find.byType(IconButton)).onPressed;
    expect(pin(), isNull);

    servers.silent.clear();
    await tester.pump(const Duration(seconds: 10));
    await tester.pump(const Duration(milliseconds: 1));
    expect(pin(), isNotNull);
  });

  testWidgets('Customise Home waits for the server to be known', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'Kalinka.host': 'localhost',
      'Kalinka.port': 8080,
      'Kalinka.pinnedCatalogs.v1:id:box-a': jsonEncode([
        PinnedCatalog(
          page: _page,
          filter: const BrowseFilterQuery(),
          preview: HomePreviewType.list,
        ).toJson(),
      ]),
    });
    final prefs = await SharedPreferences.getInstance();
    final servers = ServersByHost()
      ..ids['localhost'] = 'box-a'
      ..silent.add('localhost');
    final container = ProviderContainer(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        connectionStateProvider.overrideWith(SettableConnection.new),
        servers.client,
        sourceModulesProvider.overrideWith((ref) => const []),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: const CustomiseHomeScreen(),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 1));
    expect(find.byType(LoadingSpinner), findsOneWidget);
    expect(find.text('Nothing pinned yet'), findsNothing);
    expect(find.text('Recently added'), findsNothing);

    servers.silent.clear();
    await tester.pump(const Duration(seconds: 10));
    await tester.pump(const Duration(milliseconds: 1));
    expect(find.byType(LoadingSpinner), findsNothing);
    expect(find.text('Recently added'), findsOneWidget);
  });

  testWidgets('a layout chosen once another server answers is not pinned', (
    tester,
  ) async {
    final servers = ServersByHost()..ids['localhost'] = 'box-a';
    final container = await _pump(tester, servers: servers);
    await tester.tap(find.byTooltip('Pin catalog to Home'));
    await tester.pumpAndSettle();

    servers.ids['localhost'] = 'box-b';
    final connection =
        container.read(connectionStateProvider.notifier) as SettableConnection;
    connection.set(ConnectionStatus.reconnecting);
    connection.set(ConnectionStatus.connected);
    await tester.pump(const Duration(milliseconds: 1));
    final option = find.byKey(const ValueKey('home-preview-option-list'));
    await tester.ensureVisible(option);
    await tester.pumpAndSettle();
    await tester.tap(option);
    await tester.pumpAndSettle();

    expect(container.read(pinnedCatalogsProvider), isEmpty);
    expect(
      container
          .read(sharedPrefsProvider)
          .getKeys()
          .where((k) => k.startsWith('Kalinka.pinnedCatalogs')),
      isEmpty,
    );
  });
}
