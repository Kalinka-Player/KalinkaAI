import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../measure_size.dart';
import 'home_section_plan.dart';
import 'home_pins_shimmer.dart';

typedef HomeSectionCalculator = Future<HomeSectionLayout> Function(
  HomeSectionRequest,
);

Future<HomeSectionLayout> _computeHomeSections(HomeSectionRequest request) {
  // A phone or a single section has no alternatives to search. This still runs
  // after the frame, but avoids starting a worker just to return a stacked row.
  if (!request.wide || request.blocks.length < 2) {
    return Future.value(homeStackedSections(request));
  }
  return compute(planHomeSections, request, debugLabel: 'Home section packing');
}

/// Completed plans contain only geometry. Failed jobs are not cached. The
/// injectable executor lets widget tests use their fake clock; a separate test
/// exercises the real isolate and its transferable inputs/outputs.
class HomeSectionPlanner {
  HomeSectionPlanner({HomeSectionCalculator? calculate})
    : _calculate = calculate ?? _computeHomeSections;

  final HomeSectionCalculator _calculate;
  final _completed = <HomeSectionRequest, HomeSectionLayout>{};
  final _pending = <HomeSectionRequest, Future<HomeSectionLayout>>{};

  HomeSectionLayout? cached(HomeSectionRequest request) {
    final plan = _completed.remove(request);
    if (plan != null) _completed[request] = plan;
    return plan;
  }

  Future<HomeSectionLayout> resolve(HomeSectionRequest request) {
    final previous = cached(request);
    if (previous != null) return Future.value(previous);
    return _pending.putIfAbsent(request, () async {
      try {
        final plan = await Future.sync(() => _calculate(request));
        if (_completed.length >= 32) _completed.remove(_completed.keys.first);
        _completed[request] = plan;
        return plan;
      } finally {
        _pending.remove(request);
      }
    });
  }
}

final homeSectionPlannerProvider = Provider((ref) => HomeSectionPlanner());

/// Coalesces resize/data notifications after the frame and runs at most one job
/// at a time. Old results cannot overwrite newer constraints or pin contents.
class PlannedHomeSections extends ConsumerStatefulWidget {
  final HomeSectionRequest request;
  final bool ready;
  final Widget Function(HomeSectionLayout) builder;
  const PlannedHomeSections({
    super.key,
    required this.request,
    this.ready = true,
    required this.builder,
  });

  @override
  ConsumerState<PlannedHomeSections> createState() =>
      _PlannedHomeSectionsState();
}

class _PlannedHomeSectionsState extends ConsumerState<PlannedHomeSections> {
  HomeSectionRequest? _applied;
  HomeSectionLayout? _plan;
  Timer? _debounce;
  bool _busy = false;
  bool _scheduled = false;
  bool _visible = false;
  double _lastExtent = 0;
  final _focus = FocusNode(skipTraversal: true);

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addEarlyKeyEventHandler(_onKeyEvent);
    _schedule(immediate: true);
  }

  KeyEventResult _onKeyEvent(KeyEvent event) {
    if (_visible || !_focus.hasFocus) return KeyEventResult.ignored;
    // Keep focus so unchanged row slices can resume where they were. Intercept
    // activation before a focused button's own Shortcuts/Actions can handle it.
    // Tab may leave the excluded subtree; Escape still reaches the host route.
    if (event.logicalKey == LogicalKeyboardKey.tab ||
        event.logicalKey == LogicalKeyboardKey.escape) {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  void didUpdateWidget(PlannedHomeSections oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.request != widget.request ||
        oldWidget.ready != widget.ready) {
      // Data was already held until every preview settled. Only ongoing
      // geometry changes need the resize debounce.
      _schedule(immediate: !oldWidget.ready && widget.ready);
    }
  }

  void _schedule({bool immediate = false}) {
    if (_scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!mounted) return;
      _debounce?.cancel();
      if (immediate) {
        _resolve();
      } else {
        _debounce = Timer(const Duration(milliseconds: 40), _resolve);
      }
    });
  }

  Future<void> _resolve() async {
    if (!mounted || !widget.ready || _busy || _applied == widget.request) {
      return;
    }
    final request = widget.request;
    _busy = true;
    HomeSectionLayout plan;
    try {
      plan = await ref.read(homeSectionPlannerProvider).resolve(request);
    } catch (error, stack) {
      // A worker failure must leave Home usable. A later size/content change
      // retries; playback frames do not repeatedly start the failing job.
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'Home section planner',
          silent: true,
        ),
      );
      plan = homeStackedSections(request);
    }
    _busy = false;
    if (!mounted) return;
    if (widget.request == request) {
      setState(() {
        _applied = request;
        _plan = plan;
      });
    } else {
      // The intermediate resize was superseded. Only solve the latest input.
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 40), _resolve);
    }
  }

  @override
  Widget build(BuildContext context) {
    final request = widget.request;
    final cached = widget.ready
        ? ref.read(homeSectionPlannerProvider).cached(request)
        : null;
    if (cached != null) {
      _plan = cached;
      _applied = request;
    }
    // Loaded content must never appear in provisional geometry. Item counts,
    // folder grouping and pane changes can all produce a different final plan.
    final visible = widget.ready && _applied == request && _plan != null;
    _visible = visible;
    final compatible =
        _applied?.width == request.width &&
        _applied?.textScale == request.textScale &&
        _applied?.captionExtent == request.captionExtent &&
        _applied?.blocks.length == request.blocks.length &&
        List.generate(
          request.blocks.length,
          (i) => _applied!.blocks[i].kind == request.blocks[i].kind,
        ).every((same) => same);
    return MeasureSize(
      // Remember the rendered extent, including after a shorter final plan.
      // No rebuild is needed: it is used when a later request hides the pins.
      onChange: (size) => _lastExtent = size.height,
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: visible ? 0 : _lastExtent),
        child: Stack(
          children: [
            // Keep row state across a resize: replacing the subtree would lose
            // keyboard focus and pending enqueue feedback even when slices match.
            // A hidden layout still fits the new pane, avoiding overflow while a
            // narrower plan is being calculated. Initial loading builds no pins.
            Focus(
              focusNode: _focus,
              child: ExcludeFocusTraversal(
                excluding: !visible,
                child: Offstage(
                  offstage: !visible,
                  child: TickerMode(
                    enabled: visible,
                    child: ExcludeFocus(
                      excluding: !widget.ready,
                      child: _plan == null
                          ? const SizedBox.shrink()
                          : widget.builder(
                              compatible
                                  ? _plan!
                                  : homeStackedSections(request),
                            ),
                    ),
                  ),
                ),
              ),
            ),
            if (!visible) const HomePinsShimmer(),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _debounce?.cancel();
    FocusManager.instance.removeEarlyKeyEventHandler(_onKeyEvent);
    _focus.dispose();
    super.dispose();
  }
}
