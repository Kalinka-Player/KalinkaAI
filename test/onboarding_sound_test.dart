// The setup wizard's Sound step sets up the sound card of the Pi the chosen
// output plays on, follows the Pi through the restart that takes, asks before
// moving on while a card it found does not play, and carries on at the same
// step when the app lost the run meanwhile.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kalinka/data_model/data_model.dart' show RendererInfo;
import 'package:kalinka/data_model/renderer_config.dart';
import 'package:kalinka/providers/connection_settings_provider.dart';
import 'package:kalinka/providers/onboarding_provider.dart';
import 'package:kalinka/providers/renderer_host_provider.dart';
import 'package:kalinka/renderer/renderer_identity.dart';
import 'package:kalinka/providers/renderer_provider.dart';
import 'package:kalinka/providers/settings_provider.dart';
import 'package:kalinka/providers/supervisor_api.dart';
import 'package:kalinka/providers/toast_provider.dart';
import 'package:kalinka/screens/onboarding_screen.dart';
import 'package:kalinka/widgets/onboarding/step_sound.dart';
import 'package:kalinka/widgets/soundcard_row.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/soundcard_fakes.dart';

class _Outputs extends RendererListNotifier {
  @override
  RendererListState build() => const RendererListState(
    renderers: [
      RendererInfo(
        rendererId: 'r-local',
        friendlyName: 'Living room',
        status: 'connected',
        active: true,
      ),
    ],
    loaded: true,
  );

  @override
  Future<void> refresh() async {}
}

/// The output's own settings: just the device, the way a Pi renderer lists it.
final _deviceConfig = RendererConfigSnapshot.fromJson(
  jsonDecode('''
{"config_version":"1","sections":[{"path":"output","title":"Output",
 "description":"","fields":[
  {"path":"output.device","title":"Device","description":"","type":"enum",
   "value":"default","default":"default",
   "options":[{"value":"default","label":"System default","description":""},
              {"value":"hw:CARD=sndrpihifiberry,DEV=0",
               "label":"HiFiBerry DAC+","description":""}],
   "apply":"interrupts_playback","read_only":false,"importance":"simple"}]}]}
''') as Map<String, dynamic>,
);

final _found = soundcardReport(
  name: 'HiFiBerry Digi2 Pro',
  suggested: ['hifiberry-digi-pro'],
);

final _playing = soundcardReport(
  name: 'HiFiBerry Digi2 Pro',
  configured: 'hifiberry-digi-pro',
  pcm: 'hw:CARD=sndrpihifiberry,DEV=0',
);

/// Where a run stood when the Pi restarted, for the server at [host].
String _resumeAt(int step, {String host = 'kalinka.local'}) => jsonEncode({
  'name': 'Kalinka',
  'scheme': 'http',
  'host': host,
  'port': 8000,
  'step': step,
});

