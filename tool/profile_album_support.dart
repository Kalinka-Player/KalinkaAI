// Live Linux album profiling. Never activates playback or changes the queue.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kalinka/data_model/data_model.dart';
import 'package:kalinka/main.dart' as app;
import 'package:kalinka/providers/search_session_provider.dart';
import 'package:kalinka/widgets/search/album_page_header.dart';
import 'package:kalinka/widgets/search/catalog_page_view.dart';
import 'package:kalinka/widgets/search_cards/search_track_row.dart';

import 'profile_home_support.dart' show ProfileMeasure;

Iterable<Element> _elements(Element root) sync* {
  if (root.widget case Offstage(offstage: true)) return;
  yield root;
  final children = <Element>[];
  root.visitChildElements(children.add);
  for (final child in children) {
    yield* _elements(child);
  }
}

class AlbumProfile {
  AlbumProfile(this.item);
  final BrowseItem item;
  final openings = <Map<String, Object?>>[];
  final scrolls = <Map<String, Object?>>[];

  Iterable<Element> get shown => WidgetsBinding.instance.rootElement == null
      ? const []
      : _elements(WidgetsBinding.instance.rootElement!);

  Element? get page => shown
      .where(
        (e) =>
            e.widget is CatalogPageView &&
            (e.widget as CatalogPageView).page.id == item.id,
      )
      .firstOrNull;

  ScrollPosition? get position {
    final root = page;
    if (root == null) return null;
    final tracks = _elements(root)
        .where((e) => e.widget.key == const ValueKey('album-tracks'))
        .firstOrNull;
    if (tracks == null) return null;
    return _elements(tracks)
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

  Future<T> until<T>(T? Function() read) async {
    final timeout = Stopwatch()..start();
    while (timeout.elapsed < const Duration(seconds: 20)) {
      final value = read();
      if (value != null) return value;
      await Future<void>.delayed(const Duration(milliseconds: 16));
    }
    throw TimeoutException('Album profiling did not become ready');
  }

  Map<String, Object?> get details => {
    'album': item.name,
    'albumId': item.id,
    'trackCount': item.album?.trackCount,
    'openings': openings,
    'scrolls': scrolls,
  };

  Future<void> run(ProfileMeasure measure) async {
    app.main();
    final root = await until(
      () => shown.where((e) => e.widget is app.KalinkaApp).firstOrNull,
    );
    final container = ProviderScope.containerOf(root, listen: false);
    final nav = container.read(searchSessionProvider.notifier);
    await Future<void>.delayed(const Duration(seconds: 4));
    nav.openCatalog(
      id: 'kalinka:localfiles:catalog:albums',
      title: 'Albums',
      provider: 'My Library',
    );
    await Future<void>.delayed(const Duration(seconds: 3));

    for (var attempt = 0; attempt < 4; attempt++) {
      final name = attempt == 0
          ? 'album_open_cold'
          : 'album_open_warm_$attempt';
      await measure(name, () async {
        final watch = Stopwatch()..start();
        nav.openBrowseItem(item);
        final root = await until(() => page);
        final firstLayoutMs = watch.elapsedMicroseconds / 1000;
        await until(
          () =>
              _elements(root)
                  .where((e) => e.widget is SearchTrackRow)
                  .firstOrNull,
        );
        final firstTracksMs = watch.elapsedMicroseconds / 1000;
        final art = await until(
          () =>
              _elements(root)
                  .where((e) => e.widget is AlbumArtwork)
                  .firstOrNull,
        );
        final image = await until(
          () =>
              _elements(art)
                  .map((e) => e.widget)
                  .whereType<RawImage>()
                  .where((w) => w.image != null)
                  .firstOrNull,
        );
        final coverReadyMs = watch.elapsedMicroseconds / 1000;
        final header = _elements(root)
            .where((e) => e.widget is WideAlbumHeader)
            .firstOrNull;
        openings.add({
          'phase': name,
          'firstLayoutMs': firstLayoutMs,
          'firstTracksMs': firstTracksMs,
          'coverReadyMs': coverReadyMs,
          'decodeWidth': image.image!.width,
          'decodeHeight': image.image!.height,
          'headerHeight': header?.size?.height,
          'coverWidth': art.size?.width,
        });
      });
      if (attempt == 0) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
        final scroll = position!;
        await measure('album_scroll_cold_down', () async {
          await scroll.animateTo(
            scroll.maxScrollExtent,
            duration: const Duration(seconds: 5),
            curve: Curves.linear,
          );
          await Future<void>.delayed(const Duration(milliseconds: 200));
          if (scroll.maxScrollExtent - scroll.pixels > 1) {
            await scroll.animateTo(
              scroll.maxScrollExtent,
              duration: const Duration(seconds: 2),
              curve: Curves.linear,
            );
          }
          scrolls.add({
            'phase': 'cold_down',
            'distance': scroll.pixels,
            'lastTrackIndex': _elements(page!)
                .map((e) => e.widget)
                .whereType<SearchTrackRow>()
                .map((w) => w.containerIndex ?? -1)
                .fold<int>(-1, (max, n) => n > max ? n : max),
          });
        });
        for (final (name, down) in [
          ('album_scroll_warm_up', false),
          ('album_scroll_warm_down', true),
          ('album_scroll_repeat_up', false),
          ('album_scroll_repeat_down', true),
        ]) {
          await measure(
            name,
            () => scroll.animateTo(
              down ? scroll.maxScrollExtent : 0,
              duration: const Duration(seconds: 4),
              curve: Curves.linear,
            ),
          );
        }
      }
      nav.goBack();
      await Future<void>.delayed(const Duration(milliseconds: 650));
    }
  }
}
