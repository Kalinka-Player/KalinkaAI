import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../../data_model/wifi_countries.dart';
import '../../providers/network_setup_api.dart';
import '../../theme/app_theme.dart';
import '../../theme/field_decoration.dart';
import '../kalinka_button.dart';
import 'setup_discovery.dart';

/// Network review and Wi-Fi selection used in onboarding and hotspot activation.
class NetworkSetupPanel extends StatefulWidget {
  final Uri endpoint;
  final NetworkSetupApi? api;
  final ValueChanged<Map<String, dynamic>>? onStatus;
  final ValueChanged<bool>? onBusy;
  final VoidCallback? onReconnect;
  const NetworkSetupPanel({
    super.key,
    required this.endpoint,
    this.api,
    this.onStatus,
    this.onBusy,
    this.onReconnect,
  });

  @override
  State<NetworkSetupPanel> createState() => _NetworkSetupPanelState();
}

class _NetworkSetupPanelState extends State<NetworkSetupPanel> {
  late final NetworkSetupApi _api =
      widget.api ?? NetworkSetupApi(widget.endpoint);
  final _form = GlobalKey<FormState>();
  final _ssid = TextEditingController(), _password = TextEditingController();
  String? _country;
  Timer? _timer;
  Map<String, dynamic>? _data;
  String? _message;
  bool _sending = false, _submitted = false, _showPassword = false;
  int _scanState = 0, _revision = 0;
  bool _refreshing = false, _scanStarted = false;
  bool _manual = false, _networkChosen = false, _succeeded = false;
  bool _changingNetwork = false;
  bool _sendingJoin = false;

  bool get _validCountry => wifiCountries.containsKey(_country);

  Map get _setup => _data?['setup'] as Map? ?? const {};
  Map get _network => _data?['network'] as Map? ?? const {};
  bool get _busy =>
      _sending || _setup['state'] == 1 || _setup['scan_state'] == 'scanning';
  bool get _connecting =>
      !_changingNetwork &&
      (_sendingJoin || (_submitted && !_succeeded) || _setup['state'] == 1);

  @override
  void initState() {
    super.initState();
    _country = WidgetsBinding.instance.platformDispatcher.locale.countryCode;
    _refresh();
  }

  void _scheduleRefresh() {
    _timer?.cancel();
    if (mounted && !_sending && !_refreshing) {
      _timer = Timer(const Duration(seconds: 2), _refresh);
    }
  }

  Future<void> _refresh() async {
    if (!mounted || _sending || _refreshing) return;
    _refreshing = true;
    final revision = _revision;
    var discover = false;
    try {
      final data = await _api.status();
      if (!mounted || revision != _revision) return;
      setState(() {
        _data = data;
        final state = _setup['state'];
        if (_changingNetwork && state != 1) _changingNetwork = false;
        if (state == 3) {
          _submitted = false;
          _succeeded = false;
          _message = switch (_setup['reason']) {
            2 => 'The Wi-Fi password was not accepted. Try again.',
            3 => 'The router did not assign an address. Check the router and try again.',
            4 => 'The connection timed out. Check the network and try again.',
            6 => 'The network settings could not be saved.',
            _ => 'The box could not connect. Try again or use Ethernet.',
          };
        } else if (state == 2) {
          _submitted = true;
          _succeeded = true;
          _message = 'Your box is connected and ready to use.';
        } else if (!_submitted &&
            !_sending &&
            _message ==
                'Cannot reach network setup. Check the box connection and try again.') {
          _message = null;
        }
        if (_setup['scan_state'] == 'ready') _scanState = 2;
        if (_setup['scan_state'] == 'failed') _scanState = 3;
      });
      discover =
          !_scanStarted &&
          !_succeeded &&
          !_busy &&
          !_changingNetwork &&
          data['available'] == true &&
          _validCountry;
      widget.onStatus?.call({...data, 'submitted': _submitted});
      widget.onBusy?.call(_busy);
    } catch (_) {
      if (!mounted || revision != _revision) return;
      if (!_submitted) {
        setState(
          () => _message = 'Cannot reach network setup. Check the box connection and try again.',
        );
      }
    } finally {
      _refreshing = false;
      _scheduleRefresh();
    }
    if (discover && mounted) await _scan();
  }

