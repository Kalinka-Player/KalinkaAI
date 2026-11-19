import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kalinka/providers/connection_settings_provider.dart';
import 'package:kalinka/providers/display_settings_provider.dart';
import 'package:kalinka/widgets/clock_format_host.dart';
import 'package:kalinka/widgets/kiosk/kiosk_clock.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _evening = DateTime(2026, 11, 19, 21, 41);

/// Stands for the app's unkeyed hosts, which sit directly under the clock's.
class _Remembered extends StatefulWidget {
  final Widget child;

  const _Remembered({required this.child});

  @override
  State<_Remembered> createState() => _RememberedState();
}

class _RememberedState extends State<_Remembered> {
  @override
  Widget build(BuildContext context) => widget.child;
}

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  bool? saved,
  bool platform24Hour = false,
}) async {
  SharedPreferences.setMockInitialValues({
    Use24HourClockNotifier.preferenceKey: ?saved,
  });
  final container = ProviderContainer(
    overrides: [
      sharedPrefsProvider.overrideWithValue(
        await SharedPreferences.getInstance(),
      ),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      // The app's own MediaQuery takes the platform's preference from here.
      child: MediaQuery(
        data: MediaQueryData(alwaysUse24HourFormat: platform24Hour),
        child: MaterialApp(
          builder: (_, child) =>
              ClockFormatHost(child: _Remembered(child: child!)),
          home: Builder(
            builder: (context) => Text(KioskClock.time(context, _evening)),
          ),
        ),
      ),
    ),
  );
  return container;
}

void main() {
  for (final (saved, platform24Hour, shown) in const [
    (null, false, '9:41 PM'),
    (null, true, '21:41'),
    (true, false, '21:41'),
    (false, true, '9:41 PM'),
  ]) {
    testWidgets('saved $saved on a platform preferring 24-hour $platform24Hour '
        'shows $shown', (tester) async {
      await _pump(tester, saved: saved, platform24Hour: platform24Hour);
      expect(find.text(shown), findsOneWidget);
    });
  }

  testWidgets('a first choice reformats the time without remounting the app', (
    tester,
  ) async {
    final container = await _pump(tester);
    final before = tester.state(find.byType(_Remembered));
    await container.read(use24HourClockProvider.notifier).set(true);
    await tester.pump();
    expect(find.text('21:41'), findsOneWidget);
    expect(tester.state(find.byType(_Remembered)), same(before));
  });
}
