import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../providers/network_setup_api.dart';
import '../providers/provisioning_controller.dart';
import '../widgets/onboarding/onboarding_step_scaffold.dart';
import 'network_setup_screen.dart';
import 'provisioning_screen.dart';

/// Entry choices for a box that has not yet joined the home network.
class SetupMethodScreen extends StatelessWidget {
  const SetupMethodScreen({super.key});

  Future<void> _open(BuildContext context, Widget screen) async {
    final result = await Navigator.of(context)
        .push<ProvisionedEndpoint>(MaterialPageRoute(builder: (_) => screen));
    if (context.mounted && result != null) {
      Navigator.of(context).pop(result);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: OnboardingStepScaffold(
      stepNumber: 1,
      stepCount: 1,
      title: 'Set up a box',
      subtitle: 'Choose how to send your network settings. You can also connect the box to your router with an Ethernet cable.',
      onBack: () => Navigator.of(context).pop(),
      children: [
        ListTile(
          leading: const Icon(Icons.bluetooth),
          title: const Text('Search using Bluetooth'),
          subtitle: Text(
            kIsWeb
                ? 'Available in the Kalinka native app.'
                : 'Find nearby boxes and send Wi-Fi settings over Bluetooth.',
          ),
          enabled: !kIsWeb,
          onTap: kIsWeb
              ? null
              : () => _open(context, const ProvisioningScreen()),
        ),
        ListTile(
          leading: const Icon(Icons.wifi),
          title: const Text('Use the temporary Wi-Fi hotspot'),
          subtitle: const Text(
            'Join Kalinka-Setup-XXXX in Wi-Fi settings. Password: kalinka-setup. The activation page opens Network setup.',
          ),
          onTap: () async {
            await _open(
              context,
              NetworkSetupScreen(
                endpoint: Uri.http(hotspotAddress),
                hotspot: true,
                onReturnToDiscovery: () {
                  final navigator = Navigator.of(context);
                  navigator.popUntil(
                    (route) => route == ModalRoute.of(context),
                  );
                  navigator.pop();
                },
              ),
            );
          },
        ),
      ],
    ),
  );
}
