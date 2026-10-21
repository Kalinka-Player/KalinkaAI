import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kalinka/data_model/data_model.dart';
import 'package:kalinka/data_model/ext_device_events.dart';
import 'package:kalinka/data_model/playqueue_events.dart';
import 'package:kalinka/providers/app_state_provider.dart';
import 'package:kalinka/providers/bit_perfect_provider.dart';
import 'package:kalinka/providers/connection_state_provider.dart';
import 'package:kalinka/providers/playback_time_provider.dart';
import 'package:kalinka/providers/renderer_provider.dart';
import 'package:kalinka/providers/source_modules_provider.dart';
import 'package:kalinka/providers/url_resolver.dart';
import 'package:kalinka/widgets/now_playing_content.dart';
import 'package:kalinka/widgets/player_header.dart';
import 'package:kalinka/widgets/renderer_switcher.dart';
import 'package:kalinka/widgets/volume_control_slider.dart';

// In stacked layouts, the output sits under transport on the phone sheet and
// docked player alike. Neither header carries one; volume lives in the picker.

class _Queue extends PlayQueueStateStore {
  @override
  PlayQueueState build() => PlayQueueState(
    playbackState: PlaybackState(index: 0, state: PlayerStateType.playing),
    trackList: [Track(id: 't', title: 'Song', duration: 200)],
    playbackMode: PlaybackMode.empty,
    seq: 1,
  );
}

class _Device extends ExtDeviceStateStore {
  @override
  ExtDeviceState build() => ExtDeviceState(
    powerOn: true,
    volume: DeviceVolume(
      currentVolume: 40,
      maxVolume: 100,
      volumeGain: 0,
      supported: true,
    ),
    seq: 0,
  );
}

class _Time extends PlaybackTimeMsNotifier {
  @override
  int build() => 0;
}

class _Renderers extends RendererListNotifier {
  @override
  RendererListState build() => const RendererListState(
    loaded: true,
    renderers: [
      RendererInfo(
        rendererId: 'smsl',
        friendlyName: 'SMSL SU-1',
        status: 'connected',
        active: true,
      ),
    ],
  );
}

class _Connected extends ConnectionStateNotifier {
  @override
  ConnectionStatus build() => ConnectionStatus.connected;
}

Future<void> _pump(WidgetTester tester, {required bool docked}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.5;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        playQueueStateStoreProvider.overrideWith(_Queue.new),
        extDeviceStateStoreProvider.overrideWith(_Device.new),
        playbackTimeMsProvider.overrideWith(_Time.new),
        connectionStateProvider.overrideWith(_Connected.new),
        rendererListProvider.overrideWith(_Renderers.new),
        urlResolverProvider.overrideWithValue(UrlResolver('')),
        bitPerfectProvider.overrideWithValue(false),
        sourceModulesProvider.overrideWith((ref) => const <ModuleInfo>[]),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: NowPlayingContent(
            isTablet: docked,
            showOverlayHeader: !docked,
            onClose: () {},
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  for (final docked in [false, true]) {
    testWidgets('${docked ? 'docked' : 'phone'} player says its output under '
        'the transport, and nowhere above', (tester) async {
      await _pump(tester, docked: docked);

      final output = find.byType(RendererSwitcherDropdown);
      expect(output, findsOneWidget);
      expect(tester.widget<RendererSwitcherDropdown>(output).framed, isTrue);
      expect(find.text('SMSL SU-1'), findsOneWidget);
      expect(
        tester.getRect(output).top,
        greaterThan(
          tester.getRect(find.byIcon(Icons.skip_next_rounded)).bottom,
        ),
      );
      expect(
        find.descendant(
          of: find.byType(PlayerHeader),
          matching: find.byType(RendererSwitcherButton),
        ),
        findsNothing,
      );
      expect(find.byType(NowPlayingVolumeControl), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
