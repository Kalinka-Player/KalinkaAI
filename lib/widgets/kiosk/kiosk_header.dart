import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../data_model/data_model.dart';
import '../../providers/app_state_provider.dart';
import '../../providers/connection_settings_provider.dart';
import '../../providers/connection_state_provider.dart';
import '../../providers/kiosk_provider.dart';
import '../../providers/renderer_host_provider.dart'
    show rendererIdentityProvider;
import '../../providers/renderer_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/local_platform.dart';
import '../../utils/click_cursor.dart';
import '../keyboard/keyboard_activation.dart';
import '../renderer_switcher.dart' show rendererDisplayName;
import 'kiosk_track_text.dart' show kioskTextPolish;

/// The name a renderer gives itself until someone names it.
const _defaultRendererPrefix = 'Kalinka Renderer on ';

/// The Pi can drive a TV independently of where audio plays. Use the same
/// renderer name as its settings screen even when both run on the same host.
({String name, bool showThisDevice}) kioskOutputLabel(
  RendererInfo renderer, {
  required bool isSelf,
  required bool localDisplay,
}) {
  final name = rendererDisplayName(renderer, isSelf: isSelf);
  if (localDisplay) return (name: name, showThisDevice: false);
  return (
    name:
        name.startsWith(_defaultRendererPrefix) &&
            name.length > _defaultRendererPrefix.length
        ? name.substring(_defaultRendererPrefix.length)
        : name,
    showThisDevice:
        !isSelf &&
        renderer.hostname.isNotEmpty &&
        renderer.hostname.toLowerCase() == localHostname()?.toLowerCase(),
  );
}

/// The label for the active playback output, if one is connected.
({String name, bool showThisDevice})? watchKioskOutput(WidgetRef ref) {
  final ownId = ref.watch(rendererIdentityProvider).value?.rendererId;
  final localDisplay = ref.watch(localDisplayKioskProvider);
  return ref.watch(
    rendererListProvider.select((s) {
      final active = s.active;
      if (active == null) return null;
      return kioskOutputLabel(
        active,
        isSelf: active.rendererId == ownId,
        localDisplay: localDisplay,
      );
    }),
  );
}

/// The Kalinka wordmark, over the line that says what it is where there is
/// room for it.
class KioskLogo extends StatelessWidget {
  final double scale;

  /// `OPEN SOURCE MUSIC STREAMER` under the wordmark.
  final bool tagline;

  /// A hairline of shade under the mark, as polish over a cover.
  final bool shadowed;

  const KioskLogo({
    super.key,
    required this.scale,
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
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (shadowed)
          Stack(
            clipBehavior: Clip.none,
            children: [
              // Match the one-pixel shade under text over the cover.
              ExcludeSemantics(
                child: Transform.translate(
                  offset: const Offset(0, 1),
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
  final FocusNode? focusNode;

  const KioskOutputPill({
    super.key,
    required this.scale,
    this.onTap,
    this.focusNode,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connected =
        ref.watch(connectionStateProvider) == ConnectionStatus.connected;
    final serverName = ref.watch(
      connectionSettingsProvider.select((s) => s.name),
    );

    return connected
        ? _Output(
            scale: scale,
            serverName: serverName,
            onTap: onTap,
            focusNode: focusNode,
          )
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
  final FocusNode? focusNode;

  const _Output({
    required this.scale,
    required this.serverName,
    required this.onTap,
    required this.focusNode,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    double s(double v) => v * scale;
    final output = watchKioskOutput(ref);
    final control = ref.watch(playbackControlProvider);
    final name = output?.name ?? serverName;
    final showThisDevice = output?.showThisDevice ?? false;
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
        if (showThisDevice)
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
      label: 'Output: ${showThisDevice ? 'This device' : name}',
      button: onTap != null,
      child: KeyboardActivation(
        focusNode: focusNode,
        onActivate: onTap,
        borderRadius: BorderRadius.circular(s(24)),
        child: MouseRegion(
          cursor: clickCursor(interactive: onTap != null),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: ExcludeSemantics(
              child: _Pill(scale: scale, child: row),
            ),
          ),
        ),
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
            'Waiting for $serverName…',
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
