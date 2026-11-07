import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data_model/receiver_control.dart';
import '../providers/connection_settings_provider.dart';
import '../providers/monotonic_clock_provider.dart';
import '../providers/receiver_provider.dart';
import '../theme/app_theme.dart';
import 'failure_note.dart';
import 'home/source_button_style.dart';
import 'kalinka_bottom_sheet.dart';
import 'kalinka_button.dart';
import 'kalinka_dialog.dart';
import 'overlay_card.dart';

const kConnectIcon = Icons.phonelink_ring_outlined;

IconData receiverIcon(String kind) => switch (kind) {
  'bluetooth' => Icons.bluetooth,
  'airplay' => Icons.airplay,
  _ => Icons.speaker_outlined,
};

Future<void> showReceiverPanel(BuildContext context) =>
    showKalinkaBottomSheet<void>(
      context: context,
      mayFillScreen: true,
      useBeak: true,
      dialogMaxWidth: 380,
      contentBuilder: (_) => const ReceiverPanel(),
    );

/// Uses the existing source strip's neutral, 48dp interaction target.
class ConnectSourceButton extends ConsumerWidget {
  const ConnectSourceButton({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(enabledReceiversProvider).isEmpty) {
      return const SizedBox.shrink();
    }
    return TextButton.icon(
      key: const ValueKey('connect-source-button'),
      style: homeSourceButtonStyle,
      onPressed: () => showReceiverPanel(context),
      icon: const Icon(kConnectIcon, size: 20, applyTextScaling: true),
      label: const Text('Connect'),
    );
  }
}

/// A pointed, animated panel anchored to the sidebar's Connect button.
class ReceiverPopover extends StatefulWidget {
  final String? receiverId;
  final Widget Function(VoidCallback open, FocusNode focusNode, bool isOpen)
  builder;
  const ReceiverPopover({super.key, this.receiverId, required this.builder});
  @override
  State<ReceiverPopover> createState() => _ReceiverPopoverState();
}

