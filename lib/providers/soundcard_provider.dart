import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'box_control_provider.dart';
import 'connection_settings_provider.dart';
import 'demo_mode.dart';
import 'kalinka_player_api_provider.dart';
import 'supervisor_api.dart';
import 'toast_provider.dart';

/// A Raspberry Pi box whose supervisor can set up its sound card, and the
/// renderer on it that plays through the card.
class SoundcardBox {
  final SupervisorApi api;
  final BoxIdentity identity;

  /// Pointed at the new card once the box is back; null on a box with none.
  final String? rendererId;

  const SoundcardBox({
    required this.api,
    required this.identity,
    this.rendererId,
  });

  @override
  bool operator ==(Object other) =>
      other is SoundcardBox &&
      identical(other.api, api) &&
      other.identity == identity &&
      other.rendererId == rendererId;

  @override
  int get hashCode => Object.hash(identityHashCode(api), identity, rendererId);
}

/// The connected server's own box, when its supervisor can set up its sound
/// card.
final serverSoundcardBoxProvider = FutureProvider<SoundcardBox?>((ref) async {
  final control = await ref.watch(boxControlProvider.future);
  final api = ref.watch(supervisorApiProvider);
  if (control == null || api == null || !control.info.setsSoundcard) {
    return null;
  }
  return SoundcardBox(
    api: api,
    identity: BoxIdentity(serverId: control.serverId),
    rendererId: control.info.rendererId,
  );
});

/// The box [rendererId] plays on, when its supervisor can set up its sound
/// card: the server's own, or the box at the address the renderer connected
/// from, which must name the renderer as its own.
final rendererSoundcardBoxProvider = FutureProvider.autoDispose
    .family<SoundcardBox?, String>((ref, rendererId) async {
      final own = await ref.watch(serverSoundcardBoxProvider.future);
      if (own != null && own.rendererId == rendererId) return own;
      final settings = ref.watch(connectionSettingsProvider);
      if (ref.watch(demoModeProvider) ||
          !settings.isSet ||
          settings.scheme != 'http') {
        return null;
      }
      final String? address;
      try {
        final renderers = await ref.watch(kalinkaProxyProvider).listRenderers();
        address = renderers
            .where((r) => r.rendererId == rendererId)
            .firstOrNull
            ?.address;
      } catch (_) {
        return null;
      }
      if (address == null) return null;
      final api = ref.watch(supervisorAtProvider(address));
      final info = await api.info();
      if (info == null ||
          !info.compatible ||
          !info.setsSoundcard ||
          info.rendererId != rendererId) {
        return null;
      }
      return SoundcardBox(
        api: api,
        identity: BoxIdentity(serverId: info.serverId, rendererId: rendererId),
        rendererId: rendererId,
      );
    });

/// What [box] knows about its sound card.
final soundcardReportProvider = FutureProvider.autoDispose
    .family<SoundcardReport?, SoundcardBox>((ref, box) => box.api.soundcard());

/// How often a change follows the box through its restart.
final soundcardPollProvider = Provider<Duration>(
  (ref) => const Duration(seconds: 3),
);

/// Polls of the box, about five minutes, before a restart counts as failed.
const _restartPolls = 100;

/// Polls of the server, about two minutes, for the renderer to come back.
const _rendererPolls = 40;

enum SoundcardStep { idle, applying, restarting }

/// Sets [box] up for a card and, when the box restarts to load it, follows it
/// back and points its renderer at the new card. Kept past the page that
/// started it, so leaving settings does not abandon the change.
class SoundcardChange extends Notifier<SoundcardStep> {
  SoundcardChange(this.box);

  final SoundcardBox box;

  @override
  SoundcardStep build() => SoundcardStep.idle;

  /// Throws [BoxActionException] when the box refuses; what happens after it
  /// accepted is reported in toasts.
  Future<void> apply(SoundcardOption card) async {
    state = SoundcardStep.applying;
    final bool restarts;
    try {
      restarts = await box.api.setSoundcard(card.name, box.identity);
    } catch (_) {
      state = SoundcardStep.idle;
      rethrow;
    }
    if (!restarts) {
      _finish('${card.label} is set up. Nothing needed a restart.');
      return;
    }
    state = SoundcardStep.restarting;
    _toast('The box restarts to switch ${card.label} on.');
    final report = await _backAfterRestart(waitForCard: card.kind != 'none');
    if (!ref.mounted) return;
    final pcm = report?.activePcm;
    if (report == null) {
      _finish(
        'The box has not come back after five minutes. Check that it has '
        'power and a network connection.',
        isError: true,
      );
    } else if (card.kind == 'none') {
      _finish('The box is back, set up without a HAT.');
    } else if (pcm == null) {
      _finish(
        'The box is back, but the sound card did not come up. Check that the '
        'HAT sits firmly on the pins.',
        isError: true,
      );
    } else if (box.rendererId == null || !await _playThrough(pcm)) {
      _finish(
        '${report.name ?? card.label} is up. Choose it in the output’s '
        'settings once the output is back.',
      );
    } else {
      _finish('The box is back, playing through ${report.name ?? card.label}.');
    }
  }

  /// The box's report once it has gone down and answered again with its new
  /// card up, or with none when [waitForCard] is false; null if it never
  /// came back.
  Future<SoundcardReport?> _backAfterRestart({
    required bool waitForCard,
  }) async {
    var wentDown = false;
    SoundcardReport? last;
    for (var i = 0; i < _restartPolls; i++) {
      await Future<void>.delayed(ref.read(soundcardPollProvider));
      if (!ref.mounted) return null;
      if (await box.api.info() == null) {
        wentDown = true;
        continue;
      }
      if (!wentDown) continue;
      last = await box.api.soundcard();
      if (last != null && (!waitForCard || last.activePcm != null)) return last;
    }
    return last;
  }

  /// Points the box's renderer at [pcm] once the server lists it again;
  /// false when it did not come back or refused.
  Future<bool> _playThrough(String pcm) async {
    final rendererId = box.rendererId!;
    for (var i = 0; i < _rendererPolls; i++) {
      if (!ref.mounted) return false;
      final api = ref.read(kalinkaProxyProvider);
      try {
        final renderers = await api.listRenderers();
        if (renderers.any((r) => r.rendererId == rendererId && r.isConnected)) {
          final result = await api.updateRendererConfig(rendererId, {
            'output.device': pcm,
          });
          return result.rejected.isEmpty;
        }
      } catch (_) {
        // The server may still be starting on the same box.
      }
      await Future<void>.delayed(ref.read(soundcardPollProvider));
    }
    return false;
  }

  void _finish(String message, {bool isError = false}) {
    if (!ref.mounted) return;
    state = SoundcardStep.idle;
    ref.invalidate(soundcardReportProvider(box));
    _toast(message, isError: isError);
  }

  void _toast(String message, {bool isError = false}) =>
      ref.read(toastProvider.notifier).show(message, isError: isError);
}

final soundcardChangeProvider =
    NotifierProvider.family<SoundcardChange, SoundcardStep, SoundcardBox>(
      SoundcardChange.new,
    );
