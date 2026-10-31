import 'dart:async' show FutureOr;
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart' show SpringSimulation;
import 'package:flutter/semantics.dart' show CustomSemanticsAction;

import '../theme/app_theme.dart';
import '../utils/haptics.dart';

/// Queue swipe actions: remove on the left, optionally play next on the right.
///
/// Swipe left to trigger "Remove" on release.
/// Bin icon zooms from minimal to full size until trigger point (1/3 from right).
/// Ticks as the drag unlocks and thuds when released past the threshold.
class SwipeToDeleteRow extends StatefulWidget {
  final Widget child;
  final FutureOr<void> Function() onDelete;
  final FutureOr<void> Function()? onPlayNext;
  final bool enabled;

  const SwipeToDeleteRow({
    super.key,
    required this.child,
    required this.onDelete,
    this.onPlayNext,
    this.enabled = true,
  });

  @override
  State<SwipeToDeleteRow> createState() => _SwipeToDeleteRowState();
}

class _SwipeToDeleteRowState extends State<SwipeToDeleteRow>
    with TickerProviderStateMixin {
  static const double _deleteIconSize = 24.0;
  static const double _deleteIconMinSize = 12.0;
  static const double _iconPadding = 16.0;
  static const double _maxDrag = 200.0;
  static const double _hapticThreshold = _maxDrag / 3.0; // 1/3 from right
  static const double _dragActivationThreshold = 14.0;
  static const double _resistanceCoefficient =
      60.0; // Controls resistance curve
  static const Duration _deleteHapticMinInterval = Duration(milliseconds: 90);

  double _dragOffset = 0.0;
  double _rawDragOffset = 0.0; // Track raw offset before resistance
  double _exitSlideOffset = 0.0; // Translates the whole row during exit
  bool _dragUnlocked = false;
  bool _actionPending = false;
  bool _pointerCancelled = false;
  DateTime? _lastStartTickAt;

  /// Spring snap-back controller. Bounds must cover the resisted pixel range
  /// so Flutter's tick() clamp doesn't squash the simulation to zero instantly.
  late AnimationController _snapController;

  /// Slides the entire row (background + icon + content) off-screen to the
  /// left during deletion, so no ghost icons remain during the height collapse.
  late AnimationController _exitController;

  /// Collapses the row height to zero after the exit slide completes.
  late AnimationController _collapseController;

  @override
  void initState() {
    super.initState();
    _snapController = AnimationController(
      vsync: this,
      lowerBound: -1000.0,
      upperBound: 1000.0,
      duration: const Duration(milliseconds: 500),
    );
    _snapController.addListener(() {
      setState(() => _dragOffset = _snapController.value);
    });

    _exitController = AnimationController(
      vsync: this,
      value: 0.0,
      lowerBound: -1000.0,
      upperBound: 0.0,
      duration: const Duration(milliseconds: 250),
    );
    _exitController.addListener(() {
      setState(() => _exitSlideOffset = _exitController.value);
    });

    _collapseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    );
    _collapseController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _snapController.dispose();
    _exitController.dispose();
    _collapseController.dispose();
    super.dispose();
  }

  /// Apply resistance to drag offset using logarithmic curve.
  /// Resistance increases as you swipe further, making it harder to overshoot.
  double _applyResistance(double rawOffset) {
    final absRaw = rawOffset.abs();
    // Logarithmic curve: creates increasing resistance
    final resistedAbs =
        math.log(1 + absRaw / _resistanceCoefficient) * _resistanceCoefficient;
    return rawOffset.sign * resistedAbs;
  }

  void _onDragStart(DragStartDetails details) {
    if (!widget.enabled || _actionPending) return;
    _snapController.stop();
    _rawDragOffset =
        _dragOffset.sign *
        _resistanceCoefficient *
        (math.exp(_dragOffset.abs() / _resistanceCoefficient) - 1);
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (!widget.enabled || _actionPending) return;

    double? unlockedOffset;

    setState(() {
      _rawDragOffset = (_rawDragOffset + details.delta.dx).clamp(
        double.negativeInfinity,
        widget.onPlayNext == null ? 0.0 : double.infinity,
      );

      final absRaw = _rawDragOffset.abs();

      // Stay snapped at rest until activation threshold is crossed.
      if (!_dragUnlocked && absRaw > _dragActivationThreshold) {
        _dragUnlocked = true;
        unlockedOffset = _applyResistance(_rawDragOffset);
        _dragOffset = unlockedOffset!;
      } else if (_dragUnlocked) {
        _dragOffset = _applyResistance(_rawDragOffset);
      } else {
        _dragOffset = 0.0;
      }
    });

    // Trigger subtle haptic exactly when snapping is released.
    if (unlockedOffset != null) {
      _lastStartTickAt = DateTime.now();
      KalinkaHaptics.selectionClick();
    }
  }

  void _onDragEnd(DragEndDetails details) {
    if (!widget.enabled || _actionPending) return;
    if (_pointerCancelled) {
      _onDragCancel();
      return;
    }

    if (_dragOffset.abs() >= _hapticThreshold) {
      if (_dragOffset > 0) {
        KalinkaHaptics.corkPop();
        _animateSpringSnap(0.0);
        _playNext();
      } else {
        _playDeleteCommitHaptic();
        _animateDeleteExit();
      }
    } else {
      _animateSpringSnap(0.0);
    }
  }

  void _onDragCancel() {
    if (_actionPending) return;
    _animateSpringSnap(0.0);
  }

  Future<void> _playNext() async {
    final onPlayNext = widget.onPlayNext;
    if (!widget.enabled || _actionPending || onPlayNext == null) return;
    setState(() => _actionPending = true);
    try {
      await onPlayNext();
    } finally {
      if (mounted) setState(() => _actionPending = false);
    }
  }

  Future<void> _playDeleteCommitHaptic() async {
    final lastTickAt = _lastStartTickAt;
    if (lastTickAt != null) {
      final elapsed = DateTime.now().difference(lastTickAt);
      if (elapsed < _deleteHapticMinInterval) {
        await Future.delayed(_deleteHapticMinInterval - elapsed);
      }
    }
    KalinkaHaptics.hapticDelete();
  }

  void _animateSpringSnap(double target) {
    _dragUnlocked = false;
    _rawDragOffset = 0.0;
    if (MediaQuery.disableAnimationsOf(context)) {
      setState(() => _dragOffset = target);
      return;
    }
    final simulation = SpringSimulation(
      const SpringDescription(
        mass: 1.0,
        stiffness: 300.0, // Controls bounce: higher = stiffer
        damping: 30.0, // Controls oscillation dampening
      ),
      _dragOffset,
      target,
      0.0, // velocity
    );

    _snapController.animateWith(simulation).then((_) {
      if (mounted) setState(() => _dragOffset = target);
    });
  }

  Future<void> _animateDeleteExit() async {
    if (!widget.enabled || _actionPending) return;
    setState(() => _actionPending = true);
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    // Phase 1: slide the ENTIRE row (background + icon + content) off-screen
    // to the left using _exitController so no ghost icons linger during collapse.
    if (!reducedMotion) {
      await _exitController.animateTo(
        -1000.0,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInCubic,
      );
      if (!mounted) return;
      await _collapseController.forward();
    }
    if (!mounted) return;
    try {
      // The connection or drag state can change during the exit animation.
      if (!widget.enabled) return;
      await widget.onDelete();
    } finally {
      // The server removes successful actions from the list. If it refuses,
      // restore the retained row so the user can try again.
      if (mounted) {
        _exitController.value = 0.0;
        _collapseController.reset();
        setState(() {
          _exitSlideOffset = 0.0;
          _dragOffset = 0.0;
          _rawDragOffset = 0.0;
          _dragUnlocked = false;
          _actionPending = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final collapseFactor = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: _collapseController, curve: Curves.easeInCubic),
    );

    final isRight = _dragOffset > 0;
    final progress = (_dragOffset.abs() / _hapticThreshold).clamp(0.0, 1.0);
    final iconSize =
        _deleteIconMinSize + (_deleteIconSize - _deleteIconMinSize) * progress;
    final canSwipe = widget.enabled && !_actionPending;

    // Retain the child's ancestors during a gesture so artwork and tap state
    // aren't remounted when the swipe starts or the spring comes to rest.
    final inner = GestureDetector(
      onHorizontalDragStart: widget.enabled ? _onDragStart : null,
      onHorizontalDragUpdate: widget.enabled ? _onDragUpdate : null,
      onHorizontalDragEnd: widget.enabled ? _onDragEnd : null,
      onHorizontalDragCancel: widget.enabled ? _onDragCancel : null,
      child: ClipRect(
        child: Stack(
          children: [
            Positioned.fill(
              child: ColoredBox(
                color: isRight
                    ? KalinkaColors.gold
                    : KalinkaColors.actionDelete,
              ),
            ),
            Positioned(
              left: isRight ? _iconPadding : null,
              right: isRight ? null : _iconPadding,
              top: 0,
              bottom: 0,
              child: Center(
                child: Icon(
                  isRight ? Icons.playlist_play_rounded : Icons.delete_outline,
                  color: isRight
                      ? KalinkaColors.background
                      : KalinkaColors.textPrimary,
                  size: iconSize,
                ),
              ),
            ),
            Transform.translate(
              offset: Offset(_dragOffset, 0),
              child: ColoredBox(
                color: KalinkaColors.background,
                child: IgnorePointer(
                  ignoring: _actionPending,
                  child: widget.child,
                ),
              ),
            ),
          ],
        ),
      ),
    );

    return Listener(
      onPointerDown: (_) => _pointerCancelled = false,
      // Flutter reports an accepted drag's pointer cancellation as onEnd.
      // Remember the actual pointer event so cancellation cannot commit it.
      onPointerCancel: (_) => _pointerCancelled = true,
      child: Semantics(
        customSemanticsActions: canSwipe
            ? {
                const CustomSemanticsAction(label: 'Remove from queue'):
                    _animateDeleteExit,
                if (widget.onPlayNext != null)
                  const CustomSemanticsAction(label: 'Play next'): _playNext,
              }
            : null,
        child: SizeTransition(
          sizeFactor: collapseFactor,
          axis: Axis.vertical,
          alignment: AlignmentDirectional.topStart,
          // _exitSlideOffset translates the whole row (Stack + background + icon)
          // so nothing is left behind when the height collapses.
          child: Transform.translate(
            offset: Offset(_exitSlideOffset, 0),
            child: inner,
          ),
        ),
      ),
    );
  }
}
