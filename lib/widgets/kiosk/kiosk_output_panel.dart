import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data_model/data_model.dart' show RendererInfo;
import '../../providers/app_state_provider.dart';
import '../../providers/kalinka_player_api_provider.dart'
    show RendererSwitchException;
import '../../providers/renderer_host_provider.dart'
    show rendererIdentityProvider;
import '../../providers/renderer_provider.dart';
import '../../theme/app_theme.dart';
import '../renderer_switcher.dart' show rendererDetail, rendererDisplayName;
import 'kiosk_header.dart';
import 'kiosk_volume_control.dart';

/// Where the music plays and how loud: the output playback is on, its
/// volume, and under it the other outputs it could move to. Opened from the
/// output pill, over the display.
class KioskOutputPanel extends ConsumerStatefulWidget {
  final double scale;

  /// Over the whole screen, for one too small to float a panel on.
  final bool fullScreen;

  /// False on a locked display: the output is shown, not changed from here.
  final bool canPick;

  final VoidCallback onClose;

  const KioskOutputPanel({
    super.key,
    required this.scale,
    required this.fullScreen,
    required this.canPick,
    required this.onClose,
  });

  @override
  ConsumerState<KioskOutputPanel> createState() => _KioskOutputPanelState();
}

class _KioskOutputPanelState extends ConsumerState<KioskOutputPanel> {
  bool _switching = false;
  String? _error;

  Future<void> _select(RendererInfo renderer, String name) async {
    setState(() {
      _switching = true;
      _error = null;
    });
    try {
      await ref
          .read(rendererListProvider.notifier)
          .select(renderer.rendererId, rendererName: name);
      if (mounted) widget.onClose();
    } on RendererSwitchException catch (e) {
      if (mounted) {
        setState(() {
          _switching = false;
          _error = e.message;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _switching = false;
          _error = 'Couldn’t switch output';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    double s(double v) => v * widget.scale;
    final output = watchKioskOutput(ref);
    final volume = ref.watch(volumeAvailableProvider);
    final list = ref.watch(rendererListProvider);
    final ownId = ref.watch(rendererIdentityProvider).value?.rendererId;
    final others = [
      for (final r in list.renderers)
        if (!r.active) r,
    ];
    // Nothing else to go to, nothing to show.
    final showOthers =
        widget.canPick && list.switcherVisible && others.isNotEmpty;

    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Label('PLAYING ON', scale: widget.scale, accent: true),
                  SizedBox(height: s(8)),
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          output == null
                              ? 'No output'
                              : (output.here ? 'This device' : output.name),
                          style: KalinkaFonts.display(
                            fontSize: s(28),
                            fontWeight: FontWeight.w500,
                            color: KalinkaColors.frost,
                            height: 1.15,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (_switching) ...[
                        SizedBox(width: s(12)),
                        SizedBox.square(
                          dimension: s(18),
                          child: CircularProgressIndicator(
                            strokeWidth: s(2),
                            color: KalinkaColors.textPrimary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            SizedBox(width: s(12)),
            _CloseButton(scale: widget.scale, onTap: widget.onClose),
          ],
        ),
        if (volume) ...[
          SizedBox(height: s(14)),
          KioskVolumeSlider(scale: widget.scale),
        ],
        if (showOthers) ...[
          SizedBox(height: s(volume ? 14 : 22)),
          Container(
            height: 1,
            color: KalinkaColors.textPrimary.withValues(alpha: 0.14),
          ),
          SizedBox(height: s(18)),
          _Label('OTHER OUTPUTS', scale: widget.scale),
          SizedBox(height: s(8)),
          for (final r in others)
            _OtherOutput(
              renderer: r,
              isSelf: r.rendererId == ownId,
              scale: widget.scale,
              onTap: _switching
                  ? null
                  : () => _select(
                      r,
                      rendererDisplayName(r, isSelf: r.rendererId == ownId),
                    ),
            ),
        ],
        if (_error != null) ...[
          SizedBox(height: s(10)),
          Text(
            _error!,
            style: KalinkaFonts.sans(
              fontSize: s(15),
              color: KalinkaColors.actionDeleteLight,
            ),
          ),
        ],
      ],
    );

    if (widget.fullScreen) {
      return Material(
        color: Colors.black.withValues(alpha: 0.9),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: EdgeInsets.all(s(24)),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: s(560)),
                child: content,
              ),
            ),
          ),
        ),
      );
    }
    return Material(
      type: MaterialType.transparency,
      child: Container(
        width: s(440),
        decoration: BoxDecoration(
          color: const Color(0xD9101010),
          borderRadius: BorderRadius.circular(s(22)),
          border: Border.all(
            color: KalinkaColors.textPrimary.withValues(alpha: 0.14),
          ),
          boxShadow: const [
            BoxShadow(color: Color(0x80000000), blurRadius: 40),
          ],
        ),
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(s(24), s(20), s(16), s(20)),
          child: content,
        ),
      ),
    );
  }
}