Future<ProviderContainer> _pump(
  WidgetTester tester,
  Widget child, {
  required FakeBox box,
  FakeProxy? proxy,
  SharedPreferences? prefs,
  bool loadSettings = true,
}) async {
  final api = (proxy ?? FakeProxy([]))..rendererConfig = _deviceConfig;
  final container = ProviderContainer(
    overrides: [
      ...soundcardOverrides(prefs ?? await boxPrefs(), box: box, proxy: api),
      rendererListProvider.overrideWith(_Outputs.new),
      rendererIdentityProvider.overrideWith(
        (ref) => Completer<RendererIdentity>().future,
      ),
    ],
  );
  addTearDown(container.dispose);
  if (loadSettings) {
    await container.read(settingsProvider.notifier).loadConfig();
  }
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(home: child),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

/// Lets the toasts and the staged-settings check run out.
Future<void> _drain(WidgetTester tester) =>
    tester.pump(const Duration(seconds: 6));

void main() {
  group('the step', () {
    Widget step({SetUpSoundcard? onSetUp}) => Scaffold(
      body: SingleChildScrollView(
        child: OnboardingSoundStep(
          soundcardHost: SoundcardHost(
            setUp: onSetUp ?? (_, _) {},
            confirmNote: 'Setup carries on here.',
          ),
        ),
      ),
    );

    testWidgets('sets up the card it found, once asked', (tester) async {
      final chosen = <String>[];
      await _pump(
        tester,
        step(onSetUp: (_, card) => chosen.add(card.name)),
        box: FakeBox(reports: [_found]),
      );

      expect(find.textContaining('was found but is not set up'), findsOne);
      await tester.tap(find.text('Set it up'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Setup carries on here.'), findsOne);
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();

      expect(chosen, ['hifiberry-digi-pro']);
    });

    testWidgets('offers every card for a board it could not name', (
      tester,
    ) async {
      final chosen = <String>[];
      await _pump(
        tester,
        step(onSetUp: (_, card) => chosen.add(card.name)),
        box: FakeBox(
          reports: [
            soundcardReport(suggested: ['hifiberry-digi-pro', 'justboom-dac']),
          ],
        ),
      );

      await tester.tap(find.text('Choose a card'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('JustBoom DAC HAT').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();

      expect(chosen, ['justboom-dac']);
    });

    testWidgets('names the card that plays and switches the device on the '
        'spot', (tester) async {
      final proxy = FakeProxy([]);
      await _pump(
        tester,
        step(),
        box: FakeBox(reports: [_playing]),
        proxy: proxy,
      );

      expect(find.text('HiFiBerry Digi2 Pro'), findsOne);
      expect(find.textContaining('was found'), findsNothing);
      expect(find.text('All output settings'), findsNothing);
      await tester.tap(find.text('System default'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('HiFiBerry DAC+'));
      await tester.pumpAndSettle();

      final (renderer, changes) = proxy.updates.single;
      expect(renderer, 'r-local');
      expect(changes, {'output.device': 'hw:CARD=sndrpihifiberry,DEV=0'});
    });

    testWidgets('an output on a box that cannot set a card up has the test '
        'alone', (tester) async {
      await _pump(
        tester,
        step(),
        box: FakeBox(
          answers: [
            SupervisorInfo(
              version: '0.3.0',
              protocol: 1,
              minProtocol: 1,
              serverId: 'box-1',
              rendererId: 'r-local',
              actions: const {'reboot'},
            ),
          ],
        ),
      );

      expect(find.text('SOUND CARD'), findsNothing);
      expect(find.text('Play test sound'), findsOne);
    });
  });

  group('the wizard', () {
    Future<ProviderContainer> atSoundStep(
      WidgetTester tester,
      FakeBox box, {
      FakeProxy? proxy,
    }) async {
      final container = await _pump(
        tester,
        const OnboardingScreen(startAtSetup: true),
        box: box,
        proxy: proxy,
        prefs: await boxPrefs({OobeResumeNotifier.sharedPref: _resumeAt(5)}),
      );
      expect(find.text('Sound'), findsOne);
      return container;
    }

    testWidgets('carries on at the step a lost run stood at', (tester) async {
      final container = await atSoundStep(tester, FakeBox());

      expect(container.read(oobeResumeProvider), isNull);
      expect(
        container
            .read(sharedPrefsProvider)
            .containsKey(OobeResumeNotifier.sharedPref),
        isFalse,
      );
    });

    testWidgets('starts from the top for a run on another server', (
      tester,
    ) async {
      await _pump(
        tester,
        const OnboardingScreen(startAtSetup: true),
        box: FakeBox(),
        prefs: await boxPrefs({
          OobeResumeNotifier.sharedPref: _resumeAt(5, host: '10.0.0.9'),
        }),
      );

      expect(find.text('Network'), findsOne);
    });

    testWidgets('asks before leaving a card it found silent', (tester) async {
      await atSoundStep(tester, FakeBox(reports: [_found]));

      await tester.tap(find.text('Skip for now'));
      await tester.pumpAndSettle();
      expect(find.text('The sound card is not playing'), findsOne);
      await tester.tap(find.text('Continue anyway'));
      await tester.pumpAndSettle();

      expect(find.text('Almost there'), findsOne);
      expect(find.text('Sound card'), findsOne);
      expect(find.textContaining('was found but is not set up'), findsOne);
    });

    testWidgets('leaves the output’s other settings for later', (tester) async {
      await atSoundStep(tester, FakeBox(reports: [_playing]));

      await tester.tap(find.text('Back'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Back'));
      await tester.pumpAndSettle();

      expect(find.text('Audio output'), findsOne);
      expect(find.text('Living room'), findsOne);
      expect(find.byIcon(Icons.settings_outlined), findsNothing);
    });

    testWidgets('moves on without asking once the card plays', (tester) async {
      await atSoundStep(tester, FakeBox(reports: [_playing]));

      await tester.tap(find.text('Skip for now'));
      await tester.pumpAndSettle();

      expect(find.text('Almost there'), findsOne);
    });

    testWidgets('follows the Pi through its restart and stays on the step', (
      tester,
    ) async {
      final box = FakeBox(reports: [_found], restarts: true)
        ..answersAfterApply = [null];
      final proxy = FakeProxy([rendererRow('r-local')]);
      final container = await atSoundStep(tester, box, proxy: proxy);
      container
          .read(settingsProvider.notifier)
          .stageChange('base_config.server.service_name', 'Den');
      final reads = proxy.configReads.length;

      await tester.tap(find.text('Set it up'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();

      // Saved and remembered before the Pi went down, which it stays.
      expect(proxy.saved.single, {'base_config.server.service_name': 'Den'});
      expect(container.read(oobeResumeProvider)?.step, 6);
      expect(find.text('The streamer is not back yet'), findsOne);
      expect(proxy.configReads, hasLength(reads));

      box.answers
        ..clear()
        ..add(supervisorInfo(rendererId: 'r-local'));
      box.reports
        ..clear()
        ..add(_playing);
      await tester.tap(find.text('Keep waiting'));
      await tester.pumpAndSettle();

      expect(find.text('The streamer is not back yet'), findsNothing);
      expect(find.text('Sound'), findsOne);
      expect(proxy.updates.single.$2, {
        'output.device': 'hw:CARD=sndrpihifiberry,DEV=0',
      });
      expect(proxy.configReads, hasLength(reads + 1));
      expect(container.read(oobeResumeProvider), isNull);
      expect(
        container.read(toastProvider).last.message,
        'The streamer is back, playing through HiFiBerry Digi2 Pro.',
      );
      await _drain(tester);
    });

    testWidgets('covers the wizard while the Pi restarts', (tester) async {
      final box = FakeBox(reports: [_found], restarts: true)
        ..answersAfterApply = [null, supervisorInfo(rendererId: 'r-local')];
      await atSoundStep(
        tester,
        box,
        proxy: FakeProxy([rendererRow('r-local')]),
      );
      final restart = box.holdInfo = Completer<void>();

      await tester.tap(find.text('Set it up'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();

      expect(find.text('Restarting the streamer'), findsWidgets);
      expect(find.text('The streamer’s boot settings'), findsOne);
      expect(
        find.text('Playing through HiFiBerry Digi+ Pro or Digi2 Pro'),
        findsOne,
      );
      expect(find.text('Skip for now'), findsOne);

      box.reports
        ..clear()
        ..add(_playing);
      restart.complete();
      await tester.pumpAndSettle();

      expect(find.text('Restarting the streamer'), findsNothing);
      expect(find.text('Sound'), findsOne);
      await _drain(tester);
    });

    testWidgets('lets setup go on without a Pi that is not back', (
      tester,
    ) async {
      final box = FakeBox(reports: [_found], restarts: true)
        ..answersAfterApply = [null];
      final proxy = FakeProxy([]);
      final container = await atSoundStep(tester, box, proxy: proxy);
      final reads = proxy.configReads.length;

      await tester.tap(find.text('Set it up'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue setup'));
      await tester.pumpAndSettle();

      expect(find.text('The streamer is not back yet'), findsNothing);
      expect(find.text('Sound'), findsOne);
      expect(proxy.configReads, hasLength(reads + 1));
      expect(container.read(oobeResumeProvider), isNull);
      await _drain(tester);
    });

    testWidgets('reconnects a lost run to its server on the next launch', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({
        OobeResumeNotifier.sharedPref: _resumeAt(5),
      });
      final container = await _pump(
        tester,
        const OnboardingScreen(),
        box: FakeBox(),
        prefs: await SharedPreferences.getInstance(),
        loadSettings: false,
      );

      expect(find.text('Sound'), findsOne);
      expect(container.read(oobeResumeProvider), isNull);
    });
  });
}
