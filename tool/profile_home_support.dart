import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kalinka/main.dart' as app;
import 'package:kalinka/providers/kiosk_provider.dart';
import 'package:kalinka/providers/pinned_catalogs_provider.dart';
import 'package:kalinka/providers/search_session_provider.dart';
import 'package:kalinka/widgets/browse_rows_shimmer.dart';
import 'package:kalinka/widgets/home/home_section_plan.dart';
import 'package:kalinka/widgets/home/planned_home_sections.dart';
import 'package:kalinka/widgets/loading_shimmer.dart';
import 'package:kalinka/widgets/search/search_zero_state.dart';
import 'package:kalinka/widgets/top_bar_content_fade.dart';

typedef ProfileMeasure = Future<void> Function(
  String name,
  Future<void> Function() action,
);

Iterable<Element> _elements(Element root) sync* {
  if (root.widget case Offstage(offstage: true)) return;
  yield root;
  final children = <Element>[];
  root.visitChildElements(children.add);
  for (final child in children) {
    yield* _elements(child);
  }
}

/// Instruments the real executor, including isolate startup/transfer time.
/// No library records or widgets cross the worker boundary.
class _PlannerMetrics {
  int pending = 0;
  final jobs = <Map<String, Object?>>[];
  String phase = 'startup';

  Future<HomeSectionLayout> calculate(HomeSectionRequest request) async {
    pending++;
    final watch = Stopwatch()..start();
    final phaseAtStart = phase;
    try {
      final worker = request.wide && request.blocks.length >= 2;
      final plan = worker
          ? await compute(
              planHomeSections,
              request,
              debugLabel: 'Home section packing',
            )
          : homeStackedSections(request);
      jobs.add({
        'phase': phaseAtStart,
        'width': request.width,
        'blocks': request.blocks.length,
        'worker': worker,
        'elapsedMs': watch.elapsedMicroseconds / 1000,
        'rows': plan.rows.length,
      });
      return plan;
    } finally {
      pending--;
    }
  }
}

/// Uses saved pins and live server responses without changing pin preferences.
class HomeProfile {
  final effect =
      Platform.environment['KALINKA_PROFILE_HOME_EFFECT'] ?? 'normal';
  final width = ValueNotifier<double?>(null);
  final _metrics = _PlannerMetrics();
  late final _planner = HomeSectionPlanner(calculate: _metrics.calculate);
  final _notes = <Map<String, Object?>>[];
  List<PinnedCatalog> _pins = [];
  final _scrollRestoration = <double>[];
  double? _initialWidth;

  set phase(String value) {
    _metrics.phase = value;
    // Diagnostic-only render changes, reapplied between phases. These do not
    // edit application code and are not used for resize comparisons.
    if (effect == 'no-header-fade') {
      for (final e in _shown.where((e) => e.widget is TopBarContentFade)) {
        (e.findRenderObject() as dynamic).extent = 0.0;
      }
    }
    if (effect == 'no-bloom') {
      final bloom = _shown
          .where((e) => e.widget.key == const ValueKey('discover-backdrop'))
          .firstOrNull;
      if (bloom != null) {
        final fade = _elements(bloom)
            .where((e) => e.widget is FadeTransition)
            .firstOrNull;
        if (fade != null) {
          (fade.findRenderObject() as dynamic).opacity =
              const AlwaysStoppedAnimation(0.0);
        }
      }
    }
  }

  Map<String, Object?> get counters => {
    'plannerJobs': _metrics.jobs.length,
    'plannerPending': _metrics.pending,
  };

  Map<String, Object?> get details => {
    'effectExperiment': effect,
    'pins': [
      for (final p in _pins) {'title': p.title, 'preview': p.preview.name},
    ],
    'initialViewportWidth': _initialWidth,
    'resizeMode': 'constrained app viewport; native framebuffer unchanged',
    'plannerJobs': _metrics.jobs,
    'settling': _notes,
    'returnScrollOffsetErrors': _scrollRestoration,
  };

