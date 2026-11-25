import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kalinka/data_model/data_model.dart';
import 'package:kalinka/providers/kalinka_player_api_provider.dart';
import 'package:kalinka/providers/source_modules_provider.dart';

/// Keeps favourites as a server would, for a fake API to mix in: [favorites]
/// is what is marked, in whichever source, and is listed a source at a time
/// by kind.
///
/// A read waits for [readHeld] and fails for the sources in [away]. A change
/// waits for [held] and fails with [failure], made all the same where
/// [madeAnyway], as one that timed out may be.
mixin FavoritesServer on KalinkaPlayerProxy {
  final Set<String> favorites = {};
  final Set<String> away = {};
  Completer<void>? readHeld;
  Completer<void>? held;
  Exception? failure;
  bool madeAnyway = false;
  final List<String?> asked = [];
  final List<String> marked = [];
  final List<String> unmarked = [];

  @override
  Future<FavoriteIds> getFavoriteIds({String? source}) async {
    asked.add(source);
    List<String> of(String kind) => [
      for (final id in favorites)
        if (sourceOfId(id) == source && id.contains(':$kind:')) id,
    ];
    // As the server has it when asked, whenever the answer lands.
    final answer = FavoriteIds(
      albums: of('album'),
      tracks: of('track'),
      artists: of('artist'),
      playlists: of('playlist'),
    );
    await readHeld?.future;
    if (away.contains(source)) throw Exception('$source is away');
    return answer;
  }

  @override
  Future<StatusMessage> addFavorite(String id) {
    marked.add(id);
    return _change(() => favorites.add(id));
  }

  @override
  Future<StatusMessage> removeFavorite(String id) {
    unmarked.add(id);
    return _change(() => favorites.remove(id));
  }

  Future<StatusMessage> _change(void Function() make) async {
    await held?.future;
    if (failure == null || madeAnyway) make();
    if (failure != null) throw failure!;
    return StatusMessage(message: 'Ok');
  }
}

/// A source named [name], keeping favourites or not.
ModuleInfo favoritesSource(String name, {bool favorites = true}) => ModuleInfo(
  name: name,
  title: name[0].toUpperCase() + name.substring(1),
  enabled: true,
  state: ModuleState.ready,
  capabilities: [if (favorites) ModuleCapability.favorites],
);

/// The app's own fonts and the icons', so text is measured and captured as
/// it is drawn.
Future<void> loadAppFonts() async {
  for (final (family, file) in [
    ('IBM Plex Sans', 'IBMPlexSans-Regular.ttf'),
    ('IBM Plex Mono', 'IBMPlexMono-Regular.ttf'),
    ('Playfair Display', 'PlayfairDisplay-Regular.ttf'),
  ]) {
    await (FontLoader(
      family,
    )..addFont(rootBundle.load('assets/fonts/$file'))).load();
  }
  await (FontLoader('packages/cupertino_icons/CupertinoIcons')..addFont(
        rootBundle.load('packages/cupertino_icons/assets/CupertinoIcons.ttf'),
      ))
      .load();
  await (FontLoader(
    'MaterialIcons',
  )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
}

/// Writes what [key]'s repaint boundary shows to `$KALINKA_REVIEW_DIR` as
/// [name], where that is set.
Future<void> captureForReview(
  WidgetTester tester,
  GlobalKey key,
  String name,
) async {
  final directory = Platform.environment['KALINKA_REVIEW_DIR'];
  if (directory == null) return;
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('$directory/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}
