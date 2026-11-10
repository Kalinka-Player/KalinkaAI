// Native profiling entry point. No playback or server settings are changed.
// KALINKA_SERVER=http://host:8000 flutter run --profile -d linux \
//   -t tool/profile_artwork.dart
// Set KALINKA_PROFILE_SCENARIO=grid to isolate the search artwork grid.
// Set KALINKA_PROFILE_SCENARIO=home to profile the saved Home pins. Adding
// KALINKA_KIOSK=1 makes the Linux window fullscreen, retaining the normal Home.
// Keep the display awake for every comparison: display sleep changes frame
// scheduling and GPU power state. On GNOME, wrap the native executable with
// gnome-session-inhibit --inhibit=idle --inhibit=suspend.
// Set KALINKA_PROFILE_OUT to save the JSON report outside build/.
// KALINKA_PROFILE_HTTP=true also saves the VM's HTTP profile. Use a separate
// run: HTTP profiling retains response bodies and distorts memory/timing.
// FrameTiming measures engine work, not compositor presentation. Cache bytes
// exclude images retained outside the LRU; imageLoads counts cache loaders.
import 'dart:async';
import 'dart:convert';
import 'dart:developer' show Service;
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:ui' show FramePhase, FrameTiming;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kalinka/data_model/data_model.dart';
import 'package:kalinka/main.dart' as app;
import 'package:kalinka/providers/search_session_provider.dart';
import 'package:kalinka/providers/source_modules_provider.dart';
import 'package:kalinka/providers/url_resolver.dart';
import 'package:kalinka/theme/app_theme.dart';
import 'package:kalinka/widgets/search/catalog_page_view.dart';
import 'package:kalinka/widgets/search_cards/artwork_grid.dart';
import 'package:kalinka/widgets/search_cards/browse_navigation_scope.dart';

import 'profile_home_support.dart';

class _ProfileCache extends ImageCache {
  int loads = 0;

  @override
  ImageStreamCompleter? putIfAbsent(
    Object key,
    ImageStreamCompleter Function() loader, {
    ImageErrorListener? onError,
  }) => super.putIfAbsent(key, () {
    loads++;
    return loader();
  }, onError: onError);
}

class _ProfileBinding extends WidgetsFlutterBinding {
  _ProfileBinding({this.home});
  final HomeProfile? home;

  @override
  ImageCache createImageCache() => _ProfileCache();

  @override
  Widget wrapWithDefaultView(Widget rootWidget) =>
      super.wrapWithDefaultView(home?.wrap(rootWidget) ?? rootWidget);
}

Iterable<Element> _elements(Element element, {bool visible = true}) sync* {
  final widget = element.widget;
  if (visible && widget is Offstage && widget.offstage) return;
  yield element;
  final children = <Element>[];
  element.visitChildElements(children.add);
  for (final child in children) {
    yield* _elements(child, visible: visible);
  }
}

