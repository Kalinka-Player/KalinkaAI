import 'dart:convert';
import 'dart:typed_data';

const provisionServiceUuid = '7c8e0001-1b2f-4e6a-9d3c-4b616c696e6b';
const provisionStatusUuid = '7c8e0002-1b2f-4e6a-9d3c-4b616c696e6b';
const provisionIdentityUuid = '7c8e0003-1b2f-4e6a-9d3c-4b616c696e6b';
const provisionCommandUuid = '7c8e0004-1b2f-4e6a-9d3c-4b616c696e6b';
const provisionNetworksUuid = '7c8e0005-1b2f-4e6a-9d3c-4b616c696e6b';
const provisionProgressUuid = '7c8e0006-1b2f-4e6a-9d3c-4b616c696e6b';

enum WifiJoinStage {
  preparing,
  authenticating,
  gettingAddress,
  saving,
  connected,
}

WifiJoinStage decodeWifiProgress(Uint8List bytes) {
  if (bytes.length != 2 ||
      bytes[0] != 1 ||
      bytes[1] >= WifiJoinStage.values.length) {
    throw const FormatException('Invalid Wi-Fi progress.');
  }
  return WifiJoinStage.values[bytes[1]];
}

enum BoxState { idle, joining, joined, failed, online }

class ProvisioningStatus {
  final BoxState state;
  final int reason;
  final int capabilities;
  final String? address;
  final int port;

  const ProvisioningStatus(
    this.state,
    this.reason,
    this.capabilities,
    this.address,
    this.port,
  );

  bool get isTest => capabilities & 2 != 0;
  bool get canScanWifi => capabilities & 4 != 0;
  bool get canReportProgress => capabilities & 8 != 0;
  bool get canChangeNetwork => capabilities & 16 != 0;

  factory ProvisioningStatus.decode(Uint8List bytes) {
    if (bytes.length != 10 ||
        bytes[0] != 1 ||
        bytes[1] & 1 == 0 ||
        bytes[2] >= BoxState.values.length ||
        bytes[3] > 7) {
      throw const FormatException(
        'This box needs a different version of the app.',
      );
    }
    final port = ByteData.sublistView(bytes).getUint16(8);
    if (port == 0) throw const FormatException('Invalid server port.');
    final ip = bytes.sublist(4, 8);
    return ProvisioningStatus(
      BoxState.values[bytes[2]],
      bytes[3],
      bytes[1],
      ip.every((b) => b == 0) ? null : ip.join('.'),
      port,
    );
  }

  String get failureMessage => switch (reason) {
    1 => 'The box could not accept these network details.',
    2 => 'The Wi-Fi password was rejected. Check it and try again.',
    3 => 'Wi-Fi connected, but the router did not provide an address.',
    4 =>
      'Could not join Wi-Fi. Check the network name and password, and move the box closer to the router.',
    5 => 'Wi-Fi is unavailable on this box. Check its adapter or use Ethernet.',
    6 =>
      'The box could not save this network. Its saved networks were restored.',
    7 => 'Another phone is setting up this box. Try again shortly.',
    _ => 'Wi-Fi setup failed. Try again.',
  };
}

class ProvisioningNetwork {
  final String ssid;
  final int signal;
  final String security;
  const ProvisioningNetwork(this.ssid, this.signal, this.security);

  bool get supported => security == 'wpa2';
  String get description => supported
      ? '${signal >= -55
            ? 'Strong'
            : signal >= -70
            ? 'Good'
            : 'Weak'} signal'
      : security == 'open'
      ? 'Open network — not supported yet'
      : 'Security type not supported yet';
}

class ProvisioningNetworkPage {
  final int id;
  final int page;
  final int pages;
  final String state;
  final List<ProvisioningNetwork> networks;
  const ProvisioningNetworkPage(
    this.id,
    this.page,
    this.pages,
    this.state,
    this.networks,
  );

  factory ProvisioningNetworkPage.decode(Uint8List bytes) {
    const invalid = FormatException(
      'The box returned an invalid network list.',
    );
    if (bytes.length > 512) throw invalid;
    final data = jsonDecode(utf8.decode(bytes));
    if (data is! Map ||
        data['v'] != 1 ||
        data['id'] is! int ||
        data['page'] is! int ||
        data['pages'] is! int ||
        data['pages'] < 1 ||
        data['pages'] > 10 ||
        data['page'] < 0 ||
        data['page'] >= data['pages'] ||
        !['idle', 'scanning', 'ready', 'failed'].contains(data['state']) ||
        data['networks'] is! List ||
        (data['networks'] as List).length > 3) {
      throw invalid;
    }
    final networks = <ProvisioningNetwork>[];
    for (final item in data['networks']) {
      if (item is! Map ||
          item['ssid'] is! String ||
          utf8.encode(item['ssid']).isEmpty ||
          utf8.encode(item['ssid']).length > 32 ||
          (item['ssid'] as String).runes.any((c) => c < 32 || c == 127) ||
          item['signal'] is! int ||
          item['signal'] < -127 ||
          item['signal'] > 0 ||
          !['wpa2', 'open', 'unsupported'].contains(item['security'])) {
        throw invalid;
      }
      networks.add(
        ProvisioningNetwork(item['ssid'], item['signal'], item['security']),
      );
    }
    return ProvisioningNetworkPage(
      data['id'],
      data['page'],
      data['pages'],
      data['state'],
      networks,
    );
  }
}

String? decodeProvisioningIdentity(Uint8List bytes) {
  if (bytes.isEmpty) return null; // Core has not created its identity yet.
  if (bytes.length != 16) {
    throw const FormatException('Invalid server identity.');
  }
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

List<Uint8List> provisionFrames(Map<String, Object> command) {
  final bytes = utf8.encode(jsonEncode({'v': 1, ...command}));
  if (bytes.length > 512) {
    throw const FormatException('Network details are too long.');
  }
  return [
    for (var start = 0; start < bytes.length; start += 19)
      Uint8List.fromList([
        (start == 0 ? 1 : 0) | (start + 19 >= bytes.length ? 2 : 0),
        ...bytes.sublist(start, (start + 19).clamp(0, bytes.length)),
      ]),
  ];
}
