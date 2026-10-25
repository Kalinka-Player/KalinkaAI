// Fakes for a Raspberry Pi box whose supervisor sets its sound card and time
// zone up, and the server that box's renderer plays for.

import 'dart:async';

import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:kalinka/data_model/data_model.dart'
    show ModulesAndDevices, RendererInfo;
import 'package:kalinka/data_model/presentation_schema.dart';
import 'package:kalinka/data_model/renderer_config.dart';
import 'package:kalinka/providers/box_control_provider.dart';
import 'package:kalinka/providers/connection_settings_provider.dart';
import 'package:kalinka/providers/demo_mode.dart';
import 'package:kalinka/providers/kalinka_player_api_provider.dart';
import 'package:kalinka/providers/soundcard_provider.dart';
import 'package:kalinka/providers/supervisor_api.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Cards a Pi box offers, one of each kind the picker groups.
const soundcardOptions = [
  SoundcardOption(
    name: 'hifiberry-digi-pro',
    label: 'HiFiBerry Digi+ Pro or Digi2 Pro',
    vendor: 'HiFiBerry',
    kind: 'digital',
  ),
  SoundcardOption(
    name: 'justboom-dac',
    label: 'JustBoom DAC HAT',
    vendor: 'JustBoom',
    kind: 'dac',
  ),
  SoundcardOption(
    name: 'rpi-bcm2835-hdmi',
    label: 'Raspberry Pi HDMI',
    vendor: 'Raspberry Pi',
    kind: 'onboard',
  ),
  SoundcardOption(name: 'none', label: 'No HAT', kind: 'none'),
];

SoundcardReport soundcardReport({
  String? name,
  String? configured,
  String? pcm,
  List<String> usb = const [],
  List<String> suggested = const [],
}) => SoundcardReport(
  name: name,
  configured: configured,
  activePcm: pcm,
  usb: usb,
  suggested: suggested,
  options: soundcardOptions,
);

SupervisorInfo supervisorInfo({
  String? serverId = 'box-1',
  String? rendererId,
  Set<String> actions = const {'reboot', 'poweroff', setSoundcardAction},
}) => SupervisorInfo(
  version: '0.3.0',
  protocol: 1,
  minProtocol: 1,
  serverId: serverId,
  rendererId: rendererId,
  actions: actions,
);

/// A box that answers [answers] to `/info` in turn, the last one for good, and
/// [reports] to `/v1/soundcard` likewise. Both lists may be changed meanwhile.
class FakeBox implements SupervisorApi {
  FakeBox({
    List<SupervisorInfo?>? answers,
    List<SoundcardReport?>? reports,
    this.restarts = false,
  }) : answers = answers ?? [supervisorInfo(rendererId: 'r-local')],
       reports = reports ?? [soundcardReport()];

  final List<SupervisorInfo?> answers;
  final List<SoundcardReport?> reports;
  final bool restarts;
  BoxActionException? refusal;
  final applied = <(String, BoxIdentity)>[];

  /// What `/info` answers once a card is applied, in place of [answers].
  List<SupervisorInfo?>? answersAfterApply;

  /// While set, `/info` answers only once it completes.
  Completer<void>? holdInfo;

  /// While set, `/v1/soundcard` answers only once it completes.
  Completer<void>? holdReport;

  /// While set, `/info` throws it rather than answering.
  Object? fault;

  int infoReads = 0;
  int reportReads = 0;

  /// How a null answer in [answers] reads: nothing listening, or no answer.
  SupervisorReach noAnswer = SupervisorReach.absent;

  /// The zone `/v1/status` names; setting one changes it.
  String? zone = 'UTC';

  List<String>? zones = const ['Asia/Kolkata', 'Europe/London', 'UTC'];

  /// Old names the box sets the zone of, as its tzdata links them.
  Map<String, String> zoneLinks = const {'Asia/Calcutta': 'Asia/Kolkata'};

  final zonesSet = <(String, BoxIdentity)>[];

  /// While set, a time zone change answers only once it completes.
  Completer<void>? holdTimezone;

  /// While set, reading the zone answers only once it completes.
  Completer<void>? holdZone;

  /// While set, the list of zones answers only once it completes.
  Completer<void>? holdZones;

  T _next<T>(List<T> list) => list.length > 1 ? list.removeAt(0) : list.first;

  @override
  Future<SupervisorInfo?> info() async {
    infoReads++;
    await holdInfo?.future;
    if (fault case final fault?) throw fault;
    return _next(answers);
  }

