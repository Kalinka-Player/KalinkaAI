import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:http/http.dart' as http;

import '../data_model/module_icons.dart';

typedef IconRasterizer = Future<Uint8List> Function(Uint8List svg, int extent);

/// Keeps rasterized PNG data across rows and navigation, independently of the
/// cover-art image cache. Concurrent requests share the same work.
class ModuleIconCache {
  final http.Client client;
  final IconRasterizer rasterize;
  final _images = <(String, String, int), Future<Uint8List>>{};

  ModuleIconCache({required this.client, IconRasterizer? rasterize})
    : rasterize = rasterize ?? _rasterize;

  Future<Uint8List> load(
    String url,
    ModuleIconImage icon, {
    required bool small,
  }) {
    final extent = small ? 96 : 256;
    final key = (url, icon.mimeType, extent);
    final existing = _images.remove(key);
    if (existing != null) {
      _images[key] = existing;
      return existing;
    }
    if (_images.length >= 64) _images.remove(_images.keys.first);
    late final Future<Uint8List> pending;
    pending = _load(url, icon.mimeType, extent).catchError((
      Object error,
      StackTrace stack,
    ) {
      if (identical(_images[key], pending)) _images.remove(key);
      Error.throwWithStackTrace(error, stack);
    });
    return _images[key] = pending;
  }

  Future<Uint8List> _load(String url, String mimeType, int extent) async {
    final uri = Uri.parse(url);
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      throw const FormatException('Unsupported icon URL');
    }
    final response = await client.get(uri).timeout(const Duration(seconds: 10));
    if (response.statusCode != 200 || response.bodyBytes.length > 256 * 1024) {
      throw const FormatException('Icon unavailable');
    }
    return switch (mimeType) {
      'image/png' => response.bodyBytes,
      'image/svg+xml' => rasterize(response.bodyBytes, extent),
      _ => throw const FormatException('Unsupported icon format'),
    };
  }

  static Future<Uint8List> _rasterize(Uint8List bytes, int extent) async {
    final info = await vg.loadPicture(SvgBytesLoader(bytes), null);
    try {
      if (info.size.isEmpty || !info.size.isFinite) {
        throw const FormatException('Invalid icon dimensions');
      }
      final scale = extent / math.max(info.size.width, info.size.height);
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder)..scale(scale);
      canvas.drawPicture(info.picture);
      final picture = recorder.endRecording();
      try {
        final image = await picture.toImage(
          math.max(1, (info.size.width * scale).ceil()),
          math.max(1, (info.size.height * scale).ceil()),
        );
        try {
          final png = await image.toByteData(format: ui.ImageByteFormat.png);
          if (png == null) throw const FormatException('Cannot rasterize icon');
          return png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes);
        } finally {
          image.dispose();
        }
      } finally {
        picture.dispose();
      }
    } finally {
      info.picture.dispose();
    }
  }
}

final moduleIconCacheProvider = Provider<ModuleIconCache>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return ModuleIconCache(client: client);
});
