import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../data_model/data_model.dart';
import '../../providers/app_state_provider.dart';
import '../../providers/connection_settings_provider.dart';
import '../../providers/connection_state_provider.dart';
import '../../providers/renderer_host_provider.dart'
    show rendererIdentityProvider;
import '../../providers/renderer_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/local_platform.dart';
import '../renderer_switcher.dart' show rendererDisplayName;
import 'kiosk_track_text.dart' show kioskTextPolish;

/// The name a renderer gives itself until someone names it.
const _defaultRendererPrefix = 'Kalinka Renderer on ';

/// How the display names an output: what it was called, or, left at the
/// renderer's default, just the machine it runs on.
String kioskOutputName(RendererInfo renderer, {required bool isSelf}) {
  final name = rendererDisplayName(renderer, isSelf: isSelf);
  if (name.startsWith(_defaultRendererPrefix) &&
      name.length > _defaultRendererPrefix.length) {
    return name.substring(_defaultRendererPrefix.length);
  }
  return name;
}

/// The output playback is on, as the display names it, and whether it is the
/// machine the display runs on; null when no output is connected.
({String name, bool here})? watchKioskOutput(WidgetRef ref) {
  final ownId = ref.watch(rendererIdentityProvider).value?.rendererId;
  return ref.watch(
    rendererListProvider.select((s) {
      final active = s.active;
      if (active == null) return null;
      final isSelf = active.rendererId == ownId;
      return (
        name: kioskOutputName(active, isSelf: isSelf),
        // The browser's own renderer already calls itself "This browser".
        here: !isSelf && kioskRunsOn(active),
      );
    }),
  );
}

/// Whether [renderer] runs on the machine the display does.
bool kioskRunsOn(RendererInfo renderer) {
  final host = localHostname()?.toLowerCase();
  return host != null &&
      renderer.hostname.isNotEmpty &&
      renderer.hostname.toLowerCase() == host;
}

/// The Kalinka wordmark, over the line that says what it is where there is
/// room for it. Tapping it is the way out of a device-locked display.
class KioskLogo extends StatelessWidget {
  final double scale;

  /// Each tap on the mark.
  final VoidCallback? onTap;

  /// `OPEN SOURCE MUSIC STREAMER` under the wordmark.
  final bool tagline;

  /// A hairline of shade under the mark, as polish over a cover.
  final bool shadowed;

  const KioskLogo({
    super.key,
    required this.scale,
    this.onTap,
    this.tagline = false,
    this.shadowed = false,
  });

