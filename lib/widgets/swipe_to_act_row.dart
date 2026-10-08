import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart' show SpringSimulation;
import '../theme/app_theme.dart';
import '../utils/haptics.dart';

/// Bidirectional swipe gesture wrapper.
///
/// Swipe right → "Add to queue" (white + icon on gold background).
/// Swipe left  → "Play next"   (white ↑ icon on gold background).
/// Icon zooms from minimal to full size as you swipe.
/// Ticks as the drag unlocks and pops when released past the trigger.
class SwipeToActRow extends StatefulWidget {
  final Widget child;
  final VoidCallback onAddToQueue;
  final VoidCallback onPlayNext;
  final bool enabled;

  const SwipeToActRow({
    super.key,
    required this.child,
    required this.onAddToQueue,
    required this.onPlayNext,
    this.enabled = true,
  });

  @override
  State<SwipeToActRow> createState() => _SwipeToActRowState();
}

class _SwipeToActRowState extends State<SwipeToActRow>
    with TickerProviderStateMixin {
  static const double _iconSize = 24.0;
  static const double _iconMinSize = 12.0;
  static const double _iconPadding = 16.0;
  static const double _dragActivationThreshold = 14.0;
  static const double _settleEpsilon = 0.5;
  static const double _resistanceCoefficient = 60.0;

  // Raw finger travel to trigger, as a fraction of screen width (clamped).
  // Replaces a fixed ~122px reach that testers found too far on phones.
  static const double _rawTriggerFraction = 0.18;
  static const double _rawTriggerMin = 60.0;
  static const double _rawTriggerMax = 96.0;

  // Effective (post-resistance) trigger offset; recomputed each build.
  double _hapticThreshold = 200.0 / 3.0;

  double _dragOffset = 0.0;
  double _rawDragOffset = 0.0;
  bool _dragging = false;
  bool _dragUnlocked = false;

  AnimationController? _snapController;
  AnimationController? _confirmController;
  Animation<double>? _confirmOpacity;

  AnimationController _ensureSnapController() {
    final existing = _snapController;
    if (existing != null) return existing;
    final c = AnimationController(
      vsync: this,
      lowerBound: -1000.0,
      upperBound: 1000.0,
      duration: const Duration(milliseconds: 500),
    );
    c.addListener(() {
      setState(() {
        final value = c.value;
        _dragOffset = value.abs() <= _settleEpsilon ? 0.0 : value;
      });
    });
    _snapController = c;
    return c;
  }

  AnimationController _ensureConfirmController() {
    final existing = _confirmController;
    if (existing != null) return existing;
    final c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _confirmOpacity = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0), weight: 10),
      TweenSequenceItem(tween: ConstantTween(1.0), weight: 25),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 65),
    ]).animate(c);
    _confirmController = c;
    return c;
  }

  @override
  void dispose() {
    _snapController?.dispose();
    _confirmController?.dispose();
    super.dispose();
  }

  double _applyResistance(double rawOffset) {
    if (rawOffset <= 0) return 0;
    return math.log(1 + rawOffset / _resistanceCoefficient) *
        _resistanceCoefficient;
  }

  void _onDragStart(DragStartDetails details) {
    if (!widget.enabled) return;
    // A new gesture takes over the current position from the spring. Its
    // ticker must not keep moving the row underneath the finger.
    _snapController?.stop();
    _confirmController?.reset();
    _rawDragOffset =
        _dragOffset.sign *
        _resistanceCoefficient *
        (math.exp(_dragOffset.abs() / _resistanceCoefficient) - 1);
    _dragUnlocked = _dragOffset.abs() > _settleEpsilon;
    setState(() => _dragging = true);
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (!widget.enabled) return;

    bool unlockedThisFrame = false;

    setState(() {
      _dragging = true;
      _rawDragOffset += details.delta.dx;

      if (!_dragUnlocked && _rawDragOffset.abs() > _dragActivationThreshold) {
        _dragUnlocked = true;
        unlockedThisFrame = true;
      }

      if (_dragUnlocked) {
        final sign = _rawDragOffset >= 0 ? 1.0 : -1.0;
        _dragOffset = sign * _applyResistance(_rawDragOffset.abs());
      } else {
        _dragOffset = 0.0;
      }
    });

    if (unlockedThisFrame) {
      KalinkaHaptics.selectionClick();
    }
  }

  void _onDragEnd(DragEndDetails details) {
    if (!widget.enabled) return;

    _dragging = false;

    final bool triggered = _dragOffset.abs() >= _hapticThreshold;
    final bool isQueue = _dragOffset > 0;

    _dragUnlocked = false;
    _rawDragOffset = 0.0;
    _animateSpringSnap(0.0);

    if (triggered) {
      KalinkaHaptics.corkPop();
      _ensureConfirmController().forward(from: 0.0);
      // Commit on release. Waiting for the spring loses this action if the
      // user starts another swipe before the animation finishes.
      if (isQueue) {
        widget.onAddToQueue();
      } else {
        widget.onPlayNext();
      }
    }
  }

  void _onDragCancel() {
    if (!_dragging) return;
    _dragging = false;
    _dragUnlocked = false;
    _rawDragOffset = 0.0;
    _animateSpringSnap(0.0);
  }

  void _animateSpringSnap(double target) {
    final simulation = SpringSimulation(
      const SpringDescription(mass: 1.0, stiffness: 300.0, damping: 30.0),
      _dragOffset,
      target,
      0.0,
    );

    _ensureSnapController().animateWith(simulation).then((_) {
      if (mounted && target == 0.0) {
        setState(() => _dragOffset = 0.0);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Scale the trigger distance to the screen for consistent reach.
    final rawTrigger = (MediaQuery.sizeOf(context).width * _rawTriggerFraction)
        .clamp(_rawTriggerMin, _rawTriggerMax)
        .toDouble();
    _hapticThreshold = _applyResistance(rawTrigger);

    final isActive =
        widget.enabled &&
        (_dragOffset.abs() > _settleEpsilon ||
            _dragging ||
            (_snapController?.isAnimating ?? false));
    final offset = isActive ? _dragOffset : 0.0;
    final absOffset = offset.abs();
    final progress = (absOffset / _hapticThreshold).clamp(0.0, 1.0);
    final currentIconSize =
        _iconMinSize + (_iconSize - _iconMinSize) * progress;
    final isRight = offset > 0;
    final bgColor = isRight ? KalinkaColors.gold : KalinkaColors.statusPending;
    final confirmOpacity = _confirmOpacity;

    // Keep the child's ancestors stable at rest, during the swipe, and when
    // confirmation first appears. Swapping the wrapper remounts Image widgets
    // and drops their decoded artwork, even with gaplessPlayback enabled.
    return GestureDetector(
      onHorizontalDragStart: _onDragStart,
      onHorizontalDragUpdate: _onDragUpdate,
      onHorizontalDragEnd: _onDragEnd,
      onHorizontalDragCancel: _onDragCancel,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          // Stack's clip only covers layout overflow. Translation overflows
          // during paint, so without an explicit clip the artwork can alternate
          // between ancestor and raster-cache bounds as it crosses this edge.
          // Keep cached and uncached frames under the same fixed boundary.
          return ClipRect(
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // Background on the revealed side only (zero width at rest).
                Positioned(
                  left: isRight ? 0 : null,
                  right: isRight ? null : 0,
                  top: 0,
                  bottom: 0,
                  width: absOffset.clamp(0.0, width),
                  child: ColoredBox(color: bgColor),
                ),
                Positioned(
                  left: isRight ? _iconPadding : null,
                  right: isRight ? null : _iconPadding,
                  top: 0,
                  bottom: 0,
                  child: Visibility(
                    visible: isActive,
                    child: Center(
                      child: Icon(
                        isRight ? Icons.add : Icons.arrow_upward,
                        color: Colors.white,
                        size: currentIconSize,
                      ),
                    ),
                  ),
                ),
                Transform.translate(
                  offset: Offset(offset, 0),
                  child: SizedBox(
                    width: width,
                    child: ColoredBox(
                      color: isActive
                          ? KalinkaColors.surfaceRaised
                          : Colors.transparent,
                      // Translate the retained artwork/text layer while the
                      // background and action icon repaint independently.
                      child: RepaintBoundary(child: widget.child),
                    ),
                  ),
                ),
                // Keep confirmation lazy without wrapping/reparenting content.
                if (confirmOpacity != null)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: FadeTransition(
                        opacity: confirmOpacity,
                        // Keep feedback on the icon; a full-row tint flashes
                        // over the artwork on every committed swipe.
                        child: const Center(
                          child: Icon(
                            Icons.check_rounded,
                            color: KalinkaColors.gold,
                            size: 22,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
