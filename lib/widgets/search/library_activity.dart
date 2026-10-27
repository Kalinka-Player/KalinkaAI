import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/connection_state_provider.dart';
import '../../providers/indexer_status_provider.dart';
import '../../theme/app_theme.dart';

/// Home's line while the library pipeline works: a turning ring, **Updating
/// library** and a chevron, centred, which opens what each stage is doing
/// under it. Gone when the pipeline is idle. Its own consumer so the 5s poll
/// ticks rebuild only this line.
class LibraryActivityLine extends ConsumerStatefulWidget {
  const LibraryActivityLine({super.key});

  @override
  ConsumerState<LibraryActivityLine> createState() =>
      _LibraryActivityLineState();
}

class _LibraryActivityLineState extends ConsumerState<LibraryActivityLine> {
  final _details = MenuController();
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    // Offline, the retained progress is stale and would read as live.
    final connected = ref.watch(
      connectionStateProvider.select((s) => s == ConnectionStatus.connected),
    );
    final working =
        connected &&
        ref.watch(indexerStatusProvider.select((s) => s.current != null));
    if (!working) {
      // The menu went with the line; don't come back showing it open.
      _open = false;
      return const SizedBox.shrink();
    }
    final viewport = MediaQuery.sizeOf(context);
    final width = math.min(
      MediaQuery.textScalerOf(context).scale(300),
      viewport.width - 24,
    );
    // Lit like the sources line's names: under the pointer, focus or press.
    bool lit(Set<WidgetState> states) =>
        states.contains(WidgetState.hovered) ||
        states.contains(WidgetState.focused) ||
        states.contains(WidgetState.pressed);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Center(
        child: MenuAnchor(
          controller: _details,
          consumeOutsideTap: true,
          onOpen: () => setState(() => _open = true),
          onClose: () => setState(() => _open = false),
          // Centred under the line, its point up at it.
          alignmentOffset: Offset(-width / 2, 0),
          style: MenuStyle(
            alignment: Alignment.bottomCenter,
            maximumSize: WidgetStatePropertyAll(
              Size(width, viewport.height * .7),
            ),
            // The card paints itself, point and all.
            elevation: const WidgetStatePropertyAll(0),
            backgroundColor: const WidgetStatePropertyAll(Colors.transparent),
            surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
            shadowColor: const WidgetStatePropertyAll(Colors.transparent),
            padding: const WidgetStatePropertyAll(EdgeInsets.zero),
            shape: const WidgetStatePropertyAll(RoundedRectangleBorder()),
          ),
          menuChildren: [_LibraryActivityDetails(width: width)],
          child: MergeSemantics(
            child: Semantics(
              expanded: _open,
              child: TextButton(
                onPressed: () =>
                    _details.isOpen ? _details.close() : _details.open(),
                style: ButtonStyle(
                  minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
                  padding: const WidgetStatePropertyAll(
                    EdgeInsets.symmetric(horizontal: 14),
                  ),
                  shape: const WidgetStatePropertyAll(StadiumBorder()),
                  textStyle: WidgetStatePropertyAll(
                    KalinkaFonts.sans(
                      fontSize: KalinkaTypography.baseSize + 2,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  foregroundColor: WidgetStateProperty.resolveWith(
                    (states) => lit(states)
                        ? KalinkaColors.textPrimary
                        : KalinkaColors.textSecondary,
                  ),
                  backgroundColor: WidgetStateProperty.resolveWith(
                    (states) => lit(states)
                        ? KalinkaColors.surfaceOverlay
                        : Colors.transparent,
                  ),
                  overlayColor: const WidgetStatePropertyAll(
                    Colors.transparent,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const _ActivityRing(size: 18),
                    const SizedBox(width: 10),
                    const Flexible(child: Text('Updating library')),
                    const SizedBox(width: 4),
                    Icon(
                      _open
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                      size: 18,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// What each stage of the pipeline is doing: those at work turn, with their
/// progress where it is known; those done for now are ticked.
class _LibraryActivityDetails extends ConsumerWidget {
  final double width;

  const _LibraryActivityDetails({required this.width});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stages = ref.watch(indexerStatusProvider.select((s) => s.stages));
    return CustomPaint(
      painter: const _PointedCardPainter(),
      child: SizedBox(
        width: width,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            16,
            _PointedCardPainter.point + 14,
            16,
            14,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                header: true,
                child: Text(
                  'Library activity',
                  style: KalinkaTextStyles.trackRowTitle.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              for (final stage in stages) ...[
                const SizedBox(height: 14),
                _StageRow(stage),
              ],
              const SizedBox(height: 16),
              const Divider(
                color: KalinkaColors.borderSubtle,
                thickness: 1,
                height: 1,
              ),
              const SizedBox(height: 10),
              Text(
                'You can keep listening',
                style: KalinkaTextStyles.trackRowSubtitle.copyWith(
                  color: KalinkaColors.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StageRow extends StatelessWidget {
  final IndexerStageProgress progress;

  const _StageRow(this.progress);

  @override
  Widget build(BuildContext context) {
    final active = progress.active;
    final pct = progress.progressPct;
    // Work always comes with a count, so a row without one is done.
    final status = pct == null ? 'Done' : '${pct.toStringAsFixed(0)}%';
    final style = KalinkaTextStyles.trackRowSubtitle.copyWith(
      fontSize: KalinkaTypography.baseSize + 1,
    );
    return MergeSemantics(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              SizedBox.square(
                dimension: 18,
                child: active
                    ? const _ActivityRing(size: 18)
                    : const Icon(
                        Icons.check_rounded,
                        size: 18,
                        color: KalinkaColors.textMuted,
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  progress.stage.label,
                  style: style.copyWith(
                    color: active
                        ? KalinkaColors.textPrimary
                        : KalinkaColors.textSecondary,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                status,
                style: style.copyWith(
                  color: active
                      ? KalinkaColors.textSecondary
                      : KalinkaColors.textMuted,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          if (pct != null)
            // Under the words, past the ring.
            Padding(
              padding: const EdgeInsets.only(left: 30, top: 8),
              child: ExcludeSemantics(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: (pct / 100).clamp(0.0, 1.0),
                    minHeight: 3,
                    backgroundColor: KalinkaColors.borderSubtle,
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      KalinkaColors.accent,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A ring of short arcs with a berry head chasing round it. It moves in
/// steps, a few frames a second rather than one every vsync: it turns for as
/// long as the library works, and on desktop every frame redraws the whole
/// window. Rings step on the wall clock, so several share each frame. Still
/// under reduced motion, and while its tickers are off (an offstage visit).
class _ActivityRing extends StatefulWidget {
  final double size;

  const _ActivityRing({required this.size});

  @override
  State<_ActivityRing> createState() => _ActivityRingState();
}

class _ActivityRingState extends State<_ActivityRing> {
  static const _stepMs = 250;

  Timer? _timer;
  ValueListenable<TickerModeData>? _tickerMode;
  bool _still = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _still = MediaQuery.disableAnimationsOf(context);
    final mode = TickerMode.getValuesNotifier(context);
    if (mode != _tickerMode) {
      _tickerMode?.removeListener(_schedule);
      _tickerMode = mode..addListener(_schedule);
    }
    _schedule();
  }

  void _schedule() {
    _timer?.cancel();
    _timer = null;
    if (_still || _tickerMode?.value.enabled != true) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    _timer = Timer(Duration(milliseconds: _stepMs - now % _stepMs), () {
      if (!mounted) return;
      setState(() {});
      _schedule();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _tickerMode?.removeListener(_schedule);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final head = _still
        ? 0
        : DateTime.now().millisecondsSinceEpoch ~/
              _stepMs %
              _ChasePainter.segments;
    return RepaintBoundary(
      child: SizedBox.square(
        dimension: widget.size,
        child: CustomPaint(painter: _ChasePainter(head)),
      ),
    );
  }
}

class _ChasePainter extends CustomPainter {
  /// The lit segment; the two behind it trail off.
  final int head;

  const _ChasePainter(this.head);

  static const segments = 8;
  static const _trail = [1.0, 0.55, 0.3];

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width / 8;
    final rect = Offset.zero & size;
    final sweep = 2 * math.pi / segments;
    final gap = sweep * 0.3;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    for (var i = 0; i < segments; i++) {
      final behind = (head - i) % segments;
      paint.color = KalinkaColors.accent.withValues(
        alpha: behind < _trail.length ? _trail[behind] : 0.18,
      );
      canvas.drawArc(
        rect.deflate(stroke / 2),
        -math.pi / 2 + i * sweep + gap / 2,
        sweep - gap,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_ChasePainter oldDelegate) => oldDelegate.head != head;
}

/// The details card, with a small point up at the line it opened from.
class _PointedCardPainter extends CustomPainter {
  const _PointedCardPainter();

  static const point = 6.0;
  static const _radius = 12.0;

  @override
  void paint(Canvas canvas, Size size) {
    final x = size.width / 2;
    final card = Path()
      ..addRRect(
        RRect.fromLTRBR(
          0.5,
          point + 0.5,
          size.width - 0.5,
          size.height - 0.5,
          const Radius.circular(_radius),
        ),
      );
    // Its base sinks into the card so the two join without a seam.
    final tip = Path()
      ..moveTo(x - point, point + 1.5)
      ..lineTo(x, 0.5)
      ..lineTo(x + point, point + 1.5)
      ..close();
    final outline = Path.combine(PathOperation.union, card, tip);
    canvas
      ..drawPath(outline, Paint()..color = KalinkaColors.surfaceRaised)
      ..drawPath(
        outline,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = KalinkaColors.borderDefault,
      );
  }

  @override
  bool shouldRepaint(_PointedCardPainter oldDelegate) => false;
}
