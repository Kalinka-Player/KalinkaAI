import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;

import '../providers/connection_state_provider.dart';
import '../providers/kalinka_player_api_provider.dart';
import '../providers/queue_features_provider.dart';
import '../providers/server_refusal.dart';
import '../providers/toast_provider.dart';
import '../theme/app_theme.dart';
import 'search_cards/action_pill_button.dart';

const _offerMessage =
    'No more tracks in the queue. Continue with something similar?';

/// A [WidgetRef]'s or a [Ref]'s `read`, which [switchKeepPlaying] reads
/// providers through.
typedef ProviderRead = T Function<T>(ProviderListenable<T> provider);

/// Saves the server's Keep playing as [enabled] and says in a toast what came
/// of it: the tracks it added, that none came where the queue had run out and
/// asked for them, or why it could not be saved. [inPanel] as for
/// [ToastNotifier.show].
Future<void> switchKeepPlaying(
  ProviderRead read,
  bool enabled, {
  bool inPanel = false,
}) async {
  final toast = read(toastProvider.notifier);
  final asksForTracks = enabled && read(keepPlayingOfferedProvider);
  try {
    final added = await read(kalinkaProxyProvider).setKeepPlaying(enabled);
    if (added > 0) {
      toast.show(
        added == 1
            ? 'Keep playing added 1 track'
            : 'Keep playing added $added tracks',
        inPanel: inPanel,
      );
    } else if (asksForTracks) {
      toast.show('No tracks to recommend', inPanel: inPanel);
    }
  } catch (e) {
    toast.show(
      e is ServerRefusalException
          ? '$e'
          : 'Could not turn Keep playing ${enabled ? 'on' : 'off'}',
      isError: true,
      inPanel: inPanel,
    );
  }
}

/// The run-out offer's request to turn Keep playing on: true while it runs,
/// wherever the offer shows, so one tap asks once.
class KeepPlayingOfferRequest extends Notifier<bool> {
  @override
  bool build() => false;

  /// Turns Keep playing on and says what came of it; nothing while the last
  /// request is still under way.
  Future<void> accept() async {
    if (state) return;
    state = true;
    try {
      await switchKeepPlaying(ref.read, true, inPanel: true);
    } finally {
      if (ref.mounted) state = false;
    }
  }
}

final keepPlayingOfferRequestProvider =
    NotifierProvider<KeepPlayingOfferRequest, bool>(
      KeepPlayingOfferRequest.new,
    );

/// Whether Up next offers Keep playing: where [keepPlayingOfferedProvider]
/// holds, and until the server answers the offer's request, so the offer does
/// not give way to "Queue is empty" as the setting comes on.
final keepPlayingOfferShownProvider = Provider<bool>(
  (ref) =>
      ref.watch(keepPlayingOfferRequestProvider) ||
      ref.watch(keepPlayingOfferedProvider),
);

/// What Up next shows when nothing follows the playing track: "Queue is
/// empty", [emptyHeight] tall where that is set, or, where
/// [keepPlayingOfferShownProvider] holds, a short message offering to keep
/// playing with one button that turns Keep playing on. The offer takes its
/// natural height, which [offerHeight] measures; only its button is tappable.
class EmptyUpNext extends ConsumerWidget {
  const EmptyUpNext({super.key, this.emptyHeight});

  final double? emptyHeight;

  static const _inset = 16.0;
  static const _vertical = 8.0;
  static const _gap = 12.0;

  /// How tall the offer sets in [width], its message wrapped as it is laid
  /// out, so what holds it can make room or leave it out.
  static double offerHeight(BuildContext context, double width) {
    final painter = TextPainter(
      text: TextSpan(
        text: _offerMessage,
        style: DefaultTextStyle.of(context).style
            .merge(KalinkaTextStyles.queueItemArtist),
      ),
      textAlign: TextAlign.center,
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      textHeightBehavior: DefaultTextHeightBehavior.maybeOf(context),
    )..layout(maxWidth: math.max(0, width - 2 * _inset));
    final message = painter.height;
    painter.dispose();
    return 2 * _vertical + message + _gap + ActionPillButton.heightOf(context);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(keepPlayingOfferShownProvider)) {
      return const _KeepPlayingOffer();
    }
    return SizedBox(
      height: emptyHeight,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: _inset),
          child: Text(
            'Queue is empty',
            style: KalinkaTextStyles.queueItemArtist,
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}

class _KeepPlayingOffer extends ConsumerWidget {
  const _KeepPlayingOffer();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asking = ref.watch(keepPlayingOfferRequestProvider);
    final away = ref.watch(
      connectionStateProvider.select((s) => s.isInterrupted),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: EmptyUpNext._inset,
        vertical: EmptyUpNext._vertical,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _offerMessage,
            style: KalinkaTextStyles.queueItemArtist,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: EmptyUpNext._gap),
          // At the largest text in the narrowest pane the label would not fit.
          FittedBox(
            fit: BoxFit.scaleDown,
            child: ActionPillButton(
              label: 'Turn on Keep playing',
              accent: true,
              busy: asking,
              onTap: away
                  ? null
                  : () => ref
                        .read(keepPlayingOfferRequestProvider.notifier)
                        .accept(),
            ),
          ),
        ],
      ),
    );
  }
}