  @override
  Future<({SupervisorReach reach, SupervisorInfo? info})> probe() async {
    final info = await this.info();
    return (
      reach: info == null ? noAnswer : SupervisorReach.answered,
      info: info,
    );
  }

  @override
  Future<SoundcardReport?> soundcard() async {
    reportReads++;
    await holdReport?.future;
    return _next(reports);
  }

  @override
  Future<bool> setSoundcard(String card, BoxIdentity identity) async {
    applied.add((card, identity));
    if (refusal != null) throw refusal!;
    if (answersAfterApply case final after?) {
      answers
        ..clear()
        ..addAll(after);
    }
    return restarts;
  }

  @override
  Future<String?> timezone() async {
    await holdZone?.future;
    return zone;
  }

  @override
  Future<List<String>?> timezones() async {
    await holdZones?.future;
    return zones;
  }

  @override
  Future<String> setTimezone(String zone, BoxIdentity identity) async {
    zonesSet.add((zone, identity));
    await holdTimezone?.future;
    if (refusal != null) throw refusal!;
    return this.zone = zoneLinks[zone] ?? zone;
  }

  @override
  Future<String?> serverState() async => 'active';

  @override
  Future<void> run(BoxAction action, {required String serverId}) async {}

  @override
  Uri get page => Uri.parse('http://kalinka.local:8001/');
}

class FakeProxy implements KalinkaPlayerProxy {
  FakeProxy(this.renderers);

  List<RendererInfo> renderers;
  final updates = <(String, Map<String, String>)>[];

  /// What the server saved of its settings, change set by change set.
  final saved = <Map<String, dynamic>>[];

  /// What every renderer reports of its own settings.
  RendererConfigSnapshot rendererConfig = const RendererConfigSnapshot();

  /// The renderers whose settings were read, in order.
  final configReads = <String>[];

  /// While set, a renderer settings write answers only once it completes.
  Completer<void>? holdUpdate;

  @override
  Future<PresentationSchema> getSettingsSchema() async =>
      const PresentationSchema(schemaVersion: 'v1', pages: []);

  @override
  Future<Map<String, dynamic>> getSettings() async => {
    'schema_version': 'v1',
    'values': <String, dynamic>{},
  };

  @override
  Future<List<ConfigIssue>> validateSettings({
    required String schemaVersion,
    required Map<String, dynamic> changes,
  }) async => const [];

  @override
  Future<Set<String>?> saveSettings({
    required String schemaVersion,
    required Map<String, dynamic> changes,
  }) async {
    saved.add(changes);
    return null;
  }

  @override
  Future<RendererConfigSnapshot> getRendererConfig(String rendererId) async {
    configReads.add(rendererId);
    return rendererConfig;
  }

  @override
  Future<ModulesAndDevices> listModules() async =>
      ModulesAndDevices(inputModules: [], devices: []);

  @override
  Future<List<RendererInfo>> listRenderers() async => renderers;

  @override
  Future<RendererConfigResult> updateRendererConfig(
    String rendererId,
    Map<String, String> changes,
  ) async {
    updates.add((rendererId, changes));
    await holdUpdate?.future;
    return const RendererConfigResult();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

RendererInfo rendererRow(
  String id, {
  String? address,
  String status = 'connected',
}) => RendererInfo(
  rendererId: id,
  friendlyName: id,
  status: status,
  address: address,
);

/// Preferences naming the server at kalinka.local:8000, plus [extra].
Future<SharedPreferences> boxPrefs([Map<String, Object> extra = const {}]) {
  SharedPreferences.setMockInitialValues({
    'Kalinka.host': 'kalinka.local',
    'Kalinka.port': 8000,
    ...extra,
  });
  return SharedPreferences.getInstance();
}

/// The server's own box is [box], with its supervisor; [others] answer at the
/// addresses other renderers connected from.
List<Override> soundcardOverrides(
  SharedPreferences prefs, {
  required FakeBox box,
  FakeProxy? proxy,
  Map<String, SupervisorApi> others = const {},
}) => [
  sharedPrefsProvider.overrideWithValue(prefs),
  supervisorApiProvider.overrideWithValue(box),
  supervisorAtProvider.overrideWith((ref, host) => others[host]!),
  serverIdentityProvider.overrideWith((ref) async => 'box-1'),
  demoModeProvider.overrideWithValue(false),
  kalinkaProxyProvider.overrideWithValue(proxy ?? FakeProxy([])),
  soundcardPollProvider.overrideWithValue(Duration.zero),
];