  @override
  Widget build(BuildContext context) {
    double s(double v) => v * scale;
    const asset = 'assets/images/kalinka_logo.svg';
    final mark = SvgPicture.asset(
      asset,
      height: s(52),
      semanticsLabel: 'Kalinka',
    );
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (shadowed)
            Stack(
              clipBehavior: Clip.none,
              children: [
                // The mark's own shape, dark, softened and a pixel lower —
                // the same shade the text over the cover wears.
                ExcludeSemantics(
                  child: Transform.translate(
                    offset: const Offset(0, 1),
                    child: ImageFiltered(
                      imageFilter: ImageFilter.blur(sigmaX: 1.5, sigmaY: 1.5),
                      child: SvgPicture.asset(
                        asset,
                        height: s(52),
                        colorFilter: const ColorFilter.mode(
                          Color(0x59000000),
                          BlendMode.srcIn,
                        ),
                      ),
                    ),
                  ),
                ),
                mark,
              ],
            )
          else
            mark,
          if (tagline) ...[
            SizedBox(height: s(8)),
            ExcludeSemantics(
              child: Text(
                'OPEN SOURCE MUSIC STREAMER',
                style: KalinkaFonts.mono(
                  fontSize: s(11),
                  letterSpacing: s(2.9),
                  color: KalinkaColors.textPrimary.withValues(alpha: 0.82),
                  height: 1,
                ).copyWith(shadows: shadowed ? kioskTextPolish : null),
                maxLines: 1,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Where the music plays, in a pill: the output's name, or that the server
/// cannot be reached — the two kept apart, so an idle output never reads as
/// a lost one. Wears a chevron when it opens something.
class KioskOutputPill extends ConsumerWidget {
  final double scale;

  /// Opens the output panel; null where there is nothing in it to use.
  final VoidCallback? onTap;

  const KioskOutputPill({super.key, required this.scale, this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connected =
        ref.watch(connectionStateProvider) == ConnectionStatus.connected;
    final serverName = ref.watch(
      connectionSettingsProvider.select((s) => s.name),
    );

    return connected
        ? _Output(scale: scale, serverName: serverName, onTap: onTap)
        : _Pill(
            scale: scale,
            child: _Reconnecting(scale: scale, serverName: serverName),
          );
  }
}

class _Pill extends StatelessWidget {
  final double scale;
  final Widget child;

  const _Pill({required this.scale, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48 * scale,
      padding: EdgeInsets.symmetric(horizontal: 20 * scale),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.36),
        borderRadius: BorderRadius.circular(24 * scale),
        border: Border.all(
          color: KalinkaColors.textPrimary.withValues(alpha: 0.14),
        ),
      ),
      child: child,
    );
  }
}

class _Output extends ConsumerWidget {
  final double scale;
  final String serverName;
  final VoidCallback? onTap;

  const _Output({
    required this.scale,
    required this.serverName,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    double s(double v) => v * scale;
    final output = watchKioskOutput(ref);
    final control = ref.watch(playbackControlProvider);
    final name = output?.name ?? serverName;
    // On this device the chip says all there is to say: its own name would
    // only repeat what is standing in front of the viewer.
    final here = output?.here ?? false;
    final nameStyle = KalinkaFonts.sans(
      fontSize: s(17),
      fontWeight: FontWeight.w500,
      color: KalinkaColors.textPrimary,
      height: 1.2,
    );
    final via = control.isExclusive ? 'via ${control.title}' : null;

    final row = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.volume_up_outlined,
          size: s(24),
          color: KalinkaColors.textPrimary,
        ),
        SizedBox(width: s(12)),
        if (here)
          // Mono, like the clock and the stream line: it reads as a fact
          // about the setup rather than a name.
          Flexible(
            child: Text(
              'THIS DEVICE',
              style: KalinkaFonts.mono(
                fontSize: s(14),
                letterSpacing: s(1),
                color: KalinkaColors.textPrimary,
                height: 1.2,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          )
        else
          Flexible(
            child: Text(
              name,
              style: nameStyle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        if (via != null) ...[
          SizedBox(width: s(8)),
          Flexible(
            child: Text(
              '·  $via',
              style: nameStyle.copyWith(
                color: KalinkaColors.textSecondary,
                fontWeight: FontWeight.w400,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
        if (onTap != null) ...[
          SizedBox(width: s(10)),
          Icon(
            Icons.keyboard_arrow_down_rounded,
            size: s(24),
            color: KalinkaColors.textPrimary.withValues(alpha: 0.8),
          ),
        ],
      ],
    );

    return Semantics(
      label: 'Output: ${here ? 'This device' : name}',
      button: onTap != null,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: _Pill(scale: scale, child: row),
      ),
    );
  }
}

class _Reconnecting extends StatelessWidget {
  final double scale;
  final String serverName;

  const _Reconnecting({required this.scale, required this.serverName});

  @override
  Widget build(BuildContext context) {
    double s(double v) => v * scale;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: s(14),
          height: s(14),
          child: CircularProgressIndicator(
            strokeWidth: s(2),
            valueColor: const AlwaysStoppedAnimation(
              KalinkaColors.statusPending,
            ),
          ),
        ),
        SizedBox(width: s(12)),
        Flexible(
          child: Text(
            'Reconnecting to $serverName…',
            style: KalinkaFonts.sans(
              fontSize: s(17),
              fontWeight: FontWeight.w500,
              color: KalinkaColors.textPrimary,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
