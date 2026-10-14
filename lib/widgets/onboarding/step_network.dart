import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../../providers/network_setup_api.dart';
import '../../theme/app_theme.dart';
import '../../theme/field_decoration.dart';
import '../kalinka_button.dart';

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
  final _ssid = TextEditingController(),
      _password = TextEditingController(),
      _country = TextEditingController();
  Timer? _timer;
  Map<String, dynamic>? _data;
  String? _message;
  bool _sending = false, _submitted = false, _showPassword = false;
  int _scanState = 0, _revision = 0;
  bool _refreshing = false;

  Map get _setup => _data?['setup'] as Map? ?? const {};
  Map get _network => _data?['network'] as Map? ?? const {};
  bool get _busy =>
      _sending || _setup['state'] == 1 || _setup['scan_state'] == 'scanning';

  @override
  void initState() {
    super.initState();
    _country.text =
        WidgetsBinding.instance.platformDispatcher.locale.countryCode ?? '';
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
    try {
      final data = await _api.status();
      if (!mounted || revision != _revision) return;
      setState(() {
        _data = data;
        final state = _setup['state'];
        if (state == 3) {
          _submitted = false;
          _message = switch (_setup['reason']) {
            2 => 'The Wi-Fi password was not accepted. Try again.',
            3 => 'The router did not assign an address. Check the router and try again.',
            4 => 'The connection timed out. Check the network and try again.',
            6 => 'The network settings could not be saved.',
            _ => 'The box could not connect. Try again or use Ethernet.',
          };
        } else if (state == 2) {
          _submitted = true;
          _message = 'The box is connected. Reconnect this device to the same network to continue.';
        } else if (!_submitted &&
            !_sending &&
            _message ==
                'Cannot reach network setup. Check the box connection and try again.') {
          _message = null;
        }
        if (_setup['scan_state'] == 'ready') _scanState = 2;
        if (_setup['scan_state'] == 'failed') _scanState = 3;
      });
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
  }

  Future<void> _scan() async {
    final country = _country.text.trim().toUpperCase();
    if (!RegExp(r'^[A-Z]{2}$').hasMatch(country)) {
      setState(
        () => _message = 'Enter your two-letter country code before scanning.',
      );
      return;
    }
    await _send(() async {
      await _api.command('open');
      if (!mounted) return;
      await _api.command('scan', {'country': country});
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
    if (!_form.currentState!.validate()) return;
    await _send(() async {
      await _api.command('open');
      if (!mounted) return;
      await _api.command('join', {
        'ssid': _ssid.text,
        'password': _password.text,
        'country': _country.text.trim().toUpperCase(),
      });
      if (!mounted) return;
      _password.clear();
      _submitted = true;
      _data = {
        ...?_data,
        'setup': {..._setup, 'state': 1},
      };
      _message = 'Settings received. The box is connecting. Reconnect this device to your home network when the hotspot closes. If the connection fails, the Kalinka hotspot will return; join it again to retry.';
      widget.onStatus?.call({...?_data, 'submitted': true});
    });
  }

  Future<void> _send(Future<void> Function() action) async {
    if (_busy) return;
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
    _country.dispose();
    super.dispose();
  }

  Widget _field(
    String label,
    TextEditingController controller,
    String? Function(String?) validate, {
    bool password = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: TextFormField(
      controller: controller,
      enabled: !_busy,
      decoration: kalinkaFieldDecoration(hint: label)
          .copyWith(labelText: label),
      obscureText: password && !_showPassword,
      autocorrect: false,
      enableSuggestions: false,
      textCapitalization: TextCapitalization.none,
      validator: validate,
      autofillHints: password ? const [AutofillHints.newPassword] : null,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final connected = _network['connected'] == true;
    final networks = (_setup['networks'] as List? ?? const []).whereType<Map>();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
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
                  ? '${_network['address']} · Keep this connection or choose Wi-Fi below.'
                  : 'Connect an Ethernet cable to your router, or set up Wi-Fi.',
            ),
          ),
          if (_data?['hotspot'] == true)
            const Padding(
              padding: EdgeInsets.only(bottom: 16),
              child: Text(
                'The temporary hotspot closes while the box joins Wi-Fi. Your phone or computer must then reconnect to your home network.',
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
          if (_submitted && widget.onReconnect != null)
            TextButton(
              onPressed: widget.onReconnect,
              child: const Text('Reconnect after changing Wi-Fi'),
            ),
          if (_data == null && _message == null)
            const LinearProgressIndicator(),
          if (_data?['available'] == false)
            const Text(
              'This box does not offer Wi-Fi setup. You can keep the current connection or use Ethernet.',
            ),
          if (_data?['available'] == true)
            Form(
              key: _form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 16),
                  Text('Wi-Fi', style: KalinkaTextStyles.sectionHeaderMuted),
                  const SizedBox(height: 16),
                  _field(
                    'Country code (for example GB)',
                    _country,
                    (v) =>
                        RegExp(r'^[A-Z]{2}$')
                            .hasMatch((v ?? '').trim().toUpperCase())
                        ? null
                        : 'Enter two letters, for example GB or US.',
                  ),
                  KalinkaButton(
                    fullWidth: true,
                    label: _scanState == 1
                        ? 'Finding networks…'
                        : 'Find Wi-Fi networks',
                    variant: KalinkaButtonVariant.neutral,
                    enabled: !_busy,
                    onTap: _scan,
                  ),
                  if (_data?['networks_cached'] == true && _scanState == 2)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        'Networks found before the hotspot started. You can also enter a name manually.',
                      ),
                    ),
                  if (_scanState == 3)
                    const Text('Scanning failed. Enter a network name below.'),
                  for (final network in networks)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.wifi),
                      title: Text(network['ssid'] as String? ?? ''),
                      subtitle: network['security'] == 'wpa2'
                          ? null
                          : const Text('This network type is not supported'),
                      enabled: !_busy && network['security'] == 'wpa2',
                      selected: _ssid.text == network['ssid'],
                      onTap: () => setState(
                        () => _ssid.text = network['ssid'] as String,
                      ),
                    ),
                  const SizedBox(height: 16),
                  _field(
                    'Network name',
                    _ssid,
                    (v) =>
                        v != null &&
                            v.isNotEmpty &&
                            utf8.encode(v).length <= 32 &&
                            !v.runes.any((r) => r < 32 || r == 127)
                        ? null
                        : 'Use a network name of 1–32 bytes.',
                  ),
                  _field(
                    'Wi-Fi password',
                    _password,
                    (v) =>
                        v != null && RegExp(r'^[\x20-\x7e]{8,63}$').hasMatch(v)
                        ? null
                        : 'Use 8–63 letters, numbers, spaces or symbols.',
                    password: true,
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Show password'),
                    value: _showPassword,
                    onChanged: (v) =>
                        setState(() => _showPassword = v ?? false),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      'WPA2 and mixed WPA2/WPA3 personal networks are supported.',
                    ),
                  ),
                  KalinkaButton(
                    fullWidth: true,
                    label: _busy ? 'Please wait…' : 'Connect to Wi-Fi',
                    enabled: !_busy && _setup['state'] != 2,
                    onTap: _join,
                  ),
                  if (_setup['state'] == 2)
                    TextButton(
                      onPressed: () => _send(() async {
                        await _api.command('change_network');
                        if (!mounted) return;
                        _submitted = false;
                      }),
                      child: const Text('Choose another network'),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
