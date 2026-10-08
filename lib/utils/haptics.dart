import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/services.dart';

bool get _isAndroid =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

bool get _isIOS => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

/// The app's haptic vocabulary. Kept small on purpose: taps and buttons get
/// none, because the ripple already confirms them.
///
/// Every effect is touch feedback, so the phone's own haptics setting
/// silences it. Desktop and web play nothing. Calls never throw: a device that
/// cannot play an effect drops it or falls back to [mediumImpact].
class KalinkaHaptics {
  static const _nativeChannel = MethodChannel(
    'org.kalinka.kalinka/media_session',
  );

  /// A detent passed while dragging, or a gesture unlocking under the finger.
  static void selectionClick() {
    if (_isAndroid || _isIOS) HapticFeedback.selectionClick();
  }

  /// Something settling into place: a drop, a seek released.
  static void lightImpact() {
    if (_isAndroid || _isIOS) HapticFeedback.lightImpact();
  }

  /// A mode change under a held finger, such as entering selection.
  static void mediumImpact() {
    if (_isAndroid || _isIOS) HapticFeedback.mediumImpact();
  }

  /// A long task the user may have looked away from has finished.
  static void success() {
    if (_isAndroid || _isIOS) HapticFeedback.successNotification();
  }

  /// A swipe released past its threshold that adds to the queue.
  static Future<void> corkPop() async {
    if (_isAndroid) {
      await _playNative('hapticCorkPop');
    } else if (_isIOS) {
      HapticFeedback.heavyImpact();
    }
  }

  /// A swipe released past its threshold that removes from the queue.
  static Future<void> hapticDelete() async {
    if (_isAndroid) {
      await _playNative('hapticDelete');
    } else if (_isIOS) {
      HapticFeedback.lightImpact();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      HapticFeedback.heavyImpact();
    }
  }

  static Future<void> _playNative(String method) async {
    bool played;
    try {
      played = await _nativeChannel.invokeMethod<bool>(method) ?? false;
    } catch (_) {
      played = false;
    }
    if (!played) HapticFeedback.mediumImpact();
  }
}