class _ReceiverPopoverState extends State<ReceiverPopover>
    with SingleTickerProviderStateMixin {
  final _menu = MenuController();
  final _buttonFocus = FocusNode();
  final _panelFocus = FocusScopeNode();
  final _secretReset = ValueNotifier<int>(0);
  late final _unfold = AnimationController(vsync: this);
  late final _curve = CurvedAnimation(
    parent: _unfold,
    curve: Curves.easeOutCubic,
  );
  bool _open = false;
  bool _restoreButtonFocus = false;
  VoidCallback? _hideOverlay;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    _unfold.duration = reducedMotion
        ? Duration.zero
        : const Duration(milliseconds: 180);
    _unfold.reverseDuration = reducedMotion
        ? Duration.zero
        : const Duration(milliseconds: 120);
    if (reducedMotion && _unfold.isAnimating) {
      _unfold.value = _open ? 1 : 0;
      if (!_open) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && !_open) _hideOverlay?.call();
        });
      }
    }
  }

  @override
  void dispose() {
    _curve.dispose();
    _unfold.dispose();
    _buttonFocus.dispose();
    _panelFocus.dispose();
    _secretReset.dispose();
    super.dispose();
  }

  void _show(Offset? position, VoidCallback showOverlay) {
    _hideOverlay = null;
    showOverlay();
    setState(() => _open = true);
    _unfold.forward();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _open) _panelFocus.requestFocus();
    });
  }

  void _close(VoidCallback hideOverlay) {
    // The panel remains mounted during the exit animation and may reopen.
    // Clear secrets and invalidate pending reveals before starting that exit.
    _secretReset.value++;
    // Pointer dismissal leaves the trigger idle. Keyboard dismissal returns
    // focus so navigation can continue from the button that opened the panel.
    _restoreButtonFocus =
        HardwareKeyboard.instance.logicalKeysPressed.isNotEmpty;
    _hideOverlay = hideOverlay;
    setState(() => _open = false);
    unawaited(
      _unfold.reverse().then((_) {
        if (mounted && !_open) hideOverlay();
      }),
    );
  }

  @override
  Widget build(BuildContext context) => RawMenuAnchor(
    controller: _menu,
    childFocusNode: _buttonFocus,
    consumeOutsideTaps: true,
    onOpenRequested: _show,
    onCloseRequested: _close,
    onClose: () {
      _open = false;
      // Wait for the panel's focus scope to detach, including instant closes
      // with reduced motion, before settling focus on the trigger.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _menu.isOpen) return;
        if (_restoreButtonFocus) {
          _buttonFocus.requestFocus();
        } else {
          _buttonFocus.unfocus();
        }
      });
    },
    builder: (context, controller, _) => Semantics(
      expanded: _open,
      child: widget.builder(
        () => _open ? controller.close() : controller.open(),
        _buttonFocus,
        controller.isOpen,
      ),
    ),
    overlayBuilder: (context, info) {
      final padding = MediaQuery.paddingOf(context);
      final layout = _ReceiverPopoverLayout(
        info.anchorRect,
        Rect.fromLTRB(
          padding.left + 8,
          padding.top + 8,
          info.overlaySize.width - padding.right - 8,
          info.overlaySize.height - padding.bottom - 8,
        ),
      );
      return Positioned.fill(
        child: CustomSingleChildLayout(
          delegate: layout,
          child: TapRegion(
            groupId: info.tapRegionGroupId,
            onTapOutside: (_) => _menu.close(),
            child: ExcludeSemantics(
              excluding: !_open,
              child: IgnorePointer(
                ignoring: !_open,
                child: ExcludeFocus(
                  excluding: !_open,
                  child: FocusScope(
                    node: _panelFocus,
                    child: Shortcuts(
                      shortcuts: const {
                        SingleActivator(LogicalKeyboardKey.escape):
                            DismissIntent(),
                      },
                      child: FadeTransition(
                        opacity: _curve,
                        child: ClipRect(
                          key: const ValueKey('receiver-popover-reveal'),
                          clipper: _ReceiverPopoverReveal(
                            _curve,
                            layout.onRight,
                          ),
                          child: Material(
                            key: const ValueKey('receiver-popover-surface'),
                            color: KalinkaColors.surfaceDialog,
                            surfaceTintColor: Colors.transparent,
                            elevation: 8,
                            shadowColor: Colors.black,
                            shape: _ReceiverPopoverBorder(layout),
                            animationDuration: Duration.zero,
                            clipBehavior: Clip.antiAlias,
                            child: Padding(
                              padding: EdgeInsets.only(
                                left: layout.onRight
                                    ? _receiverPointerWidth
                                    : 0,
                                right: layout.onRight
                                    ? 0
                                    : _receiverPointerWidth,
                              ),
                              child: ReceiverPanel(
                                receiverId: widget.receiverId,
                                onClose: _menu.close,
                                secretReset: _secretReset,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

const _receiverPointerWidth = 8.0;
const _receiverPointerHalfHeight = 7.0;
const _receiverPopoverRadius = 16.0;

class _ReceiverPopoverLayout extends SingleChildLayoutDelegate {
  final Rect anchor;
  final Rect bounds;

  _ReceiverPopoverLayout(this.anchor, this.bounds);

  bool get onRight =>
      bounds.right - anchor.right >= 392 ||
      bounds.right - anchor.right >= anchor.left - bounds.left;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    final room = onRight
        ? bounds.right - anchor.right - 4
        : anchor.left - bounds.left - 4;
    final width = math.min(380 + _receiverPointerWidth, math.max(0.0, room));
    return BoxConstraints(
      minWidth: width,
      maxWidth: width,
      maxHeight: math.max(0.0, bounds.height),
    );
  }

  Offset position(Size size) => Offset(
    onRight ? anchor.right + 4 : anchor.left - size.width - 4,
    (anchor.center.dy - 28).clamp(
      bounds.top,
      math.max(bounds.top, bounds.bottom - size.height),
    ),
  );

  @override
  Offset getPositionForChild(Size size, Size childSize) => position(childSize);

  @override
  bool shouldRelayout(_ReceiverPopoverLayout oldDelegate) =>
      anchor != oldDelegate.anchor || bounds != oldDelegate.bounds;
}

/// One continuous border around the rounded panel and its small pointer.
class _ReceiverPopoverBorder extends OutlinedBorder {
  final _ReceiverPopoverLayout layout;

  const _ReceiverPopoverBorder(
    this.layout, {
    super.side = const BorderSide(color: KalinkaColors.borderDefault),
  });

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) {
    final body = Rect.fromLTRB(
      rect.left + (layout.onRight ? _receiverPointerWidth : 0),
      rect.top,
      rect.right - (layout.onRight ? 0 : _receiverPointerWidth),
      rect.bottom,
    );
    const clearance = _receiverPopoverRadius + _receiverPointerHalfHeight;
    final y =
        rect.top +
        (layout.anchor.center.dy - layout.position(rect.size).dy).clamp(
          clearance,
          math.max(clearance, rect.height - clearance),
        );
    final edge = layout.onRight ? body.left : body.right;
    final pointer = Path()
      ..moveTo(edge, y - _receiverPointerHalfHeight)
      ..lineTo(layout.onRight ? rect.left : rect.right, y)
      ..lineTo(edge, y + _receiverPointerHalfHeight)
      ..close();
    return Path.combine(
      PathOperation.union,
      Path()..addRRect(
        RRect.fromRectAndRadius(
          body,
          const Radius.circular(_receiverPopoverRadius),
        ),
      ),
      pointer,
    );
  }

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      getOuterPath(rect.deflate(side.width), textDirection: textDirection);

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) =>
      canvas.drawPath(
        getOuterPath(
          rect.deflate(side.width / 2),
          textDirection: textDirection,
        ),
        side.toPaint(),
      );

  @override
  _ReceiverPopoverBorder copyWith({BorderSide? side}) =>
      _ReceiverPopoverBorder(layout, side: side ?? this.side);

  @override
  ShapeBorder scale(double t) => copyWith(side: side.scale(t));
}

/// Reveal the already laid-out panel, without squeezing or reflowing its text.
class _ReceiverPopoverReveal extends CustomClipper<Rect> {
  final Animation<double> animation;
  final bool onRight;

  _ReceiverPopoverReveal(this.animation, this.onRight)
    : super(reclip: animation);

  @override
  Rect getClip(Size size) {
    const shadow = 12.0;
    final width = (size.width + 2 * shadow) * animation.value;
    return Rect.fromLTWH(
      onRight ? -shadow : size.width + shadow - width,
      -shadow,
      width,
      size.height + 2 * shadow,
    );
  }

  @override
  bool shouldReclip(_ReceiverPopoverReveal oldClipper) =>
      animation != oldClipper.animation || onRight != oldClipper.onRight;
}

class ReceiverPanel extends ConsumerWidget {
  final String? receiverId;
  final VoidCallback? onClose;

  /// Discards secrets immediately while the panel stays mounted for dismissal.
  final Listenable? secretReset;
  const ReceiverPanel({
    super.key,
    this.receiverId,
    this.onClose,
    this.secretReset,
  });
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inventory = ref.watch(receiversProvider);
    final connection = ref.watch(connectionSettingsProvider);
    final receivers = ref
        .watch(enabledReceiversProvider)
        .where((r) => receiverId == null || r.id == receiverId)
        .toList();
    return Material(
      type: MaterialType.transparency,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 8, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    receiverId != null && receivers.isNotEmpty
                        ? receivers.first.title
                        : 'Play from a device',
                    style: KalinkaTextStyles.settingsPageTitle,
                  ),
                ),
                OverlayCloseButton(
                  label: 'Close',
                  onTap: onClose ?? () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              primary: false,
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Receive audio on ${connection.name}',
                    style: KalinkaTextStyles.trayRowSublabel,
                  ),
                  if (inventory.error != null)
                    _ReceiverError(
                      message: inventory.error!,
                      footer: TextButton(
                        onPressed: () =>
                            ref.read(receiversProvider.notifier).refresh(),
                        child: const Text('Retry'),
                      ),
                    ),
                  const SizedBox(height: 20),
                  if (receivers.isEmpty && inventory.error == null)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Text(
                        'No enabled receivers. Manage plugins in Settings.',
                      ),
                    ),
                  for (var i = 0; i < receivers.length; i++) ...[
                    if (i > 0)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 20),
                        child: Divider(
                          height: 1,
                          color: KalinkaColors.borderDefault,
                        ),
                      ),
                    _ReceiverDetails(
                      key: ValueKey('${connection.address}:${receivers[i].id}'),
                      receiver: receivers[i],
                      available: inventory.error == null,
                      showTitle: receiverId == null,
                      secretReset: secretReset,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Errors have their own surface and announcement, separate from device rows.
class _ReceiverError extends StatelessWidget {
  final String message;
  final Widget? footer;

  const _ReceiverError({required this.message, this.footer});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: Semantics(
      liveRegion: true,
      child: FailureNote(
        message: message,
        textStyle: KalinkaTextStyles.settingsDescription.copyWith(
          color: KalinkaColors.textPrimary,
        ),
        footer: footer,
      ),
    ),
  );
}

class _ReceiverStatus extends StatelessWidget {
  final ReceiverSnapshot receiver;

  const _ReceiverStatus(this.receiver);

  @override
  Widget build(BuildContext context) {
    final message = receiver.message?.trim();
    final hasMessage = message != null && message.isNotEmpty;
    if (receiver.state == 'error') {
      return _ReceiverError(
        message: hasMessage ? message : '${receiver.title} is unavailable.',
      );
    }
    final status = hasMessage
        ? message
        : switch (receiver.state) {
            'starting' => 'Starting receiver…',
            'stopping' => 'Stopping receiver…',
            'disabled' => 'Receiver disabled',
            _ => null,
          };
    if (status == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Text(status, style: KalinkaTextStyles.trayRowSublabel),
    );
  }
}

class _ReceiverDetails extends ConsumerStatefulWidget {
  final ReceiverSnapshot receiver;
  final bool available, showTitle;
  final Listenable? secretReset;
  const _ReceiverDetails({
    super.key,
    required this.receiver,
    required this.available,
    required this.showTitle,
    this.secretReset,
  });
  @override
  ConsumerState<_ReceiverDetails> createState() => _ReceiverDetailsState();
}

class _ReceiverDetailsState extends ConsumerState<_ReceiverDetails>
    with WidgetsBindingObserver {
  Timer? _timer;
  String? _pairingWindowId;
  int? _pairingDeadlineUs;
  int _pairingSeconds = 0;
  bool _foreground = true;
  bool _busy = false;
  bool _expanded = false;
  String? _error, _password;
  String? _busyPeerId;
  int _secretEpoch = 0;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.secretReset?.addListener(_onSecretReset);
    _syncPairingCountdown();
  }

  void _discardPassword() {
    _password = null;
    _secretEpoch++;
  }

  void _onSecretReset() => setState(_discardPassword);

  void _syncPairingCountdown() {
    final pairing = widget.receiver.pairing;
    if (pairing == null) {
      _pairingWindowId = null;
      _pairingDeadlineUs = null;
    } else {
      final observedDeadline =
          ref.read(monotonicClockProvider).elapsedMicroseconds +
          pairing.remainingMicroseconds;
      // A window cannot be extended. Keep its local deadline through periodic
      // snapshots, while accepting an earlier expiry or a replacement window.
      if (_pairingWindowId != pairing.id ||
          _pairingDeadlineUs == null ||
          observedDeadline < _pairingDeadlineUs!) {
        _pairingDeadlineUs = observedDeadline;
      }
      _pairingWindowId = pairing.id;
    }
    _schedulePairingTick();
  }

  void _schedulePairingTick() {
    _timer?.cancel();
    _timer = null;
    final remaining = _pairingDeadlineUs == null
        ? 0
        : (_pairingDeadlineUs! -
                  ref.read(monotonicClockProvider).elapsedMicroseconds)
              .clamp(0, 120 * Duration.microsecondsPerSecond);
    _pairingSeconds = (remaining / Duration.microsecondsPerSecond).ceil();
    if (!widget.available || !_foreground || _pairingSeconds == 0) return;
    final untilNextSecond =
        remaining - (_pairingSeconds - 1) * Duration.microsecondsPerSecond;
    // Wake just after the boundary so timer rounding cannot repeat a number
    // and then skip the following one. Recalculate after every tick.
    _timer = Timer(Duration(microseconds: untilNextSecond + 1000), () {
      if (mounted) setState(_schedulePairingTick);
    });
  }

  @override
  void didUpdateWidget(covariant _ReceiverDetails oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.secretReset != widget.secretReset) {
      oldWidget.secretReset?.removeListener(_onSecretReset);
      widget.secretReset?.addListener(_onSecretReset);
      _discardPassword();
    }
    _syncPairingCountdown();
    if (!widget.available ||
        !widget.receiver.passwordRevealAvailable ||
        !widget.receiver.passwordRequired ||
        widget.receiver.state != 'ready') {
      _discardPassword();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (mounted) {
      setState(() {
        _foreground = state == AppLifecycleState.resumed;
        if (!_foreground) {
          _discardPassword();
        }
        _schedulePairingTick();
      });
    }
  }

  @override
  void dispose() {
    widget.secretReset?.removeListener(_onSecretReset);
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _password = null;
    super.dispose();
  }

  Future<void> _run(Future<void> Function() operation, {String? peerId}) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _busyPeerId = peerId;
      _error = null;
    });
    try {
      await operation();
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Could not complete the action. Check the refreshed state and try again.',
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _busyPeerId = null;
        });
      }
    }
  }

  Future<void> _command(
    String command, [
    Map<String, dynamic> target = const {},
  ]) => _run(
    () => ref.read(receiversProvider.notifier).command(widget.receiver, {
      'command': command,
      ...target,
    }),
    peerId:
        target['peer_id'] as String? ??
        widget.receiver.sessions
            .where((session) => session.id == target['session_id'])
            .firstOrNull
            ?.peerId,
  );
  Widget _spinner(String label) => SizedBox.square(
    dimension: 24,
    child: CircularProgressIndicator(
      strokeWidth: 2,
      color: KalinkaColors.textSecondary,
      semanticsLabel: label,
    ),
  );
  Widget _button(String label, VoidCallback? action) => OutlinedButton(
    onPressed: widget.available && !_busy ? action : null,
    style: OutlinedButton.styleFrom(
      minimumSize: const Size(48, 48),
      foregroundColor: KalinkaColors.textPrimary,
    ),
    child: Text(label),
  );
  bool _canPair(ReceiverSnapshot receiver) => receiver.can('open_pairing');

  Future<void> _reveal() async {
    if (_password != null) {
      setState(_discardPassword);
      return;
    }
    final epoch = _secretEpoch;
    await _run(() async {
      final password = await ref
          .read(receiversProvider.notifier)
          .revealPassword(widget.receiver);
      if (mounted &&
          epoch == _secretEpoch &&
          widget.available &&
          widget.receiver.passwordRevealAvailable &&
          widget.receiver.passwordRequired &&
          widget.receiver.state == 'ready') {
        setState(() => _password = password);
      }
    });
  }

  Widget _airplay(ReceiverSnapshot receiver) {
    final shown = _password != null;
    final canReveal =
        widget.available &&
        receiver.state == 'ready' &&
        receiver.passwordRequired &&
        receiver.passwordRevealAvailable;
    final status = !receiver.passwordRequired
        ? 'No password required'
        : canReveal
        ? 'Password required - click to ${shown ? 'hide' : 'reveal'}'
        : 'Password required';
    final name = receiver.effectiveName ?? receiver.title;
    final serverName = ref.watch(connectionSettingsProvider).name;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          expanded: receiver.passwordRequired ? shown : null,
          child: InkWell(
            onTap: canReveal && !_busy ? _reveal : null,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Icon(receiverIcon(receiver.kind), size: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.showTitle ? receiver.title : name,
                          style: KalinkaTextStyles.trayRowLabel,
                        ),
                        if (widget.showTitle && name != serverName) ...[
                          const SizedBox(height: 4),
                          Text(name, style: KalinkaTextStyles.trayRowSublabel),
                        ],
                        if (widget.available && receiver.state == 'ready') ...[
                          const SizedBox(height: 4),
                          Text(
                            status,
                            style: KalinkaTextStyles.trayRowSublabel,
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (canReveal || shown || _busy) ...[
                    const SizedBox(width: 12),
                    if (_busy)
                      _spinner('Revealing password')
                    else
                      Icon(
                        shown ? Icons.expand_less : Icons.expand_more,
                        size: 24,
                      ),
                  ],
                ],
              ),
            ),
          ),
        ),
        _ReceiverStatus(receiver),
        if (_error != null) _ReceiverError(message: _error!),
        if (shown)
          Padding(
            padding: const EdgeInsets.only(left: 36, top: 8, bottom: 12),
            child: SelectableText(
              _password!,
              style: KalinkaFonts.mono(
                fontSize: 28,
                fontWeight: FontWeight.w500,
                color: KalinkaColors.textPrimary,
                height: 1.4,
              ),
            ),
          ),
        for (final session in receiver.sessions)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              '${session.name} · Connected',
              style: KalinkaTextStyles.trayRowSublabel,
            ),
          ),
      ],
    );
  }

  Widget _compact(ReceiverSnapshot r) {
    final session = r.sessions.firstOrNull;
    final status = session != null
        ? '${session.name} · Connected'
        : r.passwordRequired
        ? 'Password required'
        : 'Not connected';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () => setState(() => _expanded = true),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Icon(receiverIcon(r.kind), size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(r.title, style: KalinkaTextStyles.trayRowLabel),
                      if (r.state == 'ready')
                        Text(status, style: KalinkaTextStyles.trayRowSublabel),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                const Icon(Icons.chevron_right, size: 24),
              ],
            ),
          ),
        ),
        _ReceiverStatus(r),
        if (_error != null) _ReceiverError(message: _error!),
        if (_busy) const LinearProgressIndicator(),
      ],
    );
  }

  Future<void> _forget(ReceiverPeer peer, BuildContext origin) async {
    final confirmed = await showKalinkaDialog<bool>(
      context: origin,
      builder: (context) => KalinkaDialog(
        side: KalinkaDialogSide.browsing,
        centered: true,
        title: 'Forget ${peer.name}?',
        message: 'Removes the Bluetooth pairing. Pair again to reconnect.',
        actions: [
          KalinkaButton(
            label: 'Cancel',
            variant: KalinkaButtonVariant.neutral,
            fullWidth: true,
            autofocus: true,
            onTap: () => Navigator.pop(context, false),
          ),
          KalinkaButton(
            label: 'Forget',
            fullWidth: true,
            onTap: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await _command('forget_device', {'peer_id': peer.id});
    }
  }

  Widget _bluetooth(ReceiverSnapshot r) {
    final pairing = r.pairing;
    final remaining = _pairingSeconds;
    final peers = r.peers.where((p) => p.paired).toList();
    final serverName = ref.watch(connectionSettingsProvider).name;
    final name = r.effectiveName ?? r.title;
    final title = Row(
      children: [
        if (widget.showTitle) ...[
          Icon(receiverIcon(r.kind), size: 24),
          const SizedBox(width: 12),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.showTitle ? r.title : name,
                style: KalinkaTextStyles.trayRowLabel,
              ),
              if (widget.showTitle && name != serverName) ...[
                const SizedBox(height: 4),
                Text(name, style: KalinkaTextStyles.trayRowSublabel),
              ],
            ],
          ),
        ),
      ],
    );
    final pairControl = pairing == null
        ? Stack(
            alignment: Alignment.center,
            children: [
              Opacity(
                opacity: _busy && _busyPeerId == null ? 0 : 1,
                child: KalinkaButton(
                  key: const ValueKey('receiver-pair-new'),
                  label: 'Pair new',
                  size: KalinkaButtonSize.compact,
                  enabled: widget.available && !_busy && _canPair(r),
                  onTap: () => _command('open_pairing'),
                ),
              ),
              if (_busy && _busyPeerId == null) _spinner('Starting pairing'),
            ],
          )
        : Wrap(
            alignment: WrapAlignment.end,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                widget.available
                    ? remaining > 0
                          ? 'Pairing · ${remaining ~/ 60}:${(remaining % 60).toString().padLeft(2, '0')}'
                          : 'Pairing ending…'
                    : 'Pairing status unavailable',
                style: KalinkaTextStyles.trayRowSublabel,
              ),
              IconButton(
                tooltip: 'Stop pairing',
                onPressed: widget.available && !_busy && r.can('close_pairing')
                    ? () => _command('close_pairing', {'window_id': pairing.id})
                    : null,
                icon: _busy && _busyPeerId == null
                    ? _spinner('Stopping pairing')
                    : const Icon(Icons.close, size: 18),
                color: KalinkaColors.textSecondary,
              ),
            ],
          );
    // MenuAnchor measures intrinsic sizes, so use the known panel width.
    final width = (MediaQuery.sizeOf(context).width - 40).clamp(0.0, 340.0);
    final roomy = width >= 320 * MediaQuery.textScalerOf(context).scale(1);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (roomy)
          Row(
            children: [
              Expanded(child: title),
              pairControl,
            ],
          )
        else ...[
          title,
          const SizedBox(height: 8),
          Align(alignment: Alignment.centerRight, child: pairControl),
        ],
        _ReceiverStatus(r),
        if (_error != null) _ReceiverError(message: _error!),
        if (pairing != null && widget.available && peers.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              'Choose $name in Bluetooth settings.',
              style: KalinkaTextStyles.trayRowSublabel,
            ),
          ),
        // An unavailable backend can return no peers without losing its bonds.
        // Keep reported peers, but only claim an empty list when it is ready.
        if (peers.isNotEmpty || (widget.available && r.state == 'ready'))
          Padding(
            padding: const EdgeInsets.only(top: 16, bottom: 8),
            child: Text(
              peers.isEmpty ? 'No paired devices' : 'Paired devices',
              style: KalinkaTextStyles.trayRowSublabel.copyWith(
                color: peers.isEmpty
                    ? KalinkaColors.textMuted
                    : KalinkaColors.textSecondary,
              ),
            ),
          ),
        for (final peer in peers) _pairedDevice(r, peer),
      ],
    );
  }

  Widget _pairedDevice(ReceiverSnapshot receiver, ReceiverPeer peer) {
    final session = receiver.sessions
        .where((s) => s.peerId == peer.id)
        .firstOrNull;
    final connected = peer.connected || session != null;
    final enabled = widget.available && !_busy;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          const Icon(
            Icons.devices_outlined,
            size: 24,
            color: KalinkaColors.textPrimary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(peer.name, style: KalinkaTextStyles.trayRowLabel),
                Row(
                  children: [
                    if (connected) ...[
                      Container(
                        width: 7,
                        height: 7,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: KalinkaColors.statusOnline,
                        ),
                      ),
                      const SizedBox(width: 6),
                    ],
                    Flexible(
                      child: Text(
                        connected ? 'Connected' : 'Paired',
                        style: KalinkaTextStyles.trayRowSublabel,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (receiver.offers('forget_device') || session != null)
            Builder(
              builder: (buttonContext) => PopupMenuButton<String>(
                tooltip: 'Device options for ${peer.name}',
                enabled: enabled,
                icon: _busy && _busyPeerId == peer.id
                    ? _spinner('Updating ${peer.name}')
                    : const Icon(
                        Icons.more_vert,
                        size: 24,
                        color: KalinkaColors.textSecondary,
                      ),
                constraints: const BoxConstraints(minWidth: 168, maxWidth: 280),
                color: KalinkaColors.surfaceRaised,
                surfaceTintColor: Colors.transparent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: const BorderSide(color: KalinkaColors.borderDefault),
                ),
                onSelected: (action) {
                  if (action == 'forget') {
                    _forget(peer, buttonContext);
                  } else if (action == 'disconnect' && session != null) {
                    _command('disconnect_audio', {'session_id': session.id});
                  }
                },
                itemBuilder: (_) => [
                  if (session != null && receiver.offers('disconnect_audio'))
                    PopupMenuItem(
                      value: 'disconnect',
                      enabled: receiver.can('disconnect_audio'),
                      child: Text(
                        'Disconnect',
                        style: KalinkaTextStyles.trayRowLabel,
                      ),
                    ),
                  if (receiver.offers('forget_device'))
                    PopupMenuItem(
                      value: 'forget',
                      enabled: receiver.can('forget_device'),
                      child: Text(
                        'Forget',
                        style: KalinkaTextStyles.trayRowLabel,
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.receiver;
    if (r.kind == 'bluetooth') return _bluetooth(r);
    if (r.kind == 'airplay') return _airplay(r);
    final pairing = r.pairing;
    if (widget.showTitle && !_expanded && pairing == null) return _compact(r);
    final remaining = _pairingSeconds;
    final pairingOpen = widget.available && pairing != null && remaining > 0;
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.showTitle)
            Row(
              children: [
                Icon(receiverIcon(r.kind), size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(r.title, style: KalinkaTextStyles.trayRowLabel),
                ),
              ],
            ),
          const SizedBox(height: 8),
          Text(
            r.effectiveName ?? r.title,
            style: KalinkaTextStyles.trayRowLabel,
          ),
          _ReceiverStatus(r),
          if (_error != null) _ReceiverError(message: _error!),
          if (r.offers('open_pairing')) ...[
            if (pairingOpen) ...[
              Text(
                'Visible as ${r.effectiveName ?? r.title} · ${remaining ~/ 60}:${(remaining % 60).toString().padLeft(2, '0')}',
                style: KalinkaTextStyles.trayRowSublabel,
              ),
              const SizedBox(height: 8),
              Text(
                'Open Bluetooth settings on your device and select ${r.effectiveName ?? r.title}.',
                style: KalinkaTextStyles.trayRowSublabel,
              ),
              const SizedBox(height: 12),
              _button(
                'Stop pairing',
                r.can('close_pairing')
                    ? () => _command('close_pairing', {'window_id': pairing.id})
                    : null,
              ),
            ] else ...[
              if (r.sessions.isEmpty)
                Text('Not connected', style: KalinkaTextStyles.trayRowSublabel),
              const SizedBox(height: 8),
              _button(
                r.sessions.isEmpty ? 'Pair a device' : 'Pair another device',
                _canPair(r) ? () => _command('open_pairing') : null,
              ),
              Text(
                'Visible for 2 minutes',
                style: KalinkaTextStyles.trayRowSublabel,
              ),
            ],
          ] else if (r.instructions.isNotEmpty)
            Text(r.instructions, style: KalinkaTextStyles.trayRowSublabel),
          if (r.passwordRequired) ...[
            const SizedBox(height: 8),
            Text(
              r.passwordRequired ? 'Password required' : 'No password required',
              style: KalinkaTextStyles.trayRowSublabel,
            ),
            if (_password != null)
              SelectableText(
                _password!,
                style: KalinkaFonts.mono(fontSize: 16),
              ),
            if (r.passwordRequired)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed:
                      !widget.available || _busy || !r.passwordRevealAvailable
                      ? null
                      : () {
                          _reveal();
                        },
                  style: TextButton.styleFrom(
                    foregroundColor: KalinkaColors.textPrimary,
                  ),
                  child: Text(
                    _password == null ? 'Show password' : 'Hide password',
                  ),
                ),
              ),
          ],
          for (final session in r.sessions)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(session.name, style: KalinkaTextStyles.trayRowLabel),
                  Text(
                    session.playing ? 'Connected · Playing' : 'Connected',
                    style: KalinkaTextStyles.trayRowSublabel,
                  ),
                  if (r.offers('disconnect_audio'))
                    TextButton(
                      onPressed:
                          widget.available &&
                              !_busy &&
                              r.can('disconnect_audio')
                          ? () => _command('disconnect_audio', {
                              'session_id': session.id,
                            })
                          : null,
                      child: const Text('Disconnect'),
                    ),
                ],
              ),
            ),
          if (_busy) const LinearProgressIndicator(),
        ],
      ),
    );
  }
}