Future<T> _until<T>(T? Function() read) async {
  final deadline = DateTime.now().add(const Duration(seconds: 30));
  while (DateTime.now().isBefore(deadline)) {
    final value = read();
    if (value != null) return value;
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  throw TimeoutException('Profiling scenario did not become ready');
}

Future<void> main() async {
  try {
    await _profile();
    exit(0);
  } catch (error, stack) {
    stderr.writeln('$error\n$stack');
    exit(1);
  }
}

Future<void> _profile() async {
  final scenario = Platform.environment['KALINKA_PROFILE_SCENARIO'] ?? 'app';
  final home = scenario == 'home' ? HomeProfile() : null;
  final binding = _ProfileBinding(home: home);
  final profileHttp = Platform.environment['KALINKA_PROFILE_HTTP'] == 'true';
  HttpClient.enableTimelineLogging = profileHttp;
  final cache = binding.imageCache as _ProfileCache;
  final server = Platform.environment['KALINKA_SERVER'];
  if (server == null) {
    throw ArgumentError('Set KALINKA_SERVER=http://host:8000');
  }
  final base = Uri.parse(server.contains('://') ? server : 'http://$server');
  final catalog =
      Platform.environment['KALINKA_PROFILE_CATALOG'] ??
      'kalinka:localfiles:catalog:albums';
  final items = <BrowseItem>[];
  if (home == null) {
    final client = HttpClient();
    final request = await client.getUrl(
      base.resolve('/browse/$catalog?limit=300'),
    );
    final response = await request.close();
    if (response.statusCode != 200) throw HttpException('Browse failed');
    final listing = BrowseItemsList.fromJson(
      jsonDecode(await utf8.decoder.bind(response).join())
          as Map<String, dynamic>,
    );
    client.close();
    items.addAll(listing.items.where((item) => item.album != null));
    if (items.isEmpty) throw StateError('The catalog must contain albums');
  }

  final frames = <FrameTiming>[];
  final reports = <Map<String, Object?>>[];
  binding.addTimingsCallback(frames.addAll);
  Map<String, Object?> memory() => {
    'cacheBytes': cache.currentSizeBytes,
    'cacheEntries': cache.currentSize,
    'liveImages': cache.liveImageCount,
    'pendingImages': cache.pendingImageCount,
    'imageLoads': cache.loads,
    'rssBytes': ProcessInfo.currentRss,
    'maxRssBytes': ProcessInfo.maxRss,
    ...?home?.counters,
  };

  Future<void> measure(String name, Future<void> Function() action) async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
    home?.phase = name;
    frames.clear();
    final before = memory();
    final watch = Stopwatch()..start();
    await action();
    watch.stop();
    // The engine batches FrameTiming callbacks in profile mode.
    await Future<void>.delayed(const Duration(milliseconds: 400));
    final ui = frames.map((f) => f.buildDuration.inMicroseconds / 1000).toList()
      ..sort();
    final raster =
        frames.map((f) => f.rasterDuration.inMicroseconds / 1000).toList()
          ..sort();
    final intervals = [
      for (var i = 1; i < frames.length; i++)
        (frames[i].timestampInMicroseconds(FramePhase.vsyncStart) -
                frames[i - 1].timestampInMicroseconds(FramePhase.vsyncStart)) /
            1000,
    ]..sort();
    double percentile(List<double> values, double fraction) => values.isEmpty
        ? 0
        : values[(values.length * fraction).ceil().clamp(1, values.length) - 1];
    final refresh = binding.platformDispatcher.views.first.display.refreshRate;
    final budget = 1000 / (refresh > 0 ? refresh : 60);
    final report = <String, Object?>{
      'phase': name,
      'actionMs': watch.elapsedMilliseconds,
      'frames': frames.length,
      'budgetMs': budget,
      'uiP95Ms': percentile(ui, .95),
      'uiMaxMs': percentile(ui, 1),
      'rasterP95Ms': percentile(raster, .95),
      'rasterMaxMs': percentile(raster, 1),
      'frameIntervalP50Ms': percentile(intervals, .5),
      'frameIntervalP95Ms': percentile(intervals, .95),
      'uiOverBudget': ui.where((n) => n > budget).length,
      'rasterOverBudget': raster.where((n) => n > budget).length,
      'eitherOverBudget': frames
          .where(
            (f) =>
                f.buildDuration.inMicroseconds > budget * 1000 ||
                f.rasterDuration.inMicroseconds > budget * 1000,
          )
          .length,
      'before': before,
      'after': memory(),
    };
    reports.add(report);
    stdout.writeln('PROFILE ${jsonEncode(report)}');
  }

  Future<void> finish(Map<String, Object?> details) async {
    final view = binding.platformDispatcher.views.first;
    final result = {
      'scenario': scenario,
      'platform': Platform.operatingSystem,
      'gdkBackend': Platform.environment['GDK_BACKEND'],
      'physicalWidth': view.physicalSize.width,
      'physicalHeight': view.physicalSize.height,
      'dpr': view.devicePixelRatio,
      'reportedRefreshHz': view.display.refreshRate,
      'cacheLimitBytes': cache.maximumSizeBytes,
      'httpProfiling': profileHttp,
      'phases': reports,
      ...details,
    };
    if (profileHttp) {
      final service = (await Service.getInfo()).serverUri;
      if (service == null) {
        throw StateError('HTTP profiling needs a VM service');
      }
      final client = HttpClient();
      final request = await client.getUrl(
        service.resolve(
          'ext.dart.io.getHttpProfile?isolateId=${Service.getIsolateId(Isolate.current)}',
        ),
      );
      final response = await request.close();
      result['httpProfile'] = jsonDecode(
        await utf8.decoder.bind(response).join(),
      );
      client.close();
    }
    final output = File(
      Platform.environment['KALINKA_PROFILE_OUT'] ??
          'build/artwork-profile/$scenario.json',
    );
    await output.parent.create(recursive: true);
    await output.writeAsString(
      const JsonEncoder.withIndent('  ').convert(result),
    );
    stdout.writeln('PROFILE saved ${output.path}');
  }

  if (home != null) {
    await home.run(measure);
    await finish(home.details);
    return;
  }

  final controller = ScrollController();
  final gridWidth = ValueNotifier(1.0);
  ProviderContainer? container;
  if (scenario == 'grid') {
    runApp(
      ProviderScope(
        overrides: [
          sourceModulesProvider.overrideWith((ref) => const <ModuleInfo>[]),
          urlResolverProvider.overrideWithValue(UrlResolver(base.toString())),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: LayoutBuilder(
              builder: (context, constraints) {
                return ValueListenableBuilder<double>(
                  valueListenable: gridWidth,
                  builder: (context, fraction, _) => Align(
                    alignment: Alignment.topLeft,
                    child: SizedBox(
                      width: constraints.maxWidth * fraction,
                      child: BrowseNavigationScope(
                        onOpen: (_) {},
                        child: CustomScrollView(
                          controller: controller,
                          slivers: [SliverArtworkGrid(items: items)],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
    await _until(() => controller.hasClients ? controller.position : null);
  } else {
    app.main();
    final scope = await _until(
      () => binding.rootElement == null
          ? null
          : _elements(binding.rootElement!)
                .where((e) => e.widget is app.KalinkaApp)
                .firstOrNull,
    );
    container = ProviderScope.containerOf(scope, listen: false);
    await Future<void>.delayed(const Duration(seconds: 5));
    await measure('open_catalog', () async {
      container!
          .read(searchSessionProvider.notifier)
          .openCatalog(id: catalog, title: 'Albums', provider: 'My Library');
      await Future<void>.delayed(const Duration(seconds: 3));
    });
  }

  ScrollPosition? position() {
    if (scenario == 'grid') return controller.position;
    final root = binding.rootElement;
    if (root == null) return null;
    final page = _elements(root)
        .where((e) => e.widget is CatalogPageView)
        .firstOrNull;
    if (page == null) return null;
    return _elements(page)
        .whereType<StatefulElement>()
        .map((e) => e.state)
        .whereType<ScrollableState>()
        .map((s) => s.position)
        .where(
          (p) =>
              p.hasContentDimensions &&
              p.maxScrollExtent > 0 &&
              axisDirectionToAxis(p.axisDirection) == Axis.vertical,
        )
        .firstOrNull;
  }

  final scroll = await _until(position);
  await Future<void>.delayed(const Duration(seconds: 2));
  final distance = math.min(2800.0, scroll.maxScrollExtent);
  for (final (name, down) in [
    ('cold_down', true),
    ('return_up', false),
    ('warm_down', true),
    ('warm_up', false),
  ]) {
    await measure(name, () async {
      // A fixed distance and speed makes independent runs comparable.
      final target = down ? distance : 0.0;
      await scroll.animateTo(
        target,
        duration: const Duration(seconds: 5),
        curve: Curves.linear,
      );
    });
  }
  if (container != null) {
    await measure('album_navigation', () async {
      for (final item in items.take(8)) {
        container!.read(searchSessionProvider.notifier).openBrowseItem(item);
        await Future<void>.delayed(const Duration(milliseconds: 900));
        container!.read(searchSessionProvider.notifier).goBack();
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
    });
  } else {
    await measure('resize_grid', () async {
      for (var i = 0; i <= 100; i++) {
        gridWidth.value = 1 - .3 * math.sin(math.pi * i / 100);
        await Future<void>.delayed(const Duration(milliseconds: 40));
      }
    });
  }
  await finish({'albums': items.length, 'scrollDistance': distance});
}
