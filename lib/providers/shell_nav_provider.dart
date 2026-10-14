import 'package:flutter_riverpod/flutter_riverpod.dart';

/// What the player shows: the playing track, or the queue around it.
enum PlayerView { nowPlaying, queue }

class PlayerViewNotifier extends Notifier<PlayerView> {
  @override
  PlayerView build() => PlayerView.nowPlaying;

  void show(PlayerView view) => state = view;

  void toggle() => state = state == PlayerView.queue
      ? PlayerView.nowPlaying
      : PlayerView.queue;
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