  Future<void> _scan() async {
    final country = _country;
    if (!_validCountry) {
      setState(() => _message = 'Choose your country before scanning.');
      return;
    }
    _scanStarted = true;
    await _send(() async {
      await _api.command('open');
      if (!mounted) return;
      await _api.command('scan', {'country': country!});
      if (!mounted) return;
      _scanState = 1;
      _data = {
        ...?_data,
        'setup': {..._setup, 'scan_state': 'scanning'},
      };
      _message = null;
    });
  }

  Future<void> _join() async {
    if (!_validCountry) {
      setState(() => _message = 'Choose your country before connecting.');
      return;
    }
    if (!_form.currentState!.validate()) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _sendingJoin = true);
    await _send(() async {
      await _api.command('open');
      if (!mounted) return;
      await _api.command('join', {
        'ssid': _ssid.text,
        'password': _password.text,
        'country': _country!,
      });
      if (!mounted) return;
      _password.clear();
      _submitted = true;
      _succeeded = false;
      _data = {
        ...?_data,
        'setup': {..._setup, 'state': 1},
      };
      _message = _data?['hotspot'] == true
          ? 'Connecting your box… When the hotspot closes, reconnect this device to your home network. If the connection fails, the hotspot will return for another attempt.'
          : 'Connecting your box… This page will reconnect when it is ready.';
      widget.onStatus?.call({...?_data, 'submitted': true});
    });
    if (mounted) setState(() => _sendingJoin = false);
  }

  Future<void> _changeNetwork() async {
    await _send(() async {
      if (!_connecting) {
        await _api.command('open');
        if (!mounted) return;
      }
      await _api.command('change_network');
      if (!mounted) return;
      _submitted = false;
      _succeeded = false;
      _changingNetwork = true;
      _scanStarted = false;
      _scanState = 0;
      _networkChosen = false;
      _manual = false;
      _password.clear();
      _ssid.clear();
      _message = null;
      _data = {
        ...?_data,
        'setup': {..._setup, 'state': 1},
      };
      widget.onStatus?.call({...?_data, 'submitted': false});
    }, allowWhileJoining: true);
  }

  void _chooseNetwork(String? ssid) {
    setState(() {
      _manual = ssid == null;
      _networkChosen = true;
      _ssid.text = ssid ?? '';
      _password.clear();
      _showPassword = false;
      _message = null;
    });
  }

  void _showNetworks() {
    setState(() {
      _networkChosen = false;
      _manual = false;
      _password.clear();
      _message = null;
    });
  }

  Future<void> _send(
    Future<void> Function() action, {
    bool allowWhileJoining = false,
  }) async {
    if (_sending || _changingNetwork || (_busy && !allowWhileJoining)) return;
    _revision++;
    _timer?.cancel();
    setState(() => _sending = true);
    widget.onBusy?.call(true);
    try {
      await action();
    } catch (_) {
      if (mounted) {
        setState(
          () => _message = 'The request could not be confirmed. Check the connection or wait for another setup to finish, then retry.',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _sending = false);
        widget.onBusy?.call(_busy);
        _scheduleRefresh();
      }
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _api.dispose();
    _ssid.dispose();
    _password.dispose();
    super.dispose();
  }

  Widget _field(
    String label,
    TextEditingController controller,
    String? Function(String?) validate, {
    required String fieldKey,
    bool password = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: TextFormField(
      key: ValueKey(fieldKey),
      controller: controller,
      enabled: !_sending && _setup['state'] != 1,
      decoration: kalinkaFieldDecoration(hint: label).copyWith(
        labelText: label,
        suffixIcon: password
            ? IconButton(
                tooltip: _showPassword ? 'Hide password' : 'Show password',
                onPressed: () => setState(() => _showPassword = !_showPassword),
                icon: Icon(
                  _showPassword
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                ),
              )
            : null,
      ),
      obscureText: password && !_showPassword,
      autocorrect: false,
      enableSuggestions: false,
      textCapitalization: TextCapitalization.none,
      validator: validate,
      autofillHints: password ? const [AutofillHints.password] : null,
    ),
  );

  Widget _region() => ExpansionTile(
    tilePadding: EdgeInsets.zero,
    childrenPadding: const EdgeInsets.only(top: 16, bottom: 16),
    initiallyExpanded: !_validCountry,
    title: Text(
      'Wi-Fi region${_validCountry ? ' · $_country' : ''}',
      style: KalinkaTextStyles.trayRowSublabel,
    ),
    children: [
      DropdownMenu<String>(
        key: const ValueKey('network-country'),
        enabled: !_busy,
        initialSelection: _validCountry ? _country : null,
        expandedInsets: EdgeInsets.zero,
        menuHeight: 280,
        enableFilter: true,
        requestFocusOnTap: true,
        textStyle: KalinkaTextStyles.trayRowSublabel,
        decorationBuilder: (context, controller) =>
            kalinkaFieldDecoration(hint: 'Search countries')
                .copyWith(labelText: 'Country'),
        dropdownMenuEntries: [
          for (final country in wifiCountries.entries)
            DropdownMenuEntry(
              value: country.key,
              label: '${country.value} (${country.key})',
              labelWidget: Text('${country.value} (${country.key})'),
            ),
        ],
        onSelected: (country) {
          if (country == null || country == _country) return;
          setState(() => _country = country);
          FocusManager.instance.primaryFocus?.unfocus();
          if (!_busy) _scan();
        },
      ),
      Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Text(
          'Choose the country where the box is used. This sets the available Wi-Fi channels.',
          style: KalinkaTextStyles.trayRowSublabel,
        ),
      ),
    ],
  );

  List<Widget> _networks() {
    final networks = (_setup['networks'] as List? ?? const []).whereType<Map>();
    final scanning = _scanState == 1 || _setup['scan_state'] == 'scanning';
    return [
      SetupDiscoveryHeader(
        title: 'AVAILABLE NETWORKS',
        activityLabel: 'Finding Wi-Fi networks',
        searching: scanning,
        onScan: !_busy && _validCountry ? _scan : null,
      ),
      const SizedBox(height: 12),
      if (scanning)
        const SetupLoadingCard(
          title: 'Finding Wi-Fi networks…',
          subtitle: 'Your box is checking for nearby networks.',
          loading: false,
        )
      else ...[
        if (_data?['networks_cached'] == true && _scanState == 2)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text(
              'Networks found before the hotspot started. You can also enter a name manually.',
            ),
          ),
        for (final network in networks)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.wifi),
            title: Text(network['ssid'] as String? ?? ''),
            subtitle: network['security'] == 'wpa2'
                ? null
                : const Text('This network type is not supported'),
            trailing: const Icon(Icons.chevron_right),
            enabled: !_busy && network['security'] == 'wpa2',
            onTap: () => _chooseNetwork(network['ssid'] as String),
          ),
        if (_scanState == 2 && networks.isEmpty)
          const Text(
            'No networks found. Scan again or enter your network name manually.',
          ),
        if (_scanState == 3)
          const Text(
            'Could not find networks. Try again or enter your network name manually.',
          ),
        if (!_validCountry)
          const Text('Choose your country below to find nearby networks.'),
      ],
      const SizedBox(height: 12),
      TextButton(
        onPressed: !_sending && _setup['state'] != 1
            ? () => _chooseNetwork(null)
            : null,
        child: const Text('Can’t find your network? Enter SSID manually'),
      ),
    ];
  }

  Widget _credentials() => Form(
    key: _form,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_manual)
          _field(
            'Network name (SSID)',
            _ssid,
            (v) =>
                v != null &&
                    v.isNotEmpty &&
                    utf8.encode(v).length <= 32 &&
                    !v.runes.any((r) => r < 32 || r == 127)
                ? null
                : 'Use a network name of 1–32 bytes.',
            fieldKey: 'network-ssid',
          )
        else
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.wifi),
            title: Text(_ssid.text),
            subtitle: const Text('Enter the password for this network.'),
          ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: !_busy ? _showNetworks : null,
            child: const Text('Back to available networks'),
          ),
        ),
        _field(
          'Wi-Fi password',
          _password,
          (v) => v != null && RegExp(r'^[\x20-\x7e]{8,63}$').hasMatch(v)
              ? null
              : 'Use 8–63 letters, numbers, spaces or symbols.',
          fieldKey: 'network-password',
          password: true,
        ),
        KalinkaButton(
          fullWidth: true,
          label: _busy ? 'Please wait…' : 'Connect to Wi-Fi',
          enabled: !_busy,
          onTap: _join,
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final connected = _network['connected'] == true;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_data != null)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                connected
                    ? (_network['kind'] == 'wired'
                          ? Icons.settings_ethernet
                          : Icons.wifi)
                    : Icons.wifi_off,
              ),
              title: Text(
                connected
                    ? (_network['kind'] == 'wired'
                          ? 'Connected by Ethernet'
                          : 'Connected by Wi-Fi')
                    : 'Network connection',
              ),
              subtitle: Text(
                connected
                    ? '${_network['address']}'
                    : 'Connect an Ethernet cable or choose Wi-Fi below.',
              ),
            ),
          if (_message != null)
            Semantics(
              liveRegion: true,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  _message!,
                  style: KalinkaTextStyles.trayRowSublabel,
                ),
              ),
            ),
          if (_submitted && !connected && widget.onReconnect != null)
            TextButton(
              onPressed: widget.onReconnect,
              child: const Text('Reconnect after changing Wi-Fi'),
            ),
          if (_data == null && _message == null) ...[
            const SetupDiscoveryHeader(
              title: 'YOUR BOX',
              activityLabel: 'Looking for your box',
              searching: true,
            ),
            const SizedBox(height: 12),
            const SetupLoadingCard(
              title: 'Looking for your box…',
              subtitle:
                  'Keep your box powered on and stay connected to its network.',
              loading: false,
            ),
          ],
          if (_data?['available'] == false)
            const Text(
              'This box does not offer Wi-Fi setup. You can keep the current connection or use Ethernet.',
            ),
          if (_succeeded) ...[
            const SizedBox(height: 16),
            KalinkaButton(
              label: 'Change Wi-Fi network',
              variant: KalinkaButtonVariant.neutral,
              fullWidth: true,
              enabled: !_busy,
              onTap: _changeNetwork,
            ),
          ] else if (_data?['available'] == true) ...[
            const SizedBox(height: 16),
            if (_connecting) ...[
              const SetupLoadingCard(
                title: 'Please wait…',
                subtitle: 'Connecting your box to Wi-Fi.',
              ),
              const SizedBox(height: 16),
              KalinkaButton(
                label: 'Choose another network',
                variant: KalinkaButtonVariant.neutral,
                fullWidth: true,
                enabled: !_sending,
                onTap: _changeNetwork,
              ),
            ] else if (_changingNetwork)
              const SetupLoadingCard(
                title: 'Preparing the network list…',
                subtitle: 'Restoring settings before you choose again.',
              )
            else ...[
              if (_networkChosen) _credentials() else ..._networks(),
              const SizedBox(height: 16),
              _region(),
            ],
          ],
        ],
      ),
    );
  }
}
