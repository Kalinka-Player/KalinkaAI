import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kalinka/providers/connection_settings_provider.dart';
import 'package:kalinka/providers/onboarding_provider.dart';
import 'package:kalinka/providers/renderer_settings_route_provider.dart';
import 'package:kalinka/screens/music_player_screen.dart';
import 'package:kalinka/screens/renderer_settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

// The renderer settings panel sits in the phone layout's Stack and in the
// tablet layout's left panel. A resize across the breakpoint has to move it,
// not remount it: a remount reloads the page and drops staged edits.

Future<void> _resize(WidgetTester tester, Size size) async {
  await tester.binding.setSurfaceSize(size);
  await tester.pump();
  // The outgoing layout overflows a Row by a few pixels on its last frame
  // (test fonts only; see discovery_resize_test).
  final exception = tester.takeException();
  if (exception != null) {
    expect('$exception', contains('RenderFlex overflowed'));
  }
}

void main() {
  testWidgets('renderer settings survive resizes across the breakpoint', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      OnboardingStatusNotifier.sharedPrefOobeComplete: true,
    });
    final prefs = await SharedPreferences.getInstance();
    await tester.binding.setSurfaceSize(const Size(400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
        child: const MaterialApp(home: MusicPlayerScreen()),
      ),
    );
    await tester.pump();

    ProviderScope.containerOf(tester.element(find.byType(MusicPlayerScreen)))
        .read(rendererSettingsRouteProvider.notifier)
        .open('living-room', 'Living Room');
    await tester.pump(const Duration(milliseconds: 500));

    final panel = tester.state(find.byType(RendererSettingsScreen));
    await _resize(tester, const Size(1280, 800));
    expect(tester.state(find.byType(RendererSettingsScreen)), same(panel));
    await _resize(tester, const Size(400, 800));
    expect(tester.state(find.byType(RendererSettingsScreen)), same(panel));

    // Let the discovery scan's timers elapse so none are pending at teardown.
    await tester.pump(const Duration(seconds: 6));
  });
}
