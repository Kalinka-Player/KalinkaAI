import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'home_section_plan.dart';

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
  final Widget Function(HomeSectionLayout) builder;
  const PlannedHomeSections({
    super.key,
    required this.request,
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

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  @override
  void didUpdateWidget(PlannedHomeSections oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.request != widget.request) _schedule();
  }

  void _schedule() {
    if (_scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!mounted) return;
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 40), _resolve);
    });
  }

  Future<void> _resolve() async {
    if (!mounted || _busy || _applied == widget.request) return;
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
    final cached = ref.read(homeSectionPlannerProvider).cached(request);
    if (cached != null) {
      _plan = cached;
      _applied = request;
    }
    final compatible =
        _applied?.width == request.width &&
        _applied?.textScale == request.textScale &&
        _applied?.captionExtent == request.captionExtent &&
        _applied?.blocks.length == request.blocks.length &&
        List.generate(
          request.blocks.length,
          (i) => _applied!.blocks[i].kind == request.blocks[i].kind,
        ).every((same) => same);
    // A wider old plan would overflow a shrinking pane. Use a cheap stacked
    // fallback then; content-only changes can keep the last finished geometry.
    return widget.builder(
      compatible && _plan != null ? _plan! : homeStackedSections(request),
    );
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }
}
