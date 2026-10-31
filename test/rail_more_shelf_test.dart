import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kalinka/providers/connection_settings_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kalinka/data_model/data_model.dart';
import 'package:kalinka/providers/box_control_provider.dart';
import 'package:kalinka/providers/catalog_sources_provider.dart';
import 'package:kalinka/providers/collections_provider.dart';
import 'package:kalinka/providers/connection_state_provider.dart';
import 'package:kalinka/providers/server_info_provider.dart';
import 'package:kalinka/providers/supervisor_api.dart';
import 'package:kalinka/widgets/mini_player.dart';
import 'package:kalinka/widgets/now_playing_content.dart';
import 'package:kalinka/widgets/shell_navigation.dart';

import 'support/home_shell.dart';

class _Connected extends ConnectionStateNotifier {
  @override
  ConnectionStatus build() => ConnectionStatus.connected;
}

/// The rail alone, beside nothing, in a window of [size].
Future<void> _pumpRail(
  WidgetTester tester,
  Size size, {
  Future<List<CatalogSource>>? sources,
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        connectionStateProvider.overrideWith(_Connected.new),
        catalogSourcesProvider.overrideWith(
          (ref) => sources ?? Future.value(const <CatalogSource>[]),
        ),
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
                child: ShellNavigation(onNavigate: (_, _) {}, onAction: (_) {}),
              ),
              const Expanded(child: SizedBox()),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  // A follower above the shelf's controls left their tooltips, overlay
  // children themselves, no position to lay out from: an assertion on hover.
  testWidgets('More unfolds a shelf whose controls show their tooltips', (
    tester,
  ) async {
    // Too short for Change server to stand under the rest.
    await _pumpRail(tester, const Size(800, 300));
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

  // Measures were matched to items by place: sources arriving between two
  // took the places of items as tall as themselves, which had reported
  // already, so they counted for nothing and the rail ran past its foot.
  testWidgets('sources arriving late fold the rail rather than overrun it', (
    tester,
  ) async {
    final sources = Completer<List<CatalogSource>>();
    await _pumpRail(tester, const Size(800, 480), sources: sources.future);
    final more = find.byKey(const ValueKey('navigation-more'));
    expect(more, findsNothing);

    // In the test's font Jamendo wraps as Change server does and TIDAL does
    // not, as More does not: each as tall as the item whose place it takes.
    sources.complete([
      for (final (id, title) in [
        ('localfiles', 'My Library'),
        ('jamendo', 'Jamendo'),
        ('tidal', 'TIDAL'),
      ])
        (
          module: ModuleInfo(
            name: id,
            title: title,
            enabled: true,
            state: ModuleState.ready,
            capabilities: const [ModuleCapability.catalogs],
          ),
          root: BrowseItem(
            id: 'kalinka:$id:catalog:root',
            name: title,
            canBrowse: true,
            canAdd: false,
          ),
        ),
    ]);
    await tester.pumpAndSettle();
    expect(more, findsOneWidget);
    final rail = tester.state<ScrollableState>(find.byType(Scrollable));
    expect(rail.position.maxScrollExtent, 0);
    expect(tester.getRect(more).bottom, lessThanOrEqualTo(480));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a shelf too wide for the window runs on in more rows', (
    tester,
  ) async {
    // Room beside the rail for one item a row: Configuration and Change
    // server go behind More.
    await _pumpRail(tester, const Size(260, 300));
    await tester.tap(find.byKey(const ValueKey('navigation-more')));
    await tester.pumpAndSettle();
    final configuration = tester.getRect(
      find.byKey(const ValueKey('navigation-configuration')),
    );
    final changeServer = tester.getRect(
      find.byKey(const ValueKey('navigation-changeServer')),
    );
    expect(changeServer.left, configuration.left);
    expect(changeServer.top, greaterThanOrEqualTo(configuration.bottom));
    expect(changeServer.right, lessThanOrEqualTo(260));
    expect(changeServer.bottom, lessThanOrEqualTo(300));
    expect(tester.takeException(), isNull);
  });

  // The phone's player is a route above the one the shelf is drawn over, so
  // the shelf opened under it, out of sight and out of reach.
  testWidgets('More beside the open player unfolds a shelf within reach', (
    tester,
  ) async {
    // A small tablet held sideways: the phone's layout beside a rail too
    // short for Power off to stand under the rest.
    await pumpHomeShell(
      tester,
      queue: SettableQueue(queueOf(4)),
      size: const Size(1000, 480),
      overrides: [
        pluginCatalogEnabledProvider.overrideWithValue(true),
        boxControlProvider.overrideWith(
          (ref) async => const BoxControl(
            SupervisorInfo(
              version: '0.2.0',
              protocol: 1,
              minProtocol: 1,
              serverId: 'home-shell',
              actions: {'reboot', 'poweroff'},
            ),
            'home-shell',
          ),
        ),
      ],
    );
    await tester.pumpAndSettle();
    // The art opens the player; the bar's middle is its slider.
    await tester.tapAt(
      tester.getTopLeft(find.byType(MiniPlayer)) + const Offset(40, 36),
    );
    await tester.pumpAndSettle();
    expect(find.byType(NowPlayingContent), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('navigation-more')));
    await tester.pumpAndSettle();
    expect(find.byType(NowPlayingContent), findsNothing);
    await tester.tap(find.byKey(const ValueKey('navigation-powerOff')));
    await tester.pumpAndSettle();
    expect(find.text('Power off streamer?'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
