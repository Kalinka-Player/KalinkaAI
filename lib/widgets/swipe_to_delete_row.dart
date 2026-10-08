import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart' show SpringSimulation;
import '../theme/app_theme.dart';
import '../utils/haptics.dart';

/// Left-swipe gesture wrapper for delete action.
///
/// Swipe left to trigger "Remove" on release.
/// Bin icon zooms from minimal to full size until trigger point (1/3 from right).
/// Ticks as the drag unlocks and thuds when released past the threshold.
class SwipeToDeleteRow extends StatefulWidget {
  final Widget child;
  final VoidCallback onDelete;
  final bool enabled;

  const SwipeToDeleteRow({
    super.key,
    required this.child,
    required this.onDelete,
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
  bool _dragging = false;
  bool _dragUnlocked = false;
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
      lowerBound: -200.0, // Covers maximum resisted drag (~88 px) with headroom
      upperBound: 0.0,
      duration: const Duration(milliseconds: 500),
    );
    _snapController.addListener(() {
      setState(() => _dragOffset = _snapController.value);
    });

    _exitController = AnimationController(
      vsync: this,
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
    if (rawOffset >= 0) return 0;
    final absRaw = rawOffset.abs();
    // Logarithmic curve: creates increasing resistance
    final resistedAbs =
        math.log(1 + absRaw / _resistanceCoefficient) * _resistanceCoefficient;
    return -resistedAbs;
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (!widget.enabled) return;

    double? unlockedOffset;

    setState(() {
      _dragging = true;
      // Negative offset for left swipe
      _rawDragOffset = (_rawDragOffset + details.delta.dx).clamp(
        double.negativeInfinity,
        0.0,
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
    if (!widget.enabled) return;

    _dragging = false;

    if (_dragOffset.abs() >= _hapticThreshold) {
      _playDeleteCommitHaptic();
      _animateDeleteExit();
    } else {
      _animateSpringSnap(0.0);
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
      _dragUnlocked = false;
      _rawDragOffset = 0.0;
    });
  }

  void _animateDeleteExit() {
    // Phase 1: slide the ENTIRE row (background + icon + content) off-screen
    // to the left using _exitController so no ghost icons linger during collapse.
    _exitController
        .animateTo(
          -1000.0,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInCubic,
        )
        .then((_) {
          if (!mounted) return;
          // Phase 2: collapse row height to zero
          _collapseController.forward().then((_) {
            if (!mounted) return;
            widget.onDelete();
          });
        });
  }

  @override
  Widget build(BuildContext context) {
    final collapseFactor = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: _collapseController, curve: Curves.easeInCubic),
    );

    Widget inner;

    if (!widget.enabled ||
        _dragOffset == 0.0 &&
            !_dragging &&
            !_snapController.isAnimating &&
            !_exitController.isAnimating) {
      // Pass-through: no swipe state, just render child with drag detection
      inner = GestureDetector(
        onHorizontalDragUpdate: _onDragUpdate,
        onHorizontalDragEnd: _onDragEnd,
        child: widget.child,
      );
    } else {
      // Icon zoom calculation: zooms until deletion threshold, then stays stable
      final progress = (_dragOffset.abs() / _hapticThreshold).clamp(0.0, 1.0);
      final iconSize =
          _deleteIconMinSize +
          (_deleteIconSize - _deleteIconMinSize) * progress;

      // Bin red from palette
      const bgColor = KalinkaColors.statusOffline;

      inner = GestureDetector(
        onHorizontalDragUpdate: _onDragUpdate,
        onHorizontalDragEnd: _onDragEnd,
        child: Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            // Uniform red background under the swipe
            Positioned.fill(child: ColoredBox(color: bgColor)),
            // Bin icon (right-anchored, zooms as swipe progresses)
            Positioned(
              right: _iconPadding,
              top: 0,
              bottom: 0,
              child: Center(
                child: Icon(
                  Icons.delete_outline,
                  color: Colors.white,
                  size: iconSize,
                ),
              ),
            ),
            // Content layer (slides left during drag/spring)
            Transform.translate(
              offset: Offset(_dragOffset, 0),
              child: ColoredBox(
                color: KalinkaColors.background,
                child: widget.child,
              ),
            ),
          ],
        ),
      );
    }

    return SizeTransition(
      sizeFactor: collapseFactor,
      axis: Axis.vertical,
      alignment: AlignmentDirectional.topStart,
      // _exitSlideOffset translates the whole row (Stack + background + icon)
      // so nothing is left behind when the height collapses.
      child: Transform.translate(
        offset: Offset(_exitSlideOffset, 0),
        child: inner,
      ),
    );
  }
}
