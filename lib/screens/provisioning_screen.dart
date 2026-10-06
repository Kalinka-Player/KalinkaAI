import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/discovery_provider.dart';
import '../providers/provisioning_controller.dart';
import '../providers/provisioning_protocol.dart';
import '../providers/provisioning_transport.dart';
import '../providers/provisioning_transport_ble.dart'
    if (dart.library.js_interop) '../providers/provisioning_transport_stub.dart';
import '../theme/app_theme.dart';
import '../theme/field_decoration.dart';
import '../widgets/kalinka_button.dart';
import '../widgets/onboarding/onboarding_step_scaffold.dart';

class ProvisioningScreen extends ConsumerStatefulWidget {
  final ProvisioningTransport? transport;
  final Future<ProvisionedEndpoint?> Function(ProvisioningStatus, String?)?
  reach;
  const ProvisioningScreen({super.key, this.transport, this.reach});

  @override
  ConsumerState<ProvisioningScreen> createState() => _ProvisioningScreenState();
}

class _ProvisioningScreenState extends ConsumerState<ProvisioningScreen> {
  final _form = GlobalKey<FormState>();
  final _ssid = TextEditingController();
  final _password = TextEditingController();
  final _country = TextEditingController();
  final _client = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 2),
      receiveTimeout: const Duration(seconds: 3),
    ),
  );
  late final ProvisioningController _setup;
  NearbyBox? _chosenBox;
  bool _customSsid = false;
  bool _networkChosen = false;
  bool _advanced = false;
  final _scroll = ScrollController();
  bool _showPassword = false;
  bool _finished = false;
  SetupPhase _lastPhase = SetupPhase.scanning;

  @override
  void initState() {
    super.initState();
    _country.text =
        WidgetsBinding.instance.platformDispatcher.locale.countryCode ?? 'GB';
    _setup = ProvisioningController(
      widget.transport ?? createProvisioningTransport(),
      widget.reach ?? _reach,
    );
    _setup.addListener(_changed);
    unawaited(_setup.scan());
  }

  Future<void> _selectBox(NearbyBox box) async {
    await _setup.select(box);
    if (mounted) await _setup.scanWifi(_country.text.toUpperCase());
  }

  Future<void> _reconnect() async {
    await _setup.reconnect();
    if (mounted) await _setup.scanWifi(_country.text.toUpperCase());
  }

  Future<void> _changeNetwork() async {
    await _setup.changeNetwork();
    if (!mounted || _setup.phase != SetupPhase.credentials) return;
    _password.clear();
    _networkChosen = false;
    _customSsid = false;
    await _setup.scanWifi(_country.text.toUpperCase());
  }

  Future<void> _retry() async {
    if (_setup.error == null) return;
    if (_setup.phase == SetupPhase.reaching) {
      await _setup.retryHandoff();
    } else if (_setup.phase == SetupPhase.joining &&
        _setup.status?.state == BoxState.failed &&
        _ssid.text.isNotEmpty) {
      await _setup.join(
        _ssid.text,
        _password.text,
        _country.text.toUpperCase(),
      );
    } else {
      await _reconnect();
    }
  }

  void _changed() {
    if (!mounted) return;
    if (_lastPhase != _setup.phase) {
      _lastPhase = _setup.phase;
      if (_scroll.hasClients) _scroll.jumpTo(0);
      if (_setup.phase == SetupPhase.credentials &&
          _setup.status?.canScanWifi != true) {
        _customSsid = true;
        _networkChosen = true;
      }
    }
    if (_chosenBox == null && _setup.boxes.isNotEmpty) {
      _chosenBox = _setup.boxes.first;
    }
    if (_setup.phase == SetupPhase.done && !_finished) {
      _finished = true;
      _password.clear();
      Navigator.of(context).pop(_setup.endpoint);
      return;
    }
    setState(() {});
  }

  Future<ProvisionedEndpoint?> _reach(
    ProvisioningStatus status,
    String? id,
  ) async {
    if (!mounted) return null;
    final discovery = ref.read(discoveryProvider);
    final matches = discovery.servers.where(
      (server) => id != null && server.serverId == id,
    );
    final match = matches.isEmpty ? null : matches.first;
    final host = match?.host ?? status.address;
    final port = match?.port ?? status.port;
    // Keep ordinary discovery running through the Core's cold start. A
    // normal scan expires sooner than the server's interface rescan interval.
    if (!discovery.isScanning) {
      unawaited(ref.read(discoveryProvider.notifier).rescan());
    }
    if (host == null) return null;
    try {
      final base = Uri(scheme: 'http', host: host, port: port);
      final modules = await _client.getUri(
        base.replace(path: '/server/modules'),
      );
      if (modules.data is! Map || modules.data['input_modules'] is! List) {
        return null;
      }
      final sessions = await _client.getUri(
        base.replace(path: '/renderer/sessions'),
      );
      final serverId = sessions.data is Map ? sessions.data['server_id'] : null;
      if (serverId is! String || (id != null && id != serverId)) return null;
      return ProvisionedEndpoint(
        match?.name ?? _setup.selected!.name,
        host,
        port,
        serverId,
      );
    } catch (_) {
      return null;
    }
  }

  @override
  void dispose() {
    _setup.removeListener(_changed);
    _setup.dispose();
    _scroll.dispose();
    _ssid.dispose();
    _password.dispose();
    _country.dispose();
    _client.close(force: true);
    super.dispose();
  }

  bool get _boxStep => switch (_setup.phase) {
    SetupPhase.scanning || SetupPhase.choosing || SetupPhase.connecting => true,
    _ => false,
  };

  void _chooseNetwork(ProvisioningNetwork? network) {
    FocusScope.of(context).unfocus();
    setState(() {
      _customSsid = network == null;
      _networkChosen = true;
      _ssid.text = network?.ssid ?? '';
      _password.clear();
      _showPassword = false;
    });
    _scroll.animateTo(
      0,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  void _showNetworks() {
    FocusScope.of(context).unfocus();
    _password.clear();
    setState(() => _networkChosen = false);
  }

  bool get _atBoxPicker =>
      _setup.phase == SetupPhase.scanning ||
      _setup.phase == SetupPhase.choosing;

  void _back() {
    FocusScope.of(context).unfocus();
    if (_atBoxPicker) {
      Navigator.of(context).maybePop();
    } else if (_setup.phase == SetupPhase.changingNetwork) {
      // Wait for the box to finish cancelling the previous join.
      return;
    } else if (_setup.phase == SetupPhase.credentials &&
        _networkChosen &&
        _setup.status?.canScanWifi == true) {
      _showNetworks();
    } else if ((_setup.phase == SetupPhase.joining ||
            _setup.phase == SetupPhase.reaching) &&
        _setup.status?.canChangeNetwork == true) {
      unawaited(_changeNetwork());
    } else if (_setup.phase == SetupPhase.joining &&
        _setup.status?.state == BoxState.failed) {
      unawaited(_reconnect());
    } else {
      _password.clear();
      _ssid.clear();
      _chosenBox = null;
      _networkChosen = false;
      _customSsid = false;
      unawaited(_setup.scan());
    }
  }

  void _submit() {
    if (_setup.phase != SetupPhase.credentials || _setup.scanningWifi) return;
    if (!RegExp(r'^[A-Z]{2}$').hasMatch(_country.text.toUpperCase())) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Check the country code under Advanced.')),
      );
      return;
    }
    if (_form.currentState?.validate() != true) return;
    FocusScope.of(context).unfocus();
    unawaited(
      _setup.join(_ssid.text, _password.text, _country.text.toUpperCase()),
    );
  }

  TextStyle get _bodyStyle =>
      KalinkaTextStyles.trayRowSublabel.copyWith(fontSize: 15, height: 1.5);

  @override
  Widget build(BuildContext context) {
    final phase = _setup.phase;
    return PopScope(
      canPop: _atBoxPicker,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        backgroundColor: KalinkaColors.background,
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
                    child: OnboardingProgress(
                      stepNumber: _boxStep ? 1 : 2,
                      stepCount: 2,
                      stepLabels: const ['YOUR BOX', 'WI-FI'],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView(
                      controller: _scroll,
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
                      children: [
                        if (_boxStep)
                          ..._boxContent()
                        else if (phase == SetupPhase.credentials)
                          ..._networkContent()
                        else
                          ..._progressContent(),
                      ],
                    ),
                  ),
                  _footer(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _heading(String text, {IconData? icon}) => Row(
    children: [
      if (icon != null) ...[
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: KalinkaColors.surfaceRaised,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: KalinkaColors.borderDefault),
          ),
          child: Icon(icon, color: KalinkaColors.accentTint, size: 24),
        ),
        const SizedBox(width: 14),
      ],
      Expanded(
        child: Text(
          text,
          style: KalinkaTextStyles.dialogTitle.copyWith(
            fontSize: 28,
            height: 1.15,
          ),
        ),
      ),
    ],
  );

  Widget _deck(String text) => Padding(
    padding: const EdgeInsets.only(top: 10, bottom: 20),
    child: Text(text, style: _bodyStyle),
  );

  Widget _note(String text, {bool error = false}) => Container(
    margin: const EdgeInsets.only(top: 16),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: error
          ? KalinkaColors.actionDeleteSurface
          : KalinkaColors.surfaceRaised,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          error ? Icons.info_outline_rounded : Icons.science_outlined,
          size: 18,
          color: error
              ? KalinkaColors.actionDeleteLight
              : KalinkaColors.textMuted,
        ),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: _bodyStyle.copyWith(fontSize: 13))),
      ],
    ),
  );

  List<Widget> _boxContent() {
    final connecting = _setup.phase == SetupPhase.connecting;
    return [
      _heading(
        connecting ? 'Connecting to your box' : 'Meet your Kalinka.',
        icon: Icons.speaker_outlined,
      ),
      _deck(
        connecting
            ? 'Accept the Bluetooth pairing request on your phone.'
            : 'Switch on your box and keep it nearby.\nWe’ll take it from here.',
      ),
      if (connecting)
        _loadingCard(
          'Connecting to ${_setup.selected!.name}',
          'Establishing a secure connection…',
        )
      else ...[
        Row(
          children: [
            Expanded(
              child: Text(
                'NEARBY BOXES',
                style: KalinkaTextStyles.sectionHeaderMuted,
              ),
            ),
            if (_setup.phase == SetupPhase.scanning)
              const SizedBox(
                width: 48,
                height: 48,
                child: Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: KalinkaColors.accentTint,
                      semanticsLabel: 'Searching for nearby boxes',
                    ),
                  ),
                ),
              )
            else
              IconButton(
                tooltip: 'Scan again',
                onPressed: () {
                  _chosenBox = null;
                  _setup.scan();
                },
                icon: const Icon(
                  Icons.refresh_rounded,
                  color: KalinkaColors.textSecondary,
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        for (final box in _setup.boxes)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _choice(
              icon: Icons.speaker_outlined,
              title: box.name,
              subtitle: 'Ready to set up',
              selected: _chosenBox?.id == box.id,
              onTap: () => setState(() => _chosenBox = box),
            ),
          ),
        if (_setup.boxes.isEmpty)
          _loadingCard(
            _setup.phase == SetupPhase.scanning
                ? 'Looking for your box…'
                : 'No boxes found yet',
            'Keep Bluetooth on and your box powered up.',
            loading: false,
          ),
        const SizedBox(height: 20),
        Text(
          'Already connected to Wi-Fi? Find your box in the player list.',
          style: _bodyStyle.copyWith(fontSize: 13),
        ),
      ],
      if (_setup.error != null) _note(_setup.error!, error: true),
    ];
  }

  Widget _choice({
    required IconData icon,
    required String title,
    required String subtitle,
    bool selected = false,
    VoidCallback? onTap,
  }) => Semantics(
    selected: selected,
    button: true,
    enabled: onTap != null,
    child: Material(
      color: selected
          ? KalinkaColors.accentSubtle
          : KalinkaColors.surfaceRaised,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: selected ? KalinkaColors.accent : KalinkaColors.borderDefault,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 17),
          child: Row(
            children: [
              Icon(
                icon,
                size: 24,
                color: selected
                    ? KalinkaColors.accentTint
                    : KalinkaColors.textMuted,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: KalinkaTextStyles.trayRowLabel.copyWith(
                        fontSize: 16,
                        color: onTap == null
                            ? KalinkaColors.textMuted
                            : KalinkaColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(subtitle, style: _bodyStyle.copyWith(fontSize: 12)),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Icon(
                selected
                    ? Icons.radio_button_checked_rounded
                    : onTap == null
                    ? Icons.lock_outline_rounded
                    : Icons.radio_button_unchecked_rounded,
                size: 22,
                color: selected
                    ? KalinkaColors.accentTint
                    : KalinkaColors.textMuted,
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _loadingCard(String title, String subtitle, {bool loading = true}) =>
      Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: KalinkaColors.surfaceRaised,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: KalinkaColors.borderDefault),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (loading) ...[
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: KalinkaColors.accentTint,
                    semanticsLabel: title,
                  ),
                ),
              ),
              const SizedBox(width: 14),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: KalinkaTextStyles.trayRowLabel.copyWith(
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(subtitle, style: _bodyStyle),
                ],
              ),
            ),
          ],
        ),
      );

  List<Widget> _networkContent() => [
    _heading(
      _networkChosen
          ? (_customSsid ? 'Add your Wi-Fi.' : 'Make yourself at home.')
          : 'Choose your Wi-Fi.',
      icon: _networkChosen ? null : Icons.wifi_rounded,
    ),
    _deck(
      _networkChosen
          ? (_customSsid
                ? 'Enter the exact name and password for your network.'
                : 'Enter the password for your network.')
          : 'Connect ${_setup.selected?.name ?? 'your box'} to the same network as your phone.',
    ),
    if (_setup.scanningWifi)
      _loadingCard('Finding networks…', 'Your box is looking for Wi-Fi nearby.')
    else if (!_networkChosen) ...[
      Row(
        children: [
          Expanded(
            child: Text(
              'AVAILABLE NETWORKS',
              style: KalinkaTextStyles.sectionHeaderMuted,
            ),
          ),
          if (_setup.status?.canScanWifi == true)
            IconButton(
              tooltip: 'Scan again',
              onPressed: () => _setup.scanWifi(_country.text.toUpperCase()),
              icon: const Icon(
                Icons.refresh_rounded,
                color: KalinkaColors.textSecondary,
              ),
            ),
        ],
      ),
      const SizedBox(height: 10),
      for (final network in _setup.networks)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _choice(
            icon: network.signal >= -65
                ? Icons.wifi_rounded
                : Icons.network_wifi_2_bar_rounded,
            title: network.ssid,
            subtitle: network.description,
            onTap: network.supported ? () => _chooseNetwork(network) : null,
          ),
        ),
      if (_setup.networks.isEmpty && _setup.wifiScanError == null)
        Text(
          'No networks found. Try scanning again, or enter a hidden network.',
          style: _bodyStyle,
        ),
      if (_setup.wifiScanError != null)
        _note(_setup.wifiScanError!, error: true),
    ] else
      _credentials(),
    if (_setup.error != null) _note(_setup.error!, error: true),
    if (_setup.status?.isTest == true)
      _note('Test box · Sample networks. Your laptop’s Wi-Fi stays unchanged.'),
  ];

  Widget _credentials() => Form(
    key: _form,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_customSsid) ...[
          TextFormField(
            key: const ValueKey('custom-ssid'),
            controller: _ssid,
            autocorrect: false,
            textInputAction: TextInputAction.next,
            decoration: kalinkaFieldDecoration(
              hint: 'Exact network name',
            ).copyWith(labelText: 'Network name (SSID)'),
            validator: (value) =>
                value == null ||
                    utf8.encode(value).isEmpty ||
                    utf8.encode(value).length > 32 ||
                    value.runes.any((c) => c < 32 || c == 127)
                ? 'Enter the exact network name (up to 32 bytes).'
                : null,
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: _showNetworks,
              child: const Text('Choose from available networks'),
            ),
          ),
        ] else
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 4, 12),
            decoration: BoxDecoration(
              color: KalinkaColors.surfaceRaised,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: KalinkaColors.borderDefault),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.wifi_rounded,
                  color: KalinkaColors.accentTint,
                  size: 24,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'YOUR NETWORK',
                        style: KalinkaTextStyles.sectionHeaderMuted.copyWith(
                          fontSize: 9,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _ssid.text,
                        style: KalinkaTextStyles.trayRowLabel.copyWith(
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: _showNetworks,
                  child: const Text('Change'),
                ),
              ],
            ),
          ),
        const SizedBox(height: 24),
        TextFormField(
          key: const ValueKey('wifi-password'),
          controller: _password,
          obscureText: !_showPassword,
          autocorrect: false,
          enableSuggestions: false,
          textInputAction: TextInputAction.done,
          onFieldSubmitted: (_) => _submit(),
          decoration: kalinkaFieldDecoration(hint: 'Wi-Fi password').copyWith(
            labelText: 'Password',
            suffixIcon: IconButton(
              tooltip: _showPassword ? 'Hide password' : 'Show password',
              icon: Icon(
                _showPassword
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
              ),
              onPressed: () => setState(() => _showPassword = !_showPassword),
            ),
          ),
          validator: (value) =>
              value == null ||
                  value.length < 8 ||
                  value.length > 63 ||
                  value.runes.any((c) => c < 32 || c > 126)
              ? 'Enter a password with 8–63 characters.'
              : null,
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.lock_outline_rounded,
              size: 15,
              color: KalinkaColors.textMuted,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Sent securely to your box.',
                style: _bodyStyle.copyWith(fontSize: 12),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: EdgeInsets.zero,
            childrenPadding: const EdgeInsets.only(bottom: 12),
            initiallyExpanded: _advanced,
            onExpansionChanged: (value) => _advanced = value,
            title: Text('Advanced', style: _bodyStyle.copyWith(fontSize: 13)),
            subtitle: Text(
              'Wi-Fi region · ${_country.text.toUpperCase()}',
              style: _bodyStyle.copyWith(fontSize: 12),
            ),
            children: [
              TextFormField(
                controller: _country,
                maxLength: 2,
                autocorrect: false,
                textCapitalization: TextCapitalization.characters,
                decoration: kalinkaFieldDecoration(hint: 'GB').copyWith(
                  labelText: 'Country code',
                  helperText:
                      'For example GB or US. Used for local Wi-Fi channels.',
                ),
                validator: (value) =>
                    RegExp(r'^[A-Z]{2}$').hasMatch(value?.toUpperCase() ?? '')
                    ? null
                    : 'Enter a two-letter country code.',
              ),
            ],
          ),
        ),
      ],
    ),
  );

  List<Widget> _progressContent() {
    final reaching = _setup.phase == SetupPhase.reaching;
    final failed = _setup.error != null;
    final changing = _setup.phase == SetupPhase.changingNetwork;
    final stage = reaching
        ? 3
        : switch (_setup.wifiStage) {
            WifiJoinStage.gettingAddress => 1,
            WifiJoinStage.saving || WifiJoinStage.connected => 2,
            _ => 0,
          };
    final messages = [
      'Authenticating with your router…',
      'Waiting for an IP address…',
      'Saving the network on your box…',
      'Waiting for Kalinka to respond…',
    ];
    return [
      _heading(
        failed
            ? (reaching
                  ? 'Couldn’t reach Kalinka.'
                  : 'Couldn’t connect your box.')
            : changing
            ? 'Choose a fresh connection.'
            : reaching
            ? 'Your box is on Wi-Fi.'
            : 'Bringing your box online.',
        icon: failed
            ? Icons.error_outline_rounded
            : changing
            ? Icons.wifi_find_rounded
            : reaching
            ? Icons.check_rounded
            : Icons.speaker_outlined,
      ),
      _deck(
        failed
            ? 'Retry this step, or go back to review your network.'
            : changing
            ? 'Stopping the previous attempt. Your saved networks will be kept.'
            : reaching
            ? 'Keep your phone on the same network.\nWe’re connecting you to Kalinka.'
            : 'Connecting to ${_ssid.text.isEmpty ? 'your network' : _ssid.text}.',
      ),
      if (changing)
        _loadingCard(
          'Preparing the network list…',
          'Restoring settings before you choose again.',
        )
      else
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: KalinkaColors.surfaceRaised,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: KalinkaColors.borderDefault),
          ),
          child: Column(
            children: [
              for (var i = 0; i < 4; i++)
                Padding(
                  padding: EdgeInsets.only(bottom: i == 3 ? 0 : 24),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (i == stage && !failed)
                        const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: KalinkaColors.accentTint,
                          ),
                        )
                      else
                        Icon(
                          i == stage && failed
                              ? Icons.cancel_rounded
                              : i < stage
                              ? Icons.check_circle_rounded
                              : Icons.circle_outlined,
                          size: 20,
                          color: i == stage && failed
                              ? KalinkaColors.actionDeleteLight
                              : i < stage
                              ? KalinkaColors.statusOnlineLight
                              : KalinkaColors.textMuted,
                          semanticLabel: i == stage && failed ? 'Failed' : null,
                        ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              [
                                'Join Wi-Fi',
                                'Get a network address',
                                'Save your network',
                                'Connect to Kalinka',
                              ][i],
                              style: KalinkaTextStyles.trayRowLabel.copyWith(
                                fontSize: 15,
                                color: i <= stage
                                    ? KalinkaColors.textPrimary
                                    : KalinkaColors.textMuted,
                              ),
                            ),
                            if (i == stage) ...[
                              const SizedBox(height: 5),
                              Text(
                                failed ? _setup.error! : messages[i],
                                style: _bodyStyle.copyWith(fontSize: 12),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
    ];
  }

  Widget _footer() {
    final phase = _setup.phase;
    final retry =
        _setup.error != null &&
        _setup.selected != null &&
        (phase == SetupPhase.choosing ||
            phase == SetupPhase.joining ||
            phase == SetupPhase.reaching);
    String label = 'Connect';
    VoidCallback? action;
    String? hint;
    if (retry) {
      label = 'Retry';
      action = _retry;
    } else if (_boxStep) {
      if (phase == SetupPhase.connecting) {
        label = 'Connecting…';
      } else if (_chosenBox != null &&
          _setup.boxes.any((box) => box.id == _chosenBox!.id)) {
        action = () => _selectBox(_chosenBox!);
      } else if (phase == SetupPhase.choosing) {
        label = 'Search again';
        action = _setup.scan;
      }
      hint = 'First your connection. Then your music.';
    } else if (phase == SetupPhase.credentials) {
      label = _networkChosen ? 'Connect to Wi-Fi' : 'Enter custom SSID';
      if (!_setup.scanningWifi) {
        action = _networkChosen ? _submit : () => _chooseNetwork(null);
      }
      hint = _networkChosen ? null : 'Can’t find your network?';
    } else {
      label = phase == SetupPhase.changingNetwork
          ? 'Preparing…'
          : 'Connecting…';
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 14, 24, 18),
      decoration: const BoxDecoration(
        color: KalinkaColors.background,
        border: Border(top: BorderSide(color: KalinkaColors.borderSubtle)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (hint != null && MediaQuery.viewInsetsOf(context).bottom == 0) ...[
            Text(
              hint,
              textAlign: TextAlign.center,
              style: _bodyStyle.copyWith(fontSize: 12),
            ),
            const SizedBox(height: 12),
          ],
          LayoutBuilder(
            builder: (context, constraints) {
              final back = KalinkaButton(
                label: 'Back',
                variant: KalinkaButtonVariant.neutral,
                enabled: phase != SetupPhase.changingNetwork,
                onTap: _back,
              );
              final primary = KalinkaButton(
                label: label,
                variant: phase == SetupPhase.credentials && !_networkChosen
                    ? KalinkaButtonVariant.neutral
                    : KalinkaButtonVariant.accent,
                onTap: action,
                enabled: action != null,
                fullWidth: true,
              );
              // Keep both labels readable with large text on narrow phones.
              final labels = TextPainter(
                text: TextSpan(
                  text: 'Back$label',
                  style: KalinkaTextStyles.trayRowLabel.copyWith(
                    fontSize: KalinkaTypography.baseSize + 3,
                  ),
                ),
                textDirection: Directionality.of(context),
                textScaler: MediaQuery.textScalerOf(context),
              )..layout();
              final stacked = labels.width + 92 > constraints.maxWidth;
              labels.dispose();
              if (stacked) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [primary, const SizedBox(height: 8), back],
                );
              }
              return Row(
                children: [
                  back,
                  const SizedBox(width: 12),
                  Expanded(child: primary),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
