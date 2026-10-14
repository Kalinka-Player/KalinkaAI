import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/connection_state_provider.dart';
import '../providers/indexer_status_provider.dart';
import '../theme/app_theme.dart';
import 'kalinka_button.dart';

/// Empty queue state — shown when the queue contains no tracks.
/// Displays procedural art, title, and subtitle.
///
/// While the library pipeline works, a small muted caption below the subtitle
/// shows the stage and percentage ("Indexing · 45%") so a fresh install
/// explains itself without hiding the search call to action.
///
/// When [isOffline] is true (no server connection), the content is dimmed and
/// the subtitle prompts the user to connect rather than search.
class EmptyQueueState extends ConsumerStatefulWidget {
  final bool isOffline;

  /// Leads to search; offered only while connected.
  final VoidCallback? onFindMusic;

  const EmptyQueueState({super.key, this.isOffline = false, this.onFindMusic});

  @override
  ConsumerState<EmptyQueueState> createState() => _EmptyQueueStateState();
}

class _EmptyQueueStateState extends ConsumerState<EmptyQueueState>
    with IndexerPollHolder {
  @override
  Widget build(BuildContext context) {
    // Caption only while actually connected: during offline/reconnecting the
    // retained progress is stale and would read as live.
    final connected = ref.watch(
      connectionStateProvider.select((s) => s == ConnectionStatus.connected),
    );
    final pipelineCaption = connected
        ? ref.watch(indexerStatusProvider.select((s) => s.caption))
        : null;

    final subtitle = widget.isOffline
        ? 'Connect to Server to See Music'
        : 'Search to Add Music';

    final content = LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Procedural art element
                  SizedBox(
                    width: 100,
                    height: 100,
                    child: CustomPaint(painter: _EmptyQueueArtPainter()),
                  ),
                  const SizedBox(height: 24),
                  // Title
                  Text(
                    'Nothing Queued',
                    style: KalinkaTextStyles.emptyQueueTitle,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  // Subtitle
                  Text(
                    subtitle,
                    style: KalinkaTextStyles.emptyQueueSubtitle,
                    textAlign: TextAlign.center,
                  ),
                  if (widget.onFindMusic != null && !widget.isOffline) ...[
                    const SizedBox(height: 24),
                    KalinkaButton(
                      label: 'Find music',
                      variant: KalinkaButtonVariant.neutral,
                      size: KalinkaButtonSize.normal,
                      leading: const Icon(
                        Icons.search_rounded,
                        size: 16,
                        color: KalinkaColors.textSecondary,
                      ),
                      onTap: widget.onFindMusic,
                    ),
                  ],
                  // Animated slot so the centered block doesn't jump when
                  // the pipeline caption appears or finishes mid-view.
                  AnimatedSize(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOut,
                    child: pipelineCaption == null
                        ? const SizedBox.shrink()
                        : Padding(
                            padding: const EdgeInsets.only(top: 16),
                            child: Text(
                              pipelineCaption,
                              // Screen readers skip or literalize '·'.
                              semanticsLabel:
                                  pipelineCaption.replaceAll(' · ', ', '),
                              style: KalinkaTextStyles.pipelineCaption,
                              textAlign: TextAlign.center,
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    if (widget.isOffline) {
      return Opacity(opacity: 0.45, child: content);
    }
    return content;
  }
}

/// Procedural art for the empty queue state: concentric rings with colored dots.
class _EmptyQueueArtPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = size.width / 2;

    // Three concentric rings
    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    ringPaint.color = Colors.white.withValues(alpha: 0.05);
    canvas.drawCircle(center, maxRadius * 0.90, ringPaint); // ~45px

    ringPaint.color = Colors.white.withValues(alpha: 0.04);
    canvas.drawCircle(center, maxRadius * 0.64, ringPaint); // ~32px

    ringPaint.color = Colors.white.withValues(alpha: 0.05);
    canvas.drawCircle(center, maxRadius * 0.38, ringPaint); // ~19px

    // Center accent dot
    canvas.drawCircle(
      center,
      5,
      Paint()..color = KalinkaColors.accent.withValues(alpha: 0.40),
    );

    // Gold dot offset upper-left
    canvas.drawCircle(
      Offset(center.dx - 22, center.dy - 26),
      4,
      Paint()..color = KalinkaColors.gold.withValues(alpha: 0.20),
    );

    // Small accent dot lower-right
    canvas.drawCircle(
      Offset(center.dx + 24, center.dy + 18),
      2.5,
      Paint()..color = KalinkaColors.accent.withValues(alpha: 0.25),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
