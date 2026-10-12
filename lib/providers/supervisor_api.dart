import 'package:dio/dio.dart' show Dio, DioException, Options;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'connection_settings_provider.dart';
import 'kalinka_player_api_provider.dart' show kalinkaHttpClient;

/// Where a Kalinka box's supervisor listens: beside the server on a port of
/// its own, so it still answers when the server does not.
const supervisorPort = 8001;

/// The control protocol this app speaks.
const _protocol = 1;

/// The action that sets a Raspberry Pi box up for its sound card. It takes a
/// card, so it is no [BoxAction].
const setSoundcardAction = 'set_soundcard';

/// How long a box may take to write its boot configuration for a new card;
/// the supervisor gives up after 90 seconds.
const _soundcardTimeout = Duration(seconds: 100);

/// What the box's supervisor can be asked to do, by its name in the API.
enum BoxAction {
  restartServer('restart_core'),
  reboot('reboot'),
  powerOff('poweroff');

  const BoxAction(this.wire);

  final String wire;
}

/// The supervisor's `GET /info`.
class SupervisorInfo {
  final String version;
  final int protocol;
  final int minProtocol;

  /// Identity of the server on the same box; null until that server first ran.
  final String? serverId;

  /// Identity of the renderer on the same box, the id the server lists it
  /// under; null on a box without one, or a supervisor too old to say.
  final String? rendererId;

  final Set<String> actions;

  const SupervisorInfo({
    required this.version,
    required this.protocol,
    required this.minProtocol,
    required this.serverId,
    this.rendererId,
    required this.actions,
  });

  /// Whether this app and the supervisor share a protocol version.
  bool get compatible => protocol >= _protocol && minProtocol <= _protocol;

  bool offers(BoxAction action) => actions.contains(action.wire);

  /// Whether the box is a Raspberry Pi whose sound card it can set up.
  bool get setsSoundcard => actions.contains(setSoundcardAction);

  /// Null when [json] is not a supervisor's answer.
  static SupervisorInfo? fromJson(Object? json) {
    if (json is! Map || json['name'] != 'kalinka-supervisor') return null;
    final protocol = json['protocol'];
    final minProtocol = json['min_protocol'];
    final actions = json['actions'];
    if (protocol is! int || minProtocol is! int || actions is! List) {
      return null;
    }
    String? id(Object? value) =>
        value is String && value.isNotEmpty ? value : null;
    return SupervisorInfo(
      version: json['version']?.toString() ?? '',
      protocol: protocol,
      minProtocol: minProtocol,
      serverId: id(json['server_id']),
      rendererId: id(json['renderer_id']),
      actions: actions.whereType<String>().toSet(),
    );
  }
}

/// Names the box an action is for, so one that took over the address refuses
/// it: by its server where it runs one, by its renderer otherwise.
class BoxIdentity {
  final String? serverId;
  final String? rendererId;

  const BoxIdentity({this.serverId, this.rendererId});

  Map<String, String> toJson() => {
    'server_id': ?serverId,
    'renderer_id': ?rendererId,
  };

  @override
  bool operator ==(Object other) =>
      other is BoxIdentity &&
      other.serverId == serverId &&
      other.rendererId == rendererId;

  @override
  int get hashCode => Object.hash(serverId, rendererId);
}

/// One card a box can be set up for.
class SoundcardOption {
  final String name;
  final String label;

  /// The board's maker; empty for the Pi's own outputs and for no HAT.
  final String vendor;

  /// `dac`, `digital`, `amp`, `onboard` or `none`.
  final String kind;

  const SoundcardOption({
    required this.name,
    required this.label,
    this.vendor = '',
    required this.kind,
  });

  static SoundcardOption? fromJson(Object? json) {
    if (json is! Map) return null;
    final name = json['name'];
    final label = json['label'];
    if (name is! String || label is! String) return null;
    return SoundcardOption(
      name: name,
      label: label,
      vendor: json['vendor']?.toString() ?? '',
      kind: json['kind']?.toString() ?? '',
    );
  }
}

/// What a box knows about its sound card, from its supervisor's
/// `GET /v1/soundcard`.
class SoundcardReport {
  /// The DAC as a person would call it, or null when the box knows none.
  final String? name;

  /// The card the boot configuration sets up, else the one the firmware sets
  /// up from the HAT's ID chip, or null.
  final String? configured;

  /// The ALSA device the renderer opens the card that came up by, or null
  /// while none is up.
  final String? activePcm;

  /// The USB DACs plugged in, by name; they play with nothing set up here.
  final List<String> usb;

  /// The cards the hardware points to, most likely first.
  final List<String> suggested;

  final List<SoundcardOption> options;

  const SoundcardReport({
    this.name,
    this.configured,
    this.activePcm,
    this.usb = const [],
    this.suggested = const [],
    required this.options,
  });

  SoundcardOption? option(String? name) =>
      options.where((o) => o.name == name).firstOrNull;

