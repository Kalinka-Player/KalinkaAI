import 'package:dio/dio.dart' show Dio, DioException;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'connection_settings_provider.dart';
import 'kalinka_player_api_provider.dart' show kalinkaHttpClient;

/// Where a Kalinka box's supervisor listens: beside the server on a port of
/// its own, so it still answers when the server does not.
const supervisorPort = 8001;

/// The control protocol this app speaks.
const _protocol = 1;

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

  final Set<String> actions;

  const SupervisorInfo({
    required this.version,
    required this.protocol,
    required this.minProtocol,
    required this.serverId,
    required this.actions,
  });

  /// Whether this app and the supervisor share a protocol version.
  bool get compatible => protocol >= _protocol && minProtocol <= _protocol;

  bool offers(BoxAction action) => actions.contains(action.wire);

  /// Null when [json] is not a supervisor's answer.
  static SupervisorInfo? fromJson(Object? json) {
    if (json is! Map || json['name'] != 'kalinka-supervisor') return null;
    final protocol = json['protocol'];
    final minProtocol = json['min_protocol'];
    final actions = json['actions'];
    if (protocol is! int || minProtocol is! int || actions is! List) {
      return null;
    }
    final serverId = json['server_id'];
    return SupervisorInfo(
      version: json['version']?.toString() ?? '',
      protocol: protocol,
      minProtocol: minProtocol,
      serverId: serverId is String && serverId.isNotEmpty ? serverId : null,
      actions: actions.whereType<String>().toSet(),
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
  Future<void> run(BoxAction action, {required String serverId}) async {
    try {
      await _client.post(
        '/v$_protocol/actions/${action.wire}',
        data: {'server_id': serverId},
      );
    } on DioException catch (e) {
      final response = e.response;
      if (response == null) {
        throw const BoxActionException(
          'unreachable',
          'The box did not answer. Check that it is on and connected.',
        );
      }
      final detail = response.data is Map ? response.data['detail'] : null;
      final code = detail is Map ? detail['code']?.toString() : null;
      throw BoxActionException(code ?? 'error', _refusals[code] ?? _refused);
    }
  }

  static const _refused = 'The box could not do that.';

  static const _refusals = {
    'busy': 'The box is busy with another action. Try again in a moment.',
    'shutting_down': 'The box is already restarting or powering off.',
    'upgrade_in_progress':
        'Kalinka is being updated. Try again when the update finishes.',
    'network_change_in_progress':
        'The box is changing its network. Try again when it finishes.',
    'too_soon': 'The server was restarted moments ago. Give it a little time.',
    'wrong_server':
        'A different Kalinka box now answers at this address. Reconnect to '
        'your server first.',
  };
}

/// The supervisor beside the connected server, or null when the server is
/// reached over TLS: that is a server on the internet, not a box on this
/// network.
final supervisorApiProvider = Provider<SupervisorApi?>((ref) {
  final settings = ref.watch(connectionSettingsProvider);
  if (!settings.isSet || settings.scheme != 'http') return null;
  return DioSupervisorApi(
    kalinkaHttpClient(
      Uri(scheme: 'http', host: settings.host, port: supervisorPort).toString(),
    ),
  );
});
