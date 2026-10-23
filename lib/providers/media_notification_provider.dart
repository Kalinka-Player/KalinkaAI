import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/connection_settings_provider.dart';
import '../providers/connection_state_provider.dart';
import '../providers/playback_time_provider.dart' show appLifecycleProvider;
import 'server_address.dart';

/// Turns Android's media notification on each time the app reaches its
/// server, and off on Disconnect. In between the notification keeps its own
/// connection and shows itself while that has a current track; after losing
/// it for a while it gives up until the app reaches the server again.
class MediaNotificationNotifier extends Notifier<void> {
  static const _methodChannel = MethodChannel(
    'org.kalinka.kalinka/media_session',
  );

  @override
  void build() {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;

    // Disconnect, or another server: off until the app reaches it. The new
    // address lands while the status still reads `connected` to the old one.
    ref.listen(
      connectionSettingsProvider.select(
        (settings) => settings.isSet ? settings.address : null,
      ),
      (_, _) => _disable(),
    );
    // The app's own connection dropping leaves it to the notification's.
    ref.listen(connectionStateProvider, (_, status) {
      if (status == ConnectionStatus.connected) _follow();
    });
    // A resume that finds the app still connected (its stale sockets rebuilt
    // in place) never passes through another status, but the notification
    // may have given up meanwhile.
    ref.listen(appLifecycleProvider, (_, state) {
      if (state == AppLifecycleState.resumed &&
          ref.read(connectionStateProvider) == ConnectionStatus.connected) {
        _follow();
      }
    });
    ref.onDispose(_disable);
    _follow();
  }

  void _follow() {
    final settings = ref.read(connectionSettingsProvider);
    final ServerAddress? address = settings.isSet ? settings.address : null;
    if (address == null ||
        ref.read(connectionStateProvider) != ConnectionStatus.connected) {
      _disable();
      return;
    }
    _methodChannel.invokeMethod<void>('enableNotification', {
      'host': address.host,
      'port': address.port,
      'scheme': address.scheme,
    });
  }

  void _disable() {
    _methodChannel.invokeMethod<void>('disableNotification').ignore();
  }
}

final mediaNotificationProvider =
    NotifierProvider<MediaNotificationNotifier, void>(
      MediaNotificationNotifier.new,
    );
