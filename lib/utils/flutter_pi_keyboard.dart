import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Install at the messenger boundary because Flutter registers its keyboard
/// handler asynchronously after it synchronizes the platform keyboard state.
class FlutterPiBinding extends WidgetsFlutterBinding {
  @override
  BinaryMessenger createBinaryMessenger() =>
      FlutterPiKeyboardMessenger(super.createBinaryMessenger());
}

class FlutterPiKeyboardMessenger extends BinaryMessenger {
  FlutterPiKeyboardMessenger(this.delegate);
  final BinaryMessenger delegate;
  Future<ByteData?>? _returnReply;

  @override
  Future<ByteData?>? send(String channel, ByteData? message) =>
      delegate.send(channel, message);

  @override
  Future<void> handlePlatformMessage(
    String channel,
    ByteData? data,
    PlatformMessageResponseCallback? callback,
  ) =>
      // ignore: deprecated_member_use
      delegate.handlePlatformMessage(channel, data, callback);

  @override
  void setMessageHandler(String channel, MessageHandler? handler) {
    if (channel == SystemChannels.textInput.name && handler != null) {
      final codec = SystemChannels.textInput.codec;
      delegate.setMessageHandler(channel, (bytes) async {
        // flutter-pi sends performAction immediately after Return, even when
        // Flutter consumed the key to activate a key on the on-screen keypad.
        final reply = _returnReply;
        if (reply != null &&
            bytes != null &&
            codec.decodeMethodCall(bytes).method ==
                'TextInputClient.performAction') {
          _returnReply = null;
          final result = SystemChannels.keyEvent.codec.decodeMessage(
            await reply,
          );
          if (result is Map && result['handled'] == true) {
            return codec.encodeSuccessEnvelope(null);
          }
        }
        return handler(bytes);
      });
      return;
    }
    if (channel != SystemChannels.keyEvent.name || handler == null) {
      delegate.setMessageHandler(channel, handler);
      return;
    }
    delegate.setMessageHandler(channel, (bytes) {
      _returnReply = null;
      final codec = SystemChannels.keyEvent.codec;
      final message = codec.decodeMessage(bytes);
      if (message is! Map<String, dynamic> || message['toolkit'] != 'gtk') {
        return handler(bytes);
      }
      // flutter-pi encodes XKB symbols with %g, rounding the transport
      // symbols to the same JSON double. The Linux scan code survives.
      if (message['keyCode'] is double) {
        final key = kioskMediaKeys[kLinuxToPhysicalKey[message['scanCode']]];
        message['keyCode'] = (message['keyCode'] as double).toInt();
        if (key != null) message['specifiedLogicalKey'] = key.keyId;
        bytes = codec.encodeMessage(message);
      }
      final reply = handler(bytes);
      final key = kGtkToLogicalKey[message['keyCode']];
      if (message['type'] == 'keydown' &&
          (key == LogicalKeyboardKey.enter ||
              key == LogicalKeyboardKey.numpadEnter)) {
        _returnReply = reply;
      }
      return reply;
    });
  }
}

final kioskMediaKeys = {
  PhysicalKeyboardKey.mediaRewind: LogicalKeyboardKey.mediaRewind,
  PhysicalKeyboardKey.mediaFastForward: LogicalKeyboardKey.mediaFastForward,
  PhysicalKeyboardKey.audioVolumeUp: LogicalKeyboardKey.audioVolumeUp,
  PhysicalKeyboardKey.audioVolumeDown: LogicalKeyboardKey.audioVolumeDown,
  PhysicalKeyboardKey.mediaPlay: LogicalKeyboardKey.mediaPlay,
  PhysicalKeyboardKey.mediaPause: LogicalKeyboardKey.mediaPause,
  PhysicalKeyboardKey.mediaPlayPause: LogicalKeyboardKey.mediaPlayPause,
  PhysicalKeyboardKey.mediaTrackPrevious: LogicalKeyboardKey.mediaTrackPrevious,
  PhysicalKeyboardKey.mediaTrackNext: LogicalKeyboardKey.mediaTrackNext,
};
