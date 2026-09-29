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

  /// Sits at the far end of the strip: the clock, the exit button.
  final Widget? trailing;

  const KioskStatusStrip({
    super.key,
    required this.scale,
    this.interactive = true,
    this.trailing,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    double s(double v) => v * scale;
    final connected =
        ref.watch(connectionStateProvider) == ConnectionStatus.connected;
    final serverName = ref.watch(
      connectionSettingsProvider.select((s) => s.name),
    );

    return SizedBox(
      height: s(44),
      // Equal halves either side keep the mark at the true centre; a long
      // output name ellipsises in its half rather than pushing it along.
      child: Row(
        children: [
          Expanded(
            child: connected
                ? IgnorePointer(
                    ignoring: !interactive,
                    child: _Output(scale: scale, serverName: serverName),
                  )
                : _Reconnecting(scale: scale, serverName: serverName),
          ),
          SizedBox(width: s(16)),
          SvgPicture.asset(
            'assets/images/kalinka_logo.svg',
            height: s(20),
            semanticsLabel: 'Kalinka',
          ),
          SizedBox(width: s(16)),
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: trailing ?? const SizedBox.shrink(),
            ),
          ),
        ],
      ),
    );
  }
}

class _Output extends ConsumerWidget {
  final double scale;
  final String serverName;

  const _Output({required this.scale, required this.serverName});

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
    final pickerAvailable = ref.watch(
      rendererListProvider.select((s) => s.switcherVisible),
    );
    final control = ref.watch(playbackControlProvider);
    final name = output?.name ?? serverName;

    final row = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.speaker_outlined,
          size: s(20),
          color: KalinkaColors.textSecondary,
        ),
        SizedBox(width: s(10)),
        Flexible(
          child: Text.rich(
            TextSpan(
              text: name,
              children: [
                if (control.isExclusive)
                  TextSpan(
                    text: '  ·  via ${control.title}',
                    style: const TextStyle(
                      color: KalinkaColors.textSecondary,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
              ],
            ),
            style: KalinkaFonts.sans(
              fontSize: s(17),
              fontWeight: FontWeight.w500,
              color: KalinkaColors.textPrimary,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (output?.here ?? false) ...[
          SizedBox(width: s(10)),
          Container(
            padding: EdgeInsets.symmetric(horizontal: s(7), vertical: s(2)),
            decoration: BoxDecoration(
              border: Border.all(color: KalinkaColors.borderDefault),
              borderRadius: BorderRadius.circular(s(4)),
            ),
            child: Text(
              'This device',
              style: KalinkaFonts.sans(
                fontSize: s(12),
                color: KalinkaColors.textSecondary,
              ),
            ),
          ),
        ],
      ],
    );

    return Align(
      alignment: Alignment.centerLeft,
      child: Semantics(
        label: 'Output: $name',
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