  /// Null for a box that is no Raspberry Pi, or an answer that is no report.
  static SoundcardReport? fromJson(Object? json) {
    if (json is! Map || json['supported'] != true) return null;
    final options = json['options'];
    if (options is! List) return null;
    final active = json['active'];
    final usb = json['usb'];
    final suggested = json['suggested'];
    return SoundcardReport(
      name: json['name'] is String ? json['name'] as String : null,
      configured: json['configured'] is String
          ? json['configured'] as String
          : null,
      activePcm: active is Map && active['pcm'] is String
          ? active['pcm'] as String
          : null,
      usb: [
        if (usb is List)
          for (final card in usb)
            if (card is Map && card['name'] is String) card['name'] as String,
      ],
      suggested: suggested is List
          ? suggested.whereType<String>().toList()
          : const [],
      options: options.map(SoundcardOption.fromJson).nonNulls.toList(),
    );
  }
}

/// The supervisor refused an action; [message] is fit to show.
class BoxActionException implements Exception {
  final String code;
  final String message;

  const BoxActionException(this.code, this.message);

  @override
  String toString() => message;
}

/// The box's supervisor on the connected server's host.
///
/// Every call throws [BoxActionException] when the box refuses or cannot be
/// reached; the message is written for the person who asked.
abstract class SupervisorApi {
  /// Null when nothing there answers as a supervisor: none is installed, it
  /// predates this API, or the box is unreachable.
  Future<SupervisorInfo?> info();

  /// The server's service state as systemd reports it, such as `active`,
  /// `activating` or `failed`; null when the box does not answer.
  Future<String?> serverState();

  /// Returns once the box has accepted [action]. [serverId] must be the one
  /// [info] reported, so a box that took over the address refuses it.
  Future<void> run(BoxAction action, {required String serverId});

  /// What the box knows about its sound card; null when it has none to set
  /// up, or does not answer.
  Future<SoundcardReport?> soundcard();

  /// Sets the box up for [card] and returns whether it now restarts to load
  /// it. Returns once the box has written its boot configuration.
  Future<bool> setSoundcard(String card, BoxIdentity identity);

  /// The supervisor's own page, for a browser.
  Uri get page;
}

class DioSupervisorApi implements SupervisorApi {
  DioSupervisorApi(this._client);

  final Dio _client;

  @override
  Uri get page => Uri.parse(_client.options.baseUrl).resolve('/');

  @override
  Future<SupervisorInfo?> info() async {
    try {
      return SupervisorInfo.fromJson((await _client.get('/info')).data);
    } on DioException {
      return null;
    }
  }

  @override
  Future<String?> serverState() async {
    try {
      final data = (await _client.get('/v$_protocol/status')).data;
      final core = data is Map ? data['core'] : null;
      return core is String ? core : null;
    } on DioException {
      return null;
    }
  }

  @override
  Future<void> run(BoxAction action, {required String serverId}) =>
      _act(action.wire, BoxIdentity(serverId: serverId).toJson());

  @override
  Future<SoundcardReport?> soundcard() async {
    try {
      return SoundcardReport.fromJson(
        (await _client.get('/v$_protocol/soundcard')).data,
      );
    } on DioException {
      return null;
    }
  }

  @override
  Future<bool> setSoundcard(String card, BoxIdentity identity) async {
    final reply = await _act(setSoundcardAction, {
      ...identity.toJson(),
      'soundcard': card,
    }, receiveTimeout: _soundcardTimeout);
    return reply is Map && reply['reboot'] == true;
  }

  Future<Object?> _act(
    String action,
    Map<String, String> body, {
    Duration? receiveTimeout,
  }) async {
    try {
      final response = await _client.post(
        '/v$_protocol/actions/$action',
        data: body,
        options: Options(receiveTimeout: receiveTimeout),
      );
      return response.data;
    } on DioException catch (e) {
      final response = e.response;
      if (response == null) {
        throw const BoxActionException(
          'unreachable',
          'The streamer did not answer. Check that it is on and connected.',
        );
      }
      final detail = response.data is Map ? response.data['detail'] : null;
      final code = detail is Map ? detail['code']?.toString() : null;
      throw BoxActionException(code ?? 'error', _refusals[code] ?? _refused);
    }
  }

  static const _refused = 'The streamer could not do that.';

  static const _refusals = {
    'busy': 'The streamer is busy with another action. Try again in a moment.',
    'shutting_down': 'The streamer is already restarting or powering off.',
    'upgrade_in_progress':
        'Kalinka is being updated. Try again when the update finishes.',
    'network_change_in_progress':
        'The streamer is changing its network. Try again when it finishes.',
    'too_soon': 'The server was restarted moments ago. Give it a little time.',
    'wrong_server':
        'A different Kalinka streamer now answers at this address. Reconnect to '
        'your server first.',
    'unknown_soundcard': 'This box cannot be set up for that sound card.',
    'soundcard_failed':
        'The box could not set that sound card up. Try again in a moment.',
  };
}

/// The supervisor beside the connected server, or null when the server is
/// reached over TLS: that is a server on the internet, not a box on this
/// network.
final supervisorApiProvider = Provider<SupervisorApi?>((ref) {
  final settings = ref.watch(connectionSettingsProvider);
  if (!settings.isSet || settings.scheme != 'http') return null;
  return ref.watch(supervisorAtProvider(settings.host));
});

/// The supervisor of the box at [host], such as one that runs only a
/// renderer.
final supervisorAtProvider = Provider.family<SupervisorApi, String>(
  (ref, host) => DioSupervisorApi(
    kalinkaHttpClient(
      Uri(scheme: 'http', host: host, port: supervisorPort).toString(),
    ),
  ),
);