/// A section's name, spaced out in mono like the display's eyebrow.
class _Label extends StatelessWidget {
  final String text;
  final double scale;
  final bool accent;

  const _Label(this.text, {required this.scale, this.accent = false});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: KalinkaFonts.mono(
        fontSize: 13 * scale,
        fontWeight: FontWeight.w600,
        letterSpacing: 3.5 * scale,
        color: accent
            ? KalinkaColors.accentTint
            : KalinkaColors.textPrimary.withValues(alpha: 0.72),
        height: 1.2,
      ),
    );
  }
}

/// An output playback could move to. One that is offline, or that the
/// server cannot drive, is listed dimmed and cannot be chosen.
class _OtherOutput extends StatelessWidget {
  final RendererInfo renderer;
  final bool isSelf;
  final double scale;

  /// Null while a switch is under way.
  final VoidCallback? onTap;

  const _OtherOutput({
    required this.renderer,
    required this.isSelf,
    required this.scale,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    double s(double v) => v * scale;
    final usable = renderer.isConnected && renderer.compatible;
    final detail = [
      if (!isSelf && kioskRunsOn(renderer)) 'This device',
      rendererDetail(renderer, isSelf: isSelf),
    ].where((p) => p.isNotEmpty).join(' · ');

    return Semantics(
      button: usable,
      enabled: usable,
      child: Opacity(
        opacity: usable ? 1 : 0.45,
        child: InkWell(
          onTap: usable ? onTap : null,
          borderRadius: BorderRadius.circular(s(12)),
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: s(10), horizontal: s(4)),
            child: Row(
              children: [
                Icon(
                  Icons.speaker_outlined,
                  size: s(24),
                  color: KalinkaColors.textPrimary,
                ),
                SizedBox(width: s(16)),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        kioskOutputName(renderer, isSelf: isSelf),
                        style: KalinkaFonts.sans(
                          fontSize: s(18),
                          fontWeight: FontWeight.w500,
                          color: KalinkaColors.textPrimary,
                          height: 1.25,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (detail.isNotEmpty)
                        Text(
                          detail,
                          style: KalinkaFonts.sans(
                            fontSize: s(14),
                            color: KalinkaColors.textSecondary,
                            height: 1.3,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
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

class _CloseButton extends StatelessWidget {
  final double scale;
  final VoidCallback onTap;

  const _CloseButton({required this.scale, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Close',
      button: true,
      excludeSemantics: true,
      child: InkResponse(
        onTap: onTap,
        radius: 26 * scale,
        child: SizedBox.square(
          dimension: 44 * scale,
          child: Icon(
            Icons.close_rounded,
            size: 26 * scale,
            color: KalinkaColors.textPrimary.withValues(alpha: 0.8),
          ),
        ),
      ),
    );
  }
}
