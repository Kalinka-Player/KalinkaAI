import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The renderer whose settings panel is open.
class RendererSettingsRoute {
  final String rendererId;

  /// Friendly name, carried so the panel can title itself before its first
  /// config fetch lands.
  final String rendererName;

  const RendererSettingsRoute({
    required this.rendererId,
    required this.rendererName,
  });
}

/// Whether the renderer settings panel is open, and for which renderer.
///
/// A provider rather than a `Navigator.push`, because the panel is hosted by
/// [MusicPlayerScreen] as an overlay: on tablet it covers the right-hand queue,
/// leaving Now Playing visible, which a window-wide route cannot do. The
/// signal has to travel from the picker sheet, opened from deep inside the
/// mini player or Now Playing, up to that host.
class RendererSettingsRouteNotifier extends Notifier<RendererSettingsRoute?> {
  @override
  RendererSettingsRoute? build() => null;

  void open(String rendererId, String rendererName) {
    state = RendererSettingsRoute(
      rendererId: rendererId,
      rendererName: rendererName,
    );
  }

  void close() => state = null;
}

final rendererSettingsRouteProvider =
    NotifierProvider<RendererSettingsRouteNotifier, RendererSettingsRoute?>(
      RendererSettingsRouteNotifier.new,
    );
