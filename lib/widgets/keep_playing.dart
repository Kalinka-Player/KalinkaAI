import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/connection_state_provider.dart';
import '../providers/kalinka_player_api_provider.dart';
import '../providers/queue_features_provider.dart';
import '../providers/server_refusal.dart';
import '../providers/toast_provider.dart';
import '../theme/app_theme.dart';
import 'tap_highlight.dart';

const _offerLine = 'Turn on to add tracks like these and play on';

/// Saves the server's Keep playing as [enabled] and says in a toast what came
/// of it: the tracks it added, that none came where the queue had run out and
/// asked for them, or why it could not be saved. [inPanel] as for
/// [ToastNotifier.show].
Future<void> switchKeepPlaying(
  WidgetRef ref,
  bool enabled, {
  bool inPanel = false,
}) async {
  final toast = ref.read(toastProvider.notifier);
  final asksForTracks = enabled && ref.read(keepPlayingOfferedProvider);
  try {
    final added = await ref.read(kalinkaProxyProvider).setKeepPlaying(enabled);
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

/// What Up next shows when nothing follows the playing track: "Queue is
/// empty", or, where [keepPlayingOfferedProvider] holds, an offer to turn Keep
/// playing on, which carries the queue on in one tap. The offer stays, inert,
/// until the server answers, so one tap asks once. Takes the width it is given,
/// and fits a two-line row's height.
class EmptyUpNext extends ConsumerStatefulWidget {
  const EmptyUpNext({super.key});

  @override
  ConsumerState<EmptyUpNext> createState() => _EmptyUpNextState();
}

class _EmptyUpNextState extends ConsumerState<EmptyUpNext> {
  bool _asking = false;

  Future<void> _turnOn() async {
    setState(() => _asking = true);
    await switchKeepPlaying(ref, true, inPanel: true);
    if (mounted) setState(() => _asking = false);
  }

  @override
  Widget build(BuildContext context) {
    if (!_asking && !ref.watch(keepPlayingOfferedProvider)) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'Queue is empty',
            style: KalinkaTextStyles.queueItemArtist,
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    final away = ref.watch(
      connectionStateProvider.select((s) => s.isInterrupted),
    );
    return _KeepPlayingOffer(
      asking: _asking,
      onTap: _asking || away ? null : _turnOn,
    );
  }
}

class _KeepPlayingOffer extends StatelessWidget {
  final bool asking;
  final VoidCallback? onTap;

  const _KeepPlayingOffer({required this.asking, required this.onTap});

  static const _tileSize = 40.0;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: 'Keep playing. $_offerLine',
      child: TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          alignment: Alignment.centerLeft,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ).copyWith(overlayColor: kalinkaRowOverlay),
        child: ExcludeSemantics(
          child: Row(
            children: [
              Container(
                width: _tileSize,
                height: _tileSize,
                decoration: BoxDecoration(
                  color: KalinkaColors.surfaceElevated,
                  borderRadius: BorderRadius.circular(6),
                ),
                alignment: Alignment.center,
                child: asking
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: KalinkaColors.textSecondary,
                        ),
                      )
                    : const Icon(
                        Icons.all_inclusive_rounded,
                        size: 20,
                        color: KalinkaColors.textSecondary,
                      ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Keep playing',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: KalinkaTextStyles.queueItemTitle.copyWith(
                        fontSize: 14,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _offerLine,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: KalinkaTextStyles.queueItemArtist.copyWith(
                        fontSize: 12,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
