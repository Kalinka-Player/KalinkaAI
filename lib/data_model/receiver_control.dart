/// Receiver management is independent of the selected renderer and catalogs.
class ReceiverSnapshot {
  final String id, title, kind, state, instructions;
  final bool enabled, nameInherited;
  final String? message, effectiveName, recentPeerId, pairingMode;
  final ReceiverPairing? pairing;
  final ReceiverPairingRequest? pairingRequest;
  final bool passwordRequired, passwordRevealAvailable;
  final List<ReceiverPeer> peers;
  final List<ReceiverSession> sessions;
  final Map<String, bool> actions;

  ReceiverSnapshot.fromJson(Map<String, dynamic> json)
    : id = json['receiver_id'] as String,
      title = json['title'] as String,
      kind = json['kind'] as String,
      state = json['state'] as String,
      enabled = json['enabled'] == true,
      instructions = json['instructions'] as String? ?? '',
      message = json['message'] as String?,
      effectiveName = json['effective_name'] as String?,
      nameInherited = json['name_inherited'] != false,
      recentPeerId = json['recent_peer_id'] as String?,
      pairingMode = json['pairing_mode'] as String?,
      pairing = json['pairing'] == null
          ? null
          : ReceiverPairing.fromJson(
              Map<String, dynamic>.from(json['pairing'] as Map),
            ),
      pairingRequest = json['pairing_request'] == null
          ? null
          : ReceiverPairingRequest.fromJson(
              Map<String, dynamic>.from(json['pairing_request'] as Map),
            ),
      passwordRequired = json['password_required'] == true,
      passwordRevealAvailable = json['password_reveal_available'] == true,
      peers = [
        for (final p in json['peers'] as List? ?? [])
          ReceiverPeer.fromJson(Map<String, dynamic>.from(p as Map)),
      ],
      sessions = [
        for (final s in json['sessions'] as List? ?? [])
          ReceiverSession.fromJson(Map<String, dynamic>.from(s as Map)),
      ],
      actions = {
        for (final a in json['actions'] as List? ?? [])
          a['command'] as String: a['available'] == true,
      };

  bool offers(String command) => actions.containsKey(command);
  bool can(String command) => actions[command] == true;

  static List<ReceiverSnapshot> listFromJson(Object? value) => [
    for (final row in value as List? ?? [])
      ReceiverSnapshot.fromJson(Map<String, dynamic>.from(row as Map)),
  ];
}

class ReceiversSnapshot {
  final List<ReceiverSnapshot> receivers;
  ReceiversSnapshot.fromJson(Map<String, dynamic> json)
    : receivers = ReceiverSnapshot.listFromJson(json['receivers']);
}

class ReceiverPairing {
  final String id;
  final double seconds;
  final Stopwatch _elapsed = Stopwatch()..start();
  ReceiverPairing.fromJson(Map<String, dynamic> json)
    : id = json['window_id'] as String,
      seconds = (json['remaining_seconds'] as num).toDouble();
  int get remainingMicroseconds =>
      (seconds * Duration.microsecondsPerSecond - _elapsed.elapsedMicroseconds)
          .ceil()
          .clamp(0, 120 * Duration.microsecondsPerSecond);
  int get remainingSeconds =>
      (remainingMicroseconds / Duration.microsecondsPerSecond).ceil();
}

class ReceiverPeer {
  final String id, name;
  final bool paired, audioAllowed, connected;
  ReceiverPeer.fromJson(Map<String, dynamic> json)
    : id = json['peer_id'] as String,
      name = json['name'] as String,
      paired = json['paired'] == true,
      audioAllowed = json['audio_allowed'] == true,
      connected = json['connected'] == true;
}

class ReceiverSession {
  final String id, name;
  final String? peerId;
  final bool playing;
  ReceiverSession.fromJson(Map<String, dynamic> json)
    : id = json['session_id'] as String,
      name = json['name'] as String,
      peerId = json['peer_id'] as String?,
      playing = json['playing'] == true;
}

class ReceiverPairingRequest {
  final String id, deviceName, method;
  final String? code;
  final int? entered;
  final double seconds;
  final Stopwatch _elapsed = Stopwatch()..start();
  ReceiverPairingRequest.fromJson(Map<String, dynamic> json)
    : id = json['request_id'] as String,
      deviceName = json['device_name'] as String,
      method = json['method'] as String,
      code = json['code'] as String?,
      entered = json['entered'] as int?,
      seconds = (json['remaining_seconds'] as num).toDouble();
  int get remainingSeconds =>
      (seconds - _elapsed.elapsedMilliseconds / 1000).ceil().clamp(0, 120);
  bool get displayOnly =>
      method == 'display_pin' || method == 'display_passkey';
  bool get needsInput => method == 'pin' || method == 'passkey';
}
