import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'box_control_provider.dart';
import 'connection_settings_provider.dart';
import 'connection_state_provider.dart';
import 'demo_mode.dart';
import 'kalinka_player_api_provider.dart';
import 'renderer_provider.dart';
import 'renderer_settings_provider.dart';
import 'supervisor_api.dart';
import 'toast_provider.dart';

/// A Raspberry Pi box whose supervisor can set up its sound card, and the
/// renderer on it that plays through the card.
class SoundcardBox {
  final SupervisorApi api;
  final BoxIdentity identity;

  /// Pointed at the new card once the box is back; null on a box with none.
  final String? rendererId;

  /// The connected server runs on it, so goes down with it.
  final bool hostsServer;

  const SoundcardBox({
    required this.api,
    required this.identity,
    this.rendererId,
    this.hostsServer = false,
  });

  @override
  bool operator ==(Object other) =>
      other is SoundcardBox &&
      identical(other.api, api) &&
      other.identity == identity &&
      other.rendererId == rendererId &&
      other.hostsServer == hostsServer;

  @override
  int get hashCode =>
      Object.hash(identityHashCode(api), identity, rendererId, hostsServer);
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
    hostsServer: true,
  );
});

/// The box [rendererId] plays on, when its supervisor can set up its sound
/// card: the server's own, or the box at the address the renderer connected
/// from, which must name the renderer as its own.
final rendererSoundcardBoxProvider = FutureProvider.autoDispose
    .family<SoundcardBox?, String>((ref, rendererId) async {
      final own = await ref.watch(serverSoundcardBoxProvider.future);
      if (own != null && own.rendererId == rendererId) return own;
      ref.watch(connectionSettingsProvider.select((s) => s.address));
      final settings = ref.read(connectionSettingsProvider);
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

/// The box the selected output plays on, with what it knows about its sound
/// card; null when there is no output or its box cannot set a card up.
final outputSoundcardProvider =
    FutureProvider.autoDispose<({SoundcardBox box, SoundcardReport report})?>((
      ref,
    ) async {
      final rendererId = ref.watch(
        rendererListProvider.select((r) => r.active?.rendererId),
      );
      if (rendererId == null) return null;
      final box = await ref.watch(
        rendererSoundcardBoxProvider(rendererId).future,
      );
      if (box == null) return null;
      final report = await ref.watch(soundcardReportProvider(box).future);
      return report == null ? null : (box: box, report: report);
    });

/// The renderer setting that names the ALSA device it plays through.
const outputDevicePath = 'output.device';

/// How often a change follows the box through its restart.
final soundcardPollProvider = Provider<Duration>(
  (ref) => const Duration(seconds: 3),
);

/// Polls of the box, about five minutes, before a restart counts as failed.
const _restartPolls = 100;

/// Polls of a box that is back, about half a minute, for its new card. The
/// firmware sets a card up at boot, so one still missing by then is not
/// coming.
const _cardPolls = 10;

/// Polls of the server, about two minutes, for the renderer to come back.
const _rendererPolls = 40;

enum SoundcardStep { idle, applying, restarting, switching }

/// How a change of sound card ended.
enum SoundcardOutcome {
  /// The card is up and the box's renderer plays through it.
  playing,

  /// The card is up, but the renderer could not be pointed at it.
  up,

  /// The box is set up without a HAT.
  noHat,

  /// The box answers, but the card did not come up.
  silent,

  /// The box did not come back from its restart in time. It counts as
  /// restarting until [SoundcardChange.keepWaiting] or
  /// [SoundcardChange.stopWaiting].
  notBack,
}

/// Sets [box] up for a card and, when the box restarts to load it, follows it
/// back and points its renderer at the new card. Kept past the page that
/// started it, so leaving settings does not abandon the change.
class SoundcardChange extends Notifier<SoundcardStep> {
  SoundcardChange(this.box);

  final SoundcardBox box;

  @override
  SoundcardStep build() {
    // Only while the box is away: once it answers, its output is back.
    listenSelf(
      (_, step) => ref
          .read(restartingBoxesProvider.notifier)
          .mark(
            box,
            restarting: _restarted && step == SoundcardStep.restarting,
          ),
    );
    return SoundcardStep.idle;
  }

  /// Whether the change under way, or the last one, restarted the box.
  bool get restarted => _restarted;
  bool _restarted = false;

  /// The card the change under way, or the last one, sets up.
  SoundcardOption? get card => _card;
  SoundcardOption? _card;

  /// Whether the box did not come back in time and the change waits for
  /// [keepWaiting] or [stopWaiting]. Kept here, as the page that started the
  /// change may have been rebuilt since.
  bool get notBack => state == SoundcardStep.restarting && !_following;
  bool _following = false;

  /// Throws [BoxActionException] when the box refuses; what happens after it
  /// accepted is reported in toasts, and returned.
  Future<SoundcardOutcome> apply(SoundcardOption card) async {
    _restarted = false;
    _card = card;
    state = SoundcardStep.applying;
    final bool restarts;
    try {
      restarts = await box.api.setSoundcard(card.name, box.identity);
    } catch (_) {
      state = SoundcardStep.idle;
      rethrow;
    }
    if (!restarts) {
      return _settle(card, await box.api.soundcard(), restarted: false);
    }
    _toast('The box restarts to switch ${card.label} on.');
    return _follow(card, wentDown: false);
  }

  /// Goes on waiting for a box that did not come back in time.
  Future<SoundcardOutcome> keepWaiting(SoundcardOption card) {
    _card = card;
    return _follow(card, wentDown: true);
  }

  /// Gives up on a box that did not come back in time, so the app no longer
  /// holds for it.
  void stopWaiting() {
    if (state != SoundcardStep.restarting) return;
    state = SoundcardStep.idle;
    ref.invalidate(soundcardReportProvider(box));
  }

  Future<SoundcardOutcome> _follow(
    SoundcardOption card, {
    required bool wentDown,
  }) async {
    _restarted = true;
    _following = true;
    state = SoundcardStep.restarting;
    try {
      return await _followBack(card, wentDown: wentDown);
    } catch (_) {
      // Back to idle, or the box stays marked restarting and holds the app.
      if (ref.mounted) state = SoundcardStep.idle;
      rethrow;
    } finally {
      _following = false;
    }
  }

  Future<SoundcardOutcome> _followBack(
    SoundcardOption card, {
    required bool wentDown,
  }) async {
    if (!await _backAfterRestart(wentDown: wentDown)) {
      // Still restarting, so the app holds until the person waits on or stops.
      if (ref.mounted) {
        _toast(
          'The box has not come back after five minutes. Check that it has '
          'power and a network connection.',
          isError: true,
        );
      }
      return SoundcardOutcome.notBack;
    }
    final report = await _cardAfterRestart(waitForCard: card.kind != 'none');
    if (!ref.mounted) return SoundcardOutcome.notBack;
    if (box.hostsServer) await _reconnect();
    if (!ref.mounted) return SoundcardOutcome.notBack;
    return _settle(card, report, restarted: true);
  }

  /// Waits for the app to be back on the server, which went down with the
  /// box, retrying where it gave up on it meanwhile.
  Future<void> _reconnect() async {
    for (var i = 0; i < _rendererPolls; i++) {
      if (!ref.mounted) return;
      final status = ref.read(connectionStateProvider);
      if (status == ConnectionStatus.connected) return;
      if (status == ConnectionStatus.offline) {
        ref.read(connectionStateProvider.notifier).retryNow();
      }
      await Future<void>.delayed(ref.read(soundcardPollProvider));
    }
  }

  /// Points the renderer at the card [report] shows up, and says how it went.
  Future<SoundcardOutcome> _settle(
    SoundcardOption card,
    SoundcardReport? report, {
    required bool restarted,
  }) async {
    final pcm = report?.activePcm;
    final name = report?.name ?? card.label;
    if (card.kind == 'none') {
      _finish(
        restarted
            ? 'The box is back, set up without a HAT.'
            : 'The box is set up without a HAT.',
        reloadSettings: restarted,
      );
      return SoundcardOutcome.noHat;
    }
    if (pcm == null) {
      final advice = card.kind == 'onboard'
          ? 'Choose another card.'
          : 'Check that the HAT sits firmly on the pins.';
      _finish(
        restarted
            ? 'The box is back, but the sound card did not come up. $advice'
            : '${card.label} is set up, but did not come up. $advice',
        isError: true,
        reloadSettings: restarted,
      );
      return SoundcardOutcome.silent;
    }
    state = SoundcardStep.switching;
    if (box.rendererId == null || !await _playThrough(pcm)) {
      _finish(
        '$name is up. Choose it in the output’s settings once the output is '
        'back.',
        reloadSettings: restarted,
      );
      return SoundcardOutcome.up;
    }
    _finish(
      restarted
          ? 'The box is back, playing through $name.'
          : 'Playing through $name.',
      reloadSettings: true,
    );
    return SoundcardOutcome.playing;
  }

  /// Whether the box answered again once it had gone down, unless [wentDown]
  /// says it was seen down already. The step moves on to switching then.
  Future<bool> _backAfterRestart({required bool wentDown}) async {
    var down = wentDown;
    for (var i = 0; i < _restartPolls; i++) {
      await Future<void>.delayed(ref.read(soundcardPollProvider));
      if (!ref.mounted) return false;
      final info = await box.api.info();
      if (!ref.mounted) return false;
      if (info == null) {
        down = true;
      } else if (down) {
        state = SoundcardStep.switching;
        return true;
      }
    }
    return false;
  }

  /// The report of a box that is back, with its new card up, or at once when
  /// [waitForCard] is false; the last one if the card does not come up.
  Future<SoundcardReport?> _cardAfterRestart({
    required bool waitForCard,
  }) async {
    SoundcardReport? last;
    for (var i = 0; i < _cardPolls; i++) {
      if (i > 0) await Future<void>.delayed(ref.read(soundcardPollProvider));
      if (!ref.mounted) return last;
      last = await box.api.soundcard() ?? last;
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
            outputDevicePath: pcm,
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

  void _finish(
    String message, {
    bool isError = false,
    bool reloadSettings = false,
  }) {
    if (!ref.mounted) return;
    state = SoundcardStep.idle;
    ref.invalidate(soundcardReportProvider(box));
    if (reloadSettings) unawaited(_reloadRendererSettings());
    _toast(message, isError: isError);
  }

  /// A settings page open since before the change would still show the old
  /// card as not detected. Waits for the renderer, which a restarted box
  /// brings back after its supervisor, and keeps what the page has staged.
  Future<void> _reloadRendererSettings() async {
    final id = box.rendererId;
    if (id == null) return;
    final settings = rendererSettingsProvider(id);
    if (!ref.exists(settings)) return;
    if (!await _rendererBack(id) || !ref.mounted || !ref.exists(settings)) {
      return;
    }
    // A save under way reads the settings again itself once it is done.
    if (ref.read(settings).saving) return;
    await ref.read(settings.notifier).load(keepStaged: true);
  }

  Future<bool> _rendererBack(String rendererId) async {
    for (var i = 0; i < _rendererPolls; i++) {
      if (!ref.mounted) return false;
      try {
        final renderers = await ref.read(kalinkaProxyProvider).listRenderers();
        if (renderers.any((r) => r.rendererId == rendererId && r.isConnected)) {
          return true;
        }
      } catch (_) {
        // The server may still be starting on the same box.
      }
      await Future<void>.delayed(ref.read(soundcardPollProvider));
    }
    return false;
  }

  void _toast(String message, {bool isError = false}) =>
      ref.read(toastProvider.notifier).show(message, isError: isError);
}

final soundcardChangeProvider =
    NotifierProvider.family<SoundcardChange, SoundcardStep, SoundcardBox>(
      SoundcardChange.new,
    );

/// The boxes restarting to switch a sound card on. While one is, its output
/// — and on the server's own box the server — is away, so the app holds back
/// as it does while the server restarts. Kept whole, as a box cannot be
/// looked up while it is down.
final restartingBoxesProvider =
    NotifierProvider<RestartingBoxes, Set<SoundcardBox>>(RestartingBoxes.new);

class RestartingBoxes extends Notifier<Set<SoundcardBox>> {
  @override
  Set<SoundcardBox> build() => const {};

  void mark(SoundcardBox box, {required bool restarting}) {
    if (state.contains(box) == restarting) return;
    state = restarting ? {...state, box} : ({...state}..remove(box));
  }
}
