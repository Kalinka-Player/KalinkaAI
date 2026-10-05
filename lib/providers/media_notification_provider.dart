import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/connection_settings_provider.dart';
import '../providers/connection_state_provider.dart';
import '../providers/playback_time_provider.dart' show appLifecycleProvider;

class MediaNotificationNotifier extends Notifier<void> {
  static const _methodChannel = MethodChannel(
    'org.kalinka.kalinka/media_session',
  );

  bool _enableWhenConnected = true;
  bool _wasBackgrounded = false;

  @override
  void build() {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;

    final lifecycle = ref.read(appLifecycleProvider);
    _enableWhenConnected = lifecycle == AppLifecycleState.resumed;
    _wasBackgrounded =
        lifecycle == AppLifecycleState.paused ||
        lifecycle == AppLifecycleState.hidden;
    _enableIfRequested();

    // Connection loss dismisses media controls immediately. A replay after an
    // automatic reconnect must not resurrect the dismissed notification.
    ref.listen(connectionStateProvider, (previous, status) {
      if (status == ConnectionStatus.connected) {
        _enableIfRequested();
      } else {
        if (previous == ConnectionStatus.connected) {
          _enableWhenConnected = false;
        }
        if (status == ConnectionStatus.none ||
            status == ConnectionStatus.connecting) {
          // Initial connection or an explicitly selected server.
          _enableWhenConnected = true;
        }
        _disable();
      }
    });

    // Returning to the app or explicitly retrying starts a new lifetime for
    // media controls, once the queue connection is healthy.
    ref.listen(appLifecycleProvider, (_, next) {
      if (next == AppLifecycleState.paused ||
          next == AppLifecycleState.hidden) {
        _wasBackgrounded = true;
      } else if (next == AppLifecycleState.resumed && _wasBackgrounded) {
        // Merely closing the notification shade (inactive -> resumed) is not
        // a request to bring dismissed media controls back.
        _wasBackgrounded = false;
        _enableWhenConnected = true;
        _enableIfRequested();
      }
    });
    ref.listen(manualReconnectEpochProvider, (_, _) {
      _enableWhenConnected = true;
      _enableIfRequested();
    });
    ref.onDispose(_disable);
  }

  void _enableIfRequested() {
    if (!_enableWhenConnected ||
        ref.read(connectionStateProvider) != ConnectionStatus.connected) {
      return;
    }
    final settings = ref.read(connectionSettingsProvider);
    if (!settings.isSet) return;
    _enableWhenConnected = false;
    _methodChannel.invokeMethod<void>('enableNotification', {
      'host': settings.host,
      'port': settings.port,
      'scheme': settings.scheme,
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
