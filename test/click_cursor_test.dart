import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kalinka/theme/app_theme.dart';
import 'package:kalinka/widgets/home/catalog_tile.dart';
import 'package:kalinka/widgets/tap_highlight.dart';
import 'package:kalinka/widgets/transport_button.dart';

void main() {
  final controls = <String, Widget Function(VoidCallback?)>{
    'text button': (tap) =>
        TextButton(onPressed: tap, child: const Text('Open')),
    'outlined button': (tap) =>
        OutlinedButton(onPressed: tap, child: const Text('Open')),
    'filled button': (tap) =>
        FilledButton(onPressed: tap, child: const Text('Open')),
    'elevated button': (tap) =>
        ElevatedButton(onPressed: tap, child: const Text('Open')),
    'icon button with local style': (tap) => IconButton(
      onPressed: tap,
      style: kalinkaIconButtonStyle,
      icon: const Icon(Icons.settings),
    ),
    'transport': (tap) => TransportButton(
      onTap: tap,
      hitDiameter: 48,
      child: const Icon(Icons.play_arrow),
    ),
    'source tile including its inner ListTile': (tap) =>
        CatalogTile(title: 'My Library', icon: Icons.library_music, onTap: tap),
    'list tile': (tap) => ListTile(onTap: tap, title: const Text('Open')),
  };

  for (final entry in controls.entries) {
    testWidgets('${entry.key} uses a hand only while clickable on Linux', (
      tester,
    ) async {
      var taps = 0;
      Future<void> pump(bool enabled) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 250,
                  child: entry.value(enabled ? () => taps++ : null),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      await pump(true);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      final center = tester.getCenter(find.byType(Scaffold));
      await mouse.moveTo(center);
      await tester.pump();
      expect(
        tester.binding.mouseTracker.debugDeviceActiveCursor(1),
        SystemMouseCursors.click,
      );
      await mouse.down(center);
      await mouse.up();
      await tester.pumpAndSettle();
      expect(taps, 1);

      // Changing availability must update a stationary pointer too.
      await pump(false);
      expect(
        tester.binding.mouseTracker.debugDeviceActiveCursor(1),
        SystemMouseCursors.basic,
      );
      await mouse.down(center);
      await mouse.up();
      await tester.pumpAndSettle();
      expect(taps, 1);

      await pump(true);
      expect(
        tester.binding.mouseTracker.debugDeviceActiveCursor(1),
        SystemMouseCursors.click,
      );
    }, variant: TargetPlatformVariant({TargetPlatform.linux}));
  }
}
