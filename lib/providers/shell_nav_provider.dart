import 'package:flutter_riverpod/flutter_riverpod.dart';

/// What the player shows: the playing track, or the queue around it.
enum PlayerView { nowPlaying, queue }

class PlayerViewNotifier extends Notifier<PlayerView> {
  @override
  PlayerView build() => PlayerView.nowPlaying;

  void show(PlayerView view) => state = view;
}

final playerViewProvider = NotifierProvider<PlayerViewNotifier, PlayerView>(
  PlayerViewNotifier.new,
);

/// Ticks when something outside Home asks it to lift its search overlay, such
/// as the empty queue's "Find music".
class HomeSearchRequest extends Notifier<int> {
  @override
  int build() => 0;

  void request() => state++;
}

final homeSearchRequestProvider = NotifierProvider<HomeSearchRequest, int>(
  HomeSearchRequest.new,
);

/// Opens Configuration's Music sources tab through the player shell, keeping
/// settings in the tablet panel and preserving Home's scroll position.
class MusicSourcesSettingsRequest extends Notifier<int> {
  @override
  int build() => 0;

  void open() => state++;
}

final musicSourcesSettingsRequestProvider =
    NotifierProvider<MusicSourcesSettingsRequest, int>(
      MusicSourcesSettingsRequest.new,
    );

/// Hosted by the player shell so tablet customisation stays in the right panel.
class HomeCustomisationNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void open() => state = true;
  void close() => state = false;
}

final homeCustomisationProvider =
    NotifierProvider<HomeCustomisationNotifier, bool>(
      HomeCustomisationNotifier.new,
    );
