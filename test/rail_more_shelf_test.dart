import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kalinka/providers/connection_settings_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kalinka/providers/box_control_provider.dart';
import 'package:kalinka/providers/catalog_sources_provider.dart';
import 'package:kalinka/providers/collections_provider.dart';
import 'package:kalinka/providers/connection_state_provider.dart';
import 'package:kalinka/providers/server_info_provider.dart';
import 'package:kalinka/widgets/shell_navigation.dart';

class _Connected extends ConnectionStateNotifier {
  @override
  ConnectionStatus build() => ConnectionStatus.connected;
}

void main() {
  // A follower above the shelf's controls left their tooltips, overlay
  // children themselves, no position to lay out from: an assertion on hover.
  testWidgets('More unfolds a shelf whose controls show their tooltips', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    // Too short for Change server to stand under the rest.
    tester.view.physicalSize = const Size(800, 300);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPrefsProvider.overrideWithValue(prefs),
          connectionStateProvider.overrideWith(_Connected.new),
          catalogSourcesProvider.overrideWith((ref) async => const []),
          collectionsShelfProvider.overrideWith((ref) async => null),
          boxControlProvider.overrideWith((ref) async => null),
          pluginCatalogEnabledProvider.overrideWithValue(true),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Row(
              children: [
                SizedBox(
                  width: 88,
                  child: ShellNavigation(
                    onNavigate: (_, _) {},
                    onAction: (_) {},
                  ),
                ),
                const Expanded(child: SizedBox()),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('navigation-more')), findsOneWidget);
    await tester.ensureVisible(find.byKey(const ValueKey('navigation-more')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('navigation-more')));
    await tester.pumpAndSettle();
    final control = find.byKey(const ValueKey('navigation-changeServer'));
    expect(control, findsOneWidget);
    // Under the pointer, the control's tooltip shows.
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: tester.getCenter(control));
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.text('Connect to a different server'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await mouse.removePointer();
  });
}
