import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

/// Bits the three sound-related wizard steps (output, amplifier control,
/// speaker test) share.

/// Asks the wizard to open one output's own settings. The panel is hosted
/// by [OnboardingScreen] over its own Stack rather than pushed as a route:
/// it is a [SlideInPanel], which animates itself in and expects a host that
/// supplies the Material its fields need.
typedef OpenRendererSettings =
    void Function(String rendererId, String rendererName);

/// The wizard's radio bullet.
class RadioMark extends StatelessWidget {
  final bool selected;

  const RadioMark({super.key, required this.selected});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: selected ? KalinkaColors.accent : KalinkaColors.borderDefault,
          width: 1.5,
        ),
      ),
      child: selected
          ? Center(
              child: Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: KalinkaColors.accent,
                ),
              ),
            )
          : null,
    );
  }
}

/// Full-width speaker-test CTA. Brass-tinted — prominent without
/// competing with the step's berry-accented Continue button.
class TestSoundButton extends StatelessWidget {
  final VoidCallback onTap;
  final bool enabled;

  const TestSoundButton({super.key, required this.onTap, this.enabled = true});

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1.0 : 0.4,
      child: Material(
        color: KalinkaColors.goldSubtle,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(13),
          side: BorderSide(color: KalinkaColors.gold.withValues(alpha: 0.35)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: enabled ? onTap : null,
          overlayColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.pressed) ||
                states.contains(WidgetState.hovered)) {
              return Colors.white.withValues(alpha: 0.06);
            }
            return null;
          }),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.volume_up_rounded,
                  size: 16,
                  color: KalinkaColors.gold,
                ),
                const SizedBox(width: 8),
                Text(
                  'Play test sound',
                  style: KalinkaTextStyles.trayRowLabel.copyWith(
                    fontSize: KalinkaTypography.baseSize + 3,
                    color: KalinkaColors.gold,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
