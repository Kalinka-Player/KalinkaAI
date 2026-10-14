import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../providers/provisioning_controller.dart';
import '../widgets/onboarding/onboarding_step_scaffold.dart';
import '../widgets/onboarding/step_network.dart';

/// The same network setup UI is hosted by the captive portal and the native app.
class NetworkSetupScreen extends StatefulWidget {
  final Uri endpoint;
  final bool hotspot;
  final VoidCallback? onReturnToDiscovery;
  const NetworkSetupScreen({
    super.key,
    required this.endpoint,
    this.hotspot = false,
    this.onReturnToDiscovery,
  });

  @override
  State<NetworkSetupScreen> createState() => _NetworkSetupScreenState();
}

class _NetworkSetupScreenState extends State<NetworkSetupScreen> {
  Map<String, dynamic>? _status;
  bool _submitted = false;
  bool _busy = false;
  bool get _needsActivation =>
      widget.hotspot && kIsWeb && Uri.base.host != '192.168.4.1';
  bool get _connected => (_status?['network'] as Map?)?['connected'] == true;

  Future<void> _continue() async {
    if (_needsActivation) {
      await launchUrl(
        Uri.parse('http://192.168.4.1/activate'),
        webOnlyWindowName: '_self',
      );
      return;
    }
    final network = _status?['network'] as Map?;
    final setup = _status?['setup'] as Map?;
    final host = _connected ? network!['address'] as String : 'kalinka.local';
    final port = setup?['port'] as int? ?? 8000;
    if (kIsWeb) {
      await launchUrl(
        Uri(scheme: 'http', host: host, port: port),
        webOnlyWindowName: '_self',
      );
    } else if (_connected) {
      Navigator.of(context).pop(
        ProvisionedEndpoint(
          'Kalinka',
          host,
          port,
          _status?['server_id'] as String?,
        ),
      );
    } else {
      (widget.onReturnToDiscovery ?? () => Navigator.of(context).pop())();
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: OnboardingStepScaffold(
      stepNumber: 1,
      stepCount: 1,
      stepLabels: const ['NETWORK'],
      title: 'Connect your box',
      subtitle: widget.hotspot
          ? 'In your device’s Wi-Fi settings, join Kalinka-Setup-XXXX with password kalinka-setup, then return here. Stay connected if your device says there is no internet.'
          : 'Keep your existing wired or Wi-Fi connection, or choose another network.',
      onBack: Navigator.of(context).canPop()
          ? () => Navigator.of(context).pop()
          : null,
      onNext: _continue,
      nextEnabled: _needsActivation || (_connected && !_busy) || _submitted,
      nextLabel: _needsActivation
          ? 'Open activation page'
          : _submitted && !_connected
          ? (kIsWeb ? 'Open player on home network' : 'Return to discovery')
          : 'Keep this connection',
      children: [
        if (!_needsActivation)
          NetworkSetupPanel(
            endpoint: widget.endpoint,
            onBusy: (busy) {
              if (mounted) setState(() => _busy = busy);
            },
            onStatus: (status) {
              if (mounted) {
                setState(() {
                  _status = status;
                  _submitted = status['submitted'] == true;
                });
              }
            },
          ),
      ],
    ),
  );
}
