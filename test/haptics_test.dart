import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kalinka/utils/haptics.dart';

import 'support/haptic_recorder.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  HapticRecorder on(TargetPlatform platform) {
    debugDefaultTargetPlatformOverride = platform;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    return HapticRecorder.install();
  }

  Future<void> playSimple() async {
    KalinkaHaptics.selectionClick();
    KalinkaHaptics.lightImpact();
    KalinkaHaptics.mediumImpact();
    KalinkaHaptics.success();
    await Future<void>.delayed(Duration.zero);
  }

  const simple = [
    'selectionClick',
    'lightImpact',
    'mediumImpact',
    'successNotification',
  ];

  group('Android', () {
    test('plays the standard haptics as touch feedback', () async {
      final haptics = on(TargetPlatform.android);
      await playSimple();
      expect(haptics.calls, simple);
    });

    test('a swipe commit plays the native composition alone', () async {
      final haptics = on(TargetPlatform.android);
      await KalinkaHaptics.corkPop();
      await KalinkaHaptics.hapticDelete();
      expect(haptics.calls, ['native:hapticCorkPop', 'native:hapticDelete']);
    });

    test('a composition the device cannot play falls back', () async {
      final haptics = on(TargetPlatform.android)..nativePlays = false;
      await KalinkaHaptics.corkPop();
      expect(haptics.calls, ['native:hapticCorkPop', 'mediumImpact']);
    });

    test('a failing native channel falls back without throwing', () async {
      final haptics = on(TargetPlatform.android)..nativePlays = null;
      await KalinkaHaptics.hapticDelete();
      expect(haptics.calls, ['native:hapticDelete', 'mediumImpact']);
    });

    test('a missing native plugin falls back without throwing', () async {
      final haptics = on(TargetPlatform.android);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('org.kalinka.kalinka/media_session'),
            null,
          );
      await KalinkaHaptics.corkPop();
      expect(haptics.calls, ['mediumImpact']);
    });
  });

  group('iOS', () {
    test('plays the standard haptics', () async {
      final haptics = on(TargetPlatform.iOS);
      await playSimple();
      expect(haptics.calls, simple);
    });

    test('swipe commits use the Taptic Engine, never the channel', () async {
      final haptics = on(TargetPlatform.iOS);
      await KalinkaHaptics.corkPop();
      await KalinkaHaptics.hapticDelete();
      expect(haptics.calls, ['heavyImpact', 'lightImpact', 'heavyImpact']);
    });
  });

  test('desktop plays nothing', () async {
    for (final platform in [
      TargetPlatform.linux,
      TargetPlatform.macOS,
      TargetPlatform.windows,
    ]) {
      final haptics = on(platform);
      await playSimple();
      await KalinkaHaptics.corkPop();
      await KalinkaHaptics.hapticDelete();
      expect(haptics.calls, isEmpty, reason: '$platform');
    }
  });
}
