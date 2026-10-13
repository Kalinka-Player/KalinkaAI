import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kalinka/providers/connection_settings_provider.dart';
import 'package:kalinka/providers/connection_state_provider.dart';
import 'package:kalinka/theme/app_theme.dart';
import 'package:kalinka/widgets/settings_top_bar.dart';
import 'package:kalinka/widgets/slide_in_panel.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Connected extends ConnectionStateNotifier {
  @override
  ConnectionStatus build() => ConnectionStatus.connected;
}

Future<void> _open(
  WidgetTester tester, {
  required Size size,
  double scale = 1,
  bool reducedMotion = false,
  required VoidCallback onBack,
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        connectionStateProvider.overrideWith(_Connected.new),
      ],
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: MediaQuery(
          data: MediaQueryData(
            size: size,
            textScaler: TextScaler.linear(scale),
            disableAnimations: reducedMotion,
          ),
          child: Scaffold(
            body: SlideInPanel(
              onClose: onBack,
              child: Column(
                children: [
                  SettingsTopBar(
                    title: 'Living room music library settings',
                    action: IconButton(
                      tooltip: 'About this library',
                      onPressed: () {},
                      icon: const Icon(Icons.info_outline),
                    ),
                  ),
                  Expanded(
                    child: ListView(
                      children: [
                        for (var i = 0; i < 30; i++)
                          SizedBox(height: 60, child: Text('Setting $i')),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  for (final (size, scale) in [
    (const Size(320, 700), 2.0),
    (const Size(375, 812), 1.0),
    (const Size(375, 812), 3.2),
    (const Size(812, 375), 2.0),
    (const Size(540, 850), 2.0),
  ]) {
    testWidgets('title remains readable and Back usable at $size / $scale', (
      tester,
    ) async {
      var closed = false;
      await _open(
        tester,
        size: size,
        scale: scale,
        onBack: () => closed = true,
      );
      await tester.pumpAndSettle();
      final title = find.text('Living room music library settings');
      final bar = find.byType(SettingsTopBar);
      expect(title, findsOneWidget);
      expect(
        tester.getRect(bar).contains(tester.getRect(title).bottomRight),
        isTrue,
      );
      expect(tester.widget<Text>(title).maxLines, isNull);
      expect(tester.getSize(find.byTooltip('Back')), const Size(48, 48));
      expect(
        find.byTooltip('About this library').hitTestable(),
        findsOneWidget,
      );
      final position = tester.getRect(bar);
      await tester.drag(find.byType(ListView), const Offset(0, -200));
      await tester.pumpAndSettle();
      expect(tester.getRect(bar), position);
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(closed, isTrue);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('keyboard Back and reduced motion work without a slide', (
    tester,
  ) async {
    var closed = false;
    await _open(
      tester,
      size: const Size(375, 812),
      reducedMotion: true,
      onBack: () => closed = true,
    );
    await tester.pump();
    expect(tester.getTopLeft(find.byType(SettingsTopBar)).dx, 0);
    final semantics = tester.ensureSemantics();
    expect(
      tester.getSemantics(find.text('Living room music library settings')),
      matchesSemantics(
        label: 'Living room music library settings',
        isHeader: true,
      ),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(closed, isTrue);
    semantics.dispose();
    expect(tester.takeException(), isNull);
  });
}
