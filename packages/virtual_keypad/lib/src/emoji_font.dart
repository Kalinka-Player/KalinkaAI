import 'dart:typed_data' show ByteData;

import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader;

/// Supplies the bytes of a color emoji font.
///
/// The package never performs the fetch itself, so it pulls in no HTTP
/// dependency and makes no outbound request you did not write. Read the bytes
/// from your CDN, your own server, or an app asset.
typedef EmojiFontBytesLoader = Future<ByteData> Function();

/// Emoji font bundled with this package, subset to the codepoints the emoji
/// picker uses.
///
/// Only needed on Flutter web. The CanvasKit and Skwasm renderers ignore the
/// browser font stack and download a fallback emoji font on demand, so without
/// a bundled font emoji render as blank boxes until that download succeeds.
/// Native platforms ship their own color emoji font and work offline already.
///
/// The keyboard applies this automatically on web, both to the emoji picker
/// grid and to [VirtualKeypadTextField]. Use the constant directly when you
/// need the same coverage elsewhere in your app, or call
/// [VirtualKeypadEmojiFont.withVirtualKeypadEmojiFont] on your theme.
const String kBundledEmojiFontFamily = 'packages/virtual_keypad/NotoEmoji';

/// Emoji text style applied when the caller does not supply one.
///
/// Returns null off the web so the platform's color emoji font is used as-is.
TextStyle? defaultEmojiTextStyle() =>
    kIsWeb ? const TextStyle(fontFamily: kBundledEmojiFontFamily) : null;

/// Emoji font families to fall back through, best first.
///
/// The runtime color font comes first when it has loaded, so text keeps pace
/// with the emoji grid instead of showing color in the picker and monochrome
/// in the field. The bundled monochrome font always ends the chain, which is
/// what guarantees emoji render at all.
List<String> bundledEmojiFallbackFamilies() => <String>[
      if (VirtualKeypadColorEmoji.isLoaded.value)
        VirtualKeypadColorEmoji.fontFamily,
      kBundledEmojiFontFamily,
    ];

/// Appends the emoji fallback families to [style] so emoji in that text render
/// offline on web.
///
/// Returns [style] untouched off the web, where the platform already provides
/// a color emoji font.
TextStyle? withBundledEmojiFallback(TextStyle? style) {
  if (!kIsWeb) return style;
  final existing = style?.fontFamilyFallback ?? const <String>[];
  final families = bundledEmojiFallbackFamilies()
      .where((family) => !existing.contains(family))
      .toList();
  if (families.isEmpty) return style;
  return (style ?? const TextStyle()).copyWith(
    fontFamilyFallback: [...existing, ...families],
  );
}

/// Registers a color emoji font at runtime, so web can show color emoji
/// without every app paying for one in its bundle.
///
/// The bundled fallback is monochrome because a color emoji font is large:
/// subset to the same codepoints, Noto Color Emoji in COLRv1 form is roughly
/// 3.9 MB against 708 KB, because COLRv1 draws each emoji from many
/// single-color layer glyphs. Shipping that to every app, including the mobile
/// ones that already get color emoji from the system font, is a poor trade.
///
/// Loading it at runtime avoids the trade entirely. The keyboard renders the
/// bundled monochrome font immediately, and swaps to color if and when the
/// font arrives. If the fetch fails, because the device is offline or the
/// request was blocked, the monochrome font simply stays. Emoji always render.
///
/// Opt in by passing [VirtualKeypad.colorEmojiFontLoader]:
///
/// ```dart
/// VirtualKeypad(
///   standalone: true,
///   enableEmojiKey: true,
///   colorEmojiFontLoader: () async {
///     final response = await http.get(Uri.parse(myColorEmojiFontUrl));
///     return ByteData.sublistView(response.bodyBytes);
///   },
/// )
/// ```
///
/// Self-host the font rather than hot-linking someone else's CDN. Kiosk, ATM,
/// and enterprise deployments often disallow outbound requests, which is why
/// this is opt in and why the package never fetches anything on its own.
class VirtualKeypadColorEmoji {
  VirtualKeypadColorEmoji._();

  /// Family the runtime-loaded color emoji font is registered under.
  ///
  /// Registration is app wide, so once loaded you can use this family in your
  /// own text styles too, not just in the keyboard.
  static const String fontFamily = 'VirtualKeypadColorEmoji';

  /// Whether the color font has been registered.
  ///
  /// Listenable, so the keyboard repaints the emoji grid when it flips.
  static final ValueNotifier<bool> isLoaded = ValueNotifier<bool>(false);

  static Future<bool>? _pending;

  /// Loads and registers the color emoji font, at most once per app.
  ///
  /// Repeat calls return the first result, so several keyboards on screen do
  /// not each download the font. Completes with false when [loader] fails,
  /// leaving the bundled monochrome font in place.
  static Future<bool> load(EmojiFontBytesLoader loader) =>
      _pending ??= _load(loader);

  static Future<bool> _load(EmojiFontBytesLoader loader) async {
    try {
      final bytes = await loader();
      // FontLoader accepts whatever bytes it is given without validating them,
      // so a captive portal or an error page served in place of the font would
      // register as a font and quietly break emoji. Check the magic number
      // first and keep the bundled font instead.
      if (!_looksLikeFont(bytes)) return false;
      await (FontLoader(fontFamily)..addFont(Future<ByteData>.value(bytes)))
          .load();
      isLoaded.value = true;
      return true;
    } catch (_) {
      // Offline, blocked, or an unreadable font. Emoji keep rendering from the
      // bundled monochrome font, so there is nothing to report to the caller.
      return false;
    }
  }

  /// Whether [bytes] start with a font signature Flutter can actually load.
  ///
  /// WOFF and WOFF2 are deliberately rejected: Flutter cannot load them, so
  /// failing here is clearer than registering a font that never renders.
  static bool _looksLikeFont(ByteData bytes) {
    if (bytes.lengthInBytes < 4) return false;
    switch (bytes.getUint32(0)) {
      case 0x00010000: // TrueType outlines
      case 0x74727565: // 'true'
      case 0x4F54544F: // 'OTTO', CFF outlines
      case 0x74746366: // 'ttcf', TrueType collection
        return true;
      default:
        return false;
    }
  }

  /// Clears the memoized load so a test can exercise it again.
  @visibleForTesting
  static void resetForTesting() {
    _pending = null;
    isLoaded.value = false;
  }
}

/// Adds the bundled emoji font to a [ThemeData] so emoji render offline on web.
extension VirtualKeypadEmojiFont on ThemeData {
  /// Returns a copy of this theme with [kBundledEmojiFontFamily] appended as a
  /// font fallback across the text themes.
  ///
  /// The keyboard already handles its own emoji grid and
  /// [VirtualKeypadTextField]. Use this when your app drives the keyboard in
  /// standalone mode with plain [TextField] widgets, so emoji the user inserts
  /// keep rendering without a network connection:
  ///
  /// ```dart
  /// MaterialApp(
  ///   theme: ThemeData.light().withVirtualKeypadEmojiFont(),
  ///   home: const MyHomePage(),
  /// )
  /// ```
  ///
  /// Returns this theme unchanged off the web.
  ThemeData withVirtualKeypadEmojiFont() {
    if (!kIsWeb) return this;
    final fallback = bundledEmojiFallbackFamilies();
    return copyWith(
      textTheme: textTheme.apply(fontFamilyFallback: fallback),
      primaryTextTheme: primaryTextTheme.apply(fontFamilyFallback: fallback),
    );
  }
}
