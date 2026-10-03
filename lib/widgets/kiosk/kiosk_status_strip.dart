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
import '../renderer_switcher.dart' show rendererDisplayName, showRendererPicker;

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

/// Where the music plays, and whether the server can be reached — the two
/// kept apart, so an idle output never reads as a lost one — with the Kalinka
/// mark between them and the clock. Tapping the output opens the output
/// picker.
class KioskStatusStrip extends ConsumerWidget {
  final double scale;

  /// False while the display rests: the touch that wakes it must not open
  /// the picker.
  final bool interactive;

  /// False on a locked display: the output is shown, not changed from here.
  final bool canPickOutput;

  /// Sits at the far end of the strip: the clock, the exit button.
  final Widget? trailing;

  /// Each tap on the Kalinka mark, for the way out of a device-locked
  /// display.
  final VoidCallback? onLogoTap;

  /// Narrow screens: the "K" mark leads the strip instead of the wordmark
  /// taking its centre.
  final bool compact;

  const KioskStatusStrip({
    super.key,
    required this.scale,
    this.interactive = true,
    this.canPickOutput = true,
    this.trailing,
    this.onLogoTap,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    double s(double v) => v * scale;
    final connected =
        ref.watch(connectionStateProvider) == ConnectionStatus.connected;
    final serverName = ref.watch(
      connectionSettingsProvider.select((s) => s.name),
    );

    final Widget where = connected
        ? IgnorePointer(
            ignoring: !interactive,
            child: _Output(
              scale: scale,
              serverName: serverName,
              canPick: canPickOutput,
            ),
          )
        : _Reconnecting(scale: scale, serverName: serverName);

    return SizedBox(
      height: s(44),
      child: Row(children: compact ? _compact(s, where) : _wide(s, where)),
    );
  }
}

extension on KioskStatusStrip {
  Widget _mark(String asset, double height) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: onLogoTap,
    child: SvgPicture.asset(asset, height: height, semanticsLabel: 'Kalinka'),
  );

  // Equal halves either side keep the wordmark at the true centre; a long
  // output name ellipsises in its half rather than pushing it along.
  List<Widget> _wide(double Function(double) s, Widget where) => [
    Expanded(child: where),
    SizedBox(width: s(16)),
    _mark('assets/images/kalinka_logo.svg', s(26)),
    SizedBox(width: s(16)),
    Expanded(
      child: Align(
        alignment: Alignment.centerRight,
        child: trailing ?? const SizedBox.shrink(),
      ),
    ),
  ];

  List<Widget> _compact(double Function(double) s, Widget where) => [
    _mark('assets/images/kalinka_icon.svg', s(26)),
    SizedBox(width: s(14)),
    Expanded(child: where),
    SizedBox(width: s(16)),
    ?trailing,
  ];
}

class _Output extends ConsumerWidget {
  final double scale;
  final String serverName;
  final bool canPick;

  const _Output({
    required this.scale,
    required this.serverName,
    required this.canPick,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    double s(double v) => v * scale;
    final ownId = ref.watch(rendererIdentityProvider).value?.rendererId;
    final output = ref.watch(
      rendererListProvider.select((s) {
        final active = s.active;
        if (active == null) return null;
        final isSelf = active.rendererId == ownId;
        final host = localHostname()?.toLowerCase();
        return (
          name: kioskOutputName(active, isSelf: isSelf),
          // The browser's own renderer already calls itself "This browser".
          here:
              !isSelf &&
              host != null &&
              active.hostname.isNotEmpty &&
              active.hostname.toLowerCase() == host,
        );
      }),
    );
    final pickerAvailable =
        canPick &&
        ref.watch(rendererListProvider.select((s) => s.switcherVisible));
    final control = ref.watch(playbackControlProvider);
    final name = output?.name ?? serverName;
    // On this device the chip says all there is to say: its own name would
    // only repeat what is standing in front of the viewer.
    final here = output?.here ?? false;
    final nameStyle = KalinkaFonts.mono(
      fontSize: s(17),
      color: KalinkaColors.textPrimary,
    );
    final via = control.isExclusive ? 'via ${control.title}' : null;

    final row = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.speaker_outlined,
          size: s(20),
          color: KalinkaColors.textSecondary,
        ),
        SizedBox(width: s(10)),
        if (here)
          Container(
            padding: EdgeInsets.symmetric(horizontal: s(10), vertical: s(4)),
            decoration: BoxDecoration(
              border: Border.all(
                color: KalinkaColors.textPrimary.withValues(alpha: 0.28),
              ),
              borderRadius: BorderRadius.circular(s(6)),
            ),
            // Mono, like the clock and the stream line: it reads as a fact
            // about the setup rather than a name.
            child: Text(
              'THIS DEVICE',
              style: KalinkaFonts.mono(
                fontSize: s(14),
                color: KalinkaColors.textPrimary,
                height: 1.2,
              ),
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
          SizedBox(width: s(10)),
          Flexible(
            child: Text(
              '·  $via',
              style: nameStyle.copyWith(color: KalinkaColors.textSecondary),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ],
    );

    return Align(
      alignment: Alignment.centerLeft,
      child: Semantics(
        label: 'Output: ${here ? 'This device' : name}',
        button: pickerAvailable,
        excludeSemantics: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: pickerAvailable
              ? () => showRendererPicker(context, ref, configurable: false)
              : null,
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: s(8)),
            child: row,
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
