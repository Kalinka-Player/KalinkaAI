import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/app_theme.dart';

/// Instructions available before the device can reach the box's hotspot.
class HotspotSetupGuide extends StatelessWidget {
  static const password = 'kalinka-setup';

  const HotspotSetupGuide({super.key});

  Future<void> _copyPassword(BuildContext context) async {
    var message = 'Hotspot password copied';
    try {
      await Clipboard.setData(const ClipboardData(text: password));
    } on PlatformException {
      message = 'Could not copy. Select the password to copy it manually.';
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _GuideStep(
          icon: Icons.wifi_rounded,
          title: '1 · Open Wi-Fi settings',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SelectableText('Kalinka-Setup-XXXX'),
              SizedBox(height: 8),
              Text(
                'Choose the network starting with Kalinka-Setup-. The last four characters identify your streamer.',
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _GuideStep(
          icon: Icons.key_rounded,
          title: '2 · Enter this password',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SelectableText(
                password,
                style: KalinkaFonts.mono(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: KalinkaColors.textPrimary,
                ),
              ),
              TextButton.icon(
                onPressed: () => _copyPassword(context),
                style: TextButton.styleFrom(
                  foregroundColor: KalinkaColors.accentTint,
                  minimumSize: const Size(48, 48),
                ),
                icon: const Icon(Icons.copy_rounded, size: 20),
                label: const Text('Copy password'),
              ),
              const Text(
                'All lowercase, with a hyphen. This password is for the streamer’s hotspot.',
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const _GuideStep(
          icon: Icons.language_rounded,
          title: '3 · Open network setup',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Stay connected if your device says “No internet”. Return here, or open this address in your browser:',
              ),
              SizedBox(height: 8),
              SelectableText('http://192.168.4.1'),
              SizedBox(height: 8),
              Text('Then choose your home Wi-Fi and enter its password.'),
            ],
          ),
        ),
        const SizedBox(height: 24),
      ],
    ),
  );
}

class _GuideStep extends StatelessWidget {
  final IconData icon;
  final String title;
  final Widget child;

  const _GuideStep({
    required this.icon,
    required this.title,
    required this.child,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: KalinkaColors.surfaceRaised,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: KalinkaColors.borderDefault),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ExcludeSemantics(
              child: Icon(icon, size: 24, color: KalinkaColors.accentTint),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(title, style: KalinkaTextStyles.trayRowLabel)),
          ],
        ),
        const SizedBox(height: 12),
        DefaultTextStyle(
          style: KalinkaTextStyles.trayRowSublabel.copyWith(
            fontSize: 16,
            height: 1.5,
          ),
          child: child,
        ),
      ],
    ),
  );
}
