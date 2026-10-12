import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/renderer_host_provider.dart'
    show rendererIdentityProvider;
import '../../providers/renderer_provider.dart';
import '../../theme/app_theme.dart';
import '../kalinka_button.dart';
import '../renderer_switcher.dart' show rendererDisplayName, rendererDetail;
import '../settings_controls/settings_card.dart';
import '../settings_controls/warning_note.dart';
import 'onboarding_fields.dart';
import 'onboarding_step_scaffold.dart';
import 'sound_widgets.dart';

/// Wizard step: choose the output renderer the music plays on.
///
/// Lists the renderers connected to the server; tapping a row moves
/// playback there (live, like the app's output picker). Its sound card and
/// playback device come on the sound step. Offline rows stay visible for
/// context but can't be chosen. On a pre-renderer server the schema's ALSA device field renders
/// here instead. A missing output warns rather than traps: setup can
/// finish and the output can join later.
class OnboardingOutputStep extends ConsumerStatefulWidget {
  const OnboardingOutputStep({super.key});

  @override
  ConsumerState<OnboardingOutputStep> createState() =>
      _OnboardingOutputStepState();
}

class _OnboardingOutputStepState extends ConsumerState<OnboardingOutputStep> {
  @override
  void initState() {
    super.initState();
    // Renderers announce themselves to the server, not to the app — re-read
    // on entry so one that connected since the wizard started shows up.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(rendererListProvider.notifier).refresh();
    });
  }

  @override
  Widget build(BuildContext context) {
    final renderers = ref.watch(rendererListProvider);
    final ownId = ref.watch(rendererIdentityProvider).value?.rendererId;

    if (!renderers.supported) {
      // Pre-renderer server: the ALSA device field straight off the schema.
      return const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          OnboardingNote(
            'Connect your DAC or USB audio device first so it shows up in '
            'the list. For bit-perfect playback, pick a device that doesn’t '
            'do automatic conversion.',
          ),
          SettingsCard(
            children: [
              OnboardingFieldRow(
                path: 'base_config.output.alsa.device',
                label: 'Output device',
                help:
                    'Where the music comes out — your DAC, sound card '
                    'or HDMI output.',
              ),
            ],
          ),
        ],
      );
    }

    if (renderers.renderers.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          WarningNote(
            severity: WarningNoteSeverity.warning,
            message: renderers.loading
                ? 'Looking for outputs…'
                : 'No outputs connected — nothing can play yet. Install '
                      'the Kalinka renderer on the machine wired to your '
                      'speakers or DAC, or open the web player in a '
                      'browser. Setup can still finish without one.',
          ),
          const SizedBox(height: 12),
          KalinkaButton(
            label: 'Check again',
            variant: KalinkaButtonVariant.neutral,
            size: KalinkaButtonSize.compact,
            enabled: !renderers.loading,
            onTap: ref.read(rendererListProvider.notifier).refresh,
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SettingsCard(
          children: [
            for (final r in renderers.renderers)
              _OutputRow(
                name: rendererDisplayName(r, isSelf: r.rendererId == ownId),
                detail: rendererDetail(r, isSelf: r.rendererId == ownId),
                selected: r.active,
                connected: r.isConnected,
                onTap: () {
                  ref.read(rendererListProvider.notifier).select(r.rendererId);
                },
              ),
          ],
        ),
      ],
    );
  }
}

/// One output: radio mark, name and detail.
///
/// Built the way the player's output picker builds its rows: the whole row
/// carries the hover, with ink rather than a bare gesture — a row that
/// reacts to nothing under the pointer doesn't read as choosable.
class _OutputRow extends StatelessWidget {
  final String name;
  final String detail;
  final bool selected;
  final bool connected;
  final VoidCallback onTap;

  const _OutputRow({
    required this.name,
    required this.detail,
    required this.selected,
    required this.connected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final canChoose = connected && !selected;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      color: selected ? KalinkaColors.surfaceElevated : Colors.transparent,
      child: Material(
        color: Colors.transparent,
        child: Opacity(
          opacity: connected ? 1.0 : 0.45,
          child: Stack(
            children: [
              // Full-bleed and beneath the content, so hovering the name
              // lights the whole row.
              Positioned.fill(
                child: InkWell(
                  onTap: canChoose ? onTap : null,
                  // Selected and offline rows aren't targets; without this
                  // they would still light up under the pointer.
                  hoverColor: canChoose ? null : Colors.transparent,
                ),
              ),
              // Text hit-tests itself for selection, which would keep the
              // hover off the InkWell below. Nothing here is a target anyway.
              IgnorePointer(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 11, 8, 11),
                  child: Row(
                    children: [
                      RadioMark(selected: selected),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              style: KalinkaTextStyles.trayRowLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (detail.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                detail,
                                style: KalinkaTextStyles.trayRowSublabel,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