  Widget wrap(Widget root) {
    if (root is! ProviderScope) throw StateError('Expected app ProviderScope');
    final instrumented = ProviderScope(
      overrides: [
        ...root.overrides,
        homeSectionPlannerProvider.overrideWithValue(_planner),
        // KALINKA_KIOSK may make the native window fullscreen for a wide
        // measurement, but this scenario always exercises the normal Home UI.
        kioskLaunchProvider.overrideWithValue(false),
      ],
      observers: root.observers,
      retry: root.retry,
      child: root.child,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        return ValueListenableBuilder<double?>(
          valueListenable: width,
          child: instrumented,
          builder: (context, requested, child) {
            final w = math.min(
              requested ?? constraints.maxWidth,
              constraints.maxWidth,
            );
            return Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: w,
                child: MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(size: Size(w, constraints.maxHeight)),
                  child: child!,
                ),
              ),
            );
          },
        );
      },
    );
  }

  Iterable<Element> get _shown {
    final root = WidgetsBinding.instance.rootElement;
    return root == null ? const [] : _elements(root);
  }

  ScrollPosition? get _homeScroll {
    final home = _shown.where((e) => e.widget is SearchZeroState).firstOrNull;
    if (home == null) return null;
    return _elements(home)
        .whereType<StatefulElement>()
        .map((e) => e.state)
        .whereType<ScrollableState>()
        .map((s) => s.position)
        .where(
          (p) =>
              p.hasContentDimensions &&
              axisDirectionToAxis(p.axisDirection) == Axis.vertical,
        )
        .firstOrNull;
  }

  Future<void> _settle(String name, {int seconds = 12}) async {
    final watch = Stopwatch()..start();
    int loading = 0;
    int stable = 0;
    while (watch.elapsed < Duration(seconds: seconds)) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      loading = _shown
          .where((e) => e.widget is ShimmerPulse || e.widget is LoadingSpinner)
          .length;
      if (loading == 0 &&
          _metrics.pending == 0 &&
          PaintingBinding.instance.imageCache.pendingImageCount == 0) {
        if (++stable >= 5) break;
      } else {
        stable = 0;
      }
    }
    _notes.add({
      'phase': name,
      'elapsedMs': watch.elapsedMilliseconds,
      'settled': stable >= 5,
      'loadingWidgets': loading,
      'errorLabels': _shown
          .map((e) => e.widget)
          .whereType<Text>()
          .map((t) => t.data)
          .whereType<String>()
          .where(
            (s) => s.contains('Could not load') || s.contains('unavailable'),
          )
          .toSet()
          .toList(),
    });
  }

  Future<void> run(ProfileMeasure measure) async {
    ProviderContainer? container;
    await measure('home_initial_load', () async {
      app.main();
      final deadline = DateTime.now().add(const Duration(seconds: 30));
      while (DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        final root = _shown
            .where((e) => e.widget is app.KalinkaApp)
            .firstOrNull;
        if (root == null) continue;
        container = ProviderScope.containerOf(root, listen: false);
        final pins = container!.read(pinnedCatalogsProvider);
        if (pins != null && _homeScroll != null) {
          _pins = pins;
          break;
        }
      }
      if (container == null || _homeScroll == null || _pins.isEmpty) {
        throw StateError('Home with saved pins did not become ready');
      }
      await _settle('initial_load', seconds: 20);
    });
    final view = WidgetsBinding.instance.platformDispatcher.views.first;
    _initialWidth = view.physicalSize.width / view.devicePixelRatio;
    final scroll = _homeScroll!;
    final distance = math.min(2800.0, scroll.maxScrollExtent);
    _notes.add({'scrollDistance': distance});
    for (final (name, down) in [
      ('home_cold_down', true),
      ('home_return_up', false),
      ('home_warm_down', true),
      ('home_warm_up', false),
    ]) {
      await measure(
        name,
        () => scroll.animateTo(
          down ? distance : 0,
          duration: const Duration(seconds: 5),
          curve: Curves.linear,
        ),
      );
    }
    if (Platform.environment['KALINKA_PROFILE_HOME_SCROLL_ONLY'] == 'true') {
      return;
    }
    for (final (index, pin)
        in _pins.where((p) => !p.shortcut).take(3).indexed) {
      final before = _homeScroll!.pixels;
      await measure('open_pin_$index', () async {
        container!
            .read(searchSessionProvider.notifier)
            .openPage(pin.page, filter: pin.filter);
        await Future<void>.delayed(const Duration(milliseconds: 1200));
      });
      await measure('return_home_$index', () async {
        container!.read(searchSessionProvider.notifier).goBack();
        await _settle('return_home_$index');
      });
      _scrollRestoration.add((_homeScroll!.pixels - before).abs());
    }
    await measure('home_resize_drag', () async {
      for (var i = 0; i <= 100; i++) {
        width.value =
            _initialWidth! -
            (_initialWidth! - 720) * math.sin(math.pi * i / 100);
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }
      width.value = null;
      await _settle('after_resize_drag');
    });
    await measure('home_resize_stops', () async {
      for (final w in [1280.0, 1024.0, 800.0, 720.0, _initialWidth!]) {
        if (w > _initialWidth!) continue;
        width.value = w;
        await _settle('width_$w');
      }
      width.value = null;
    });
    await measure('home_warm_after_resize', () async {
      final current = _homeScroll!;
      current.jumpTo(0);
      await current.animateTo(
        math.min(distance, current.maxScrollExtent),
        duration: const Duration(seconds: 5),
        curve: Curves.linear,
      );
    });
  }
}
