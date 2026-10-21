import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data_model/data_model.dart';
import '../../providers/kalinka_player_api_provider.dart';
import '../../providers/toast_provider.dart';
import '../../theme/app_theme.dart';
import '../modifier_click.dart';
import '../search/track_group_actions.dart' show kEnqueuedHold;

/// Adds one track to the end of the queue from a wide row, where there is
/// no swipe to do it. It turns to a grey check at once and holds it as
/// Enqueue holds its Added, so a second click cannot add the track twice.
class RowEnqueueButton extends ConsumerStatefulWidget {
  final BrowseItem item;

  const RowEnqueueButton({super.key, required this.item});

  /// Its square, as tall as the row's cover, and the gap before it.
  static const double size = 44;
  static const double gap = 4;

  @override
  ConsumerState<RowEnqueueButton> createState() => _RowEnqueueButtonState();
}

class _RowEnqueueButtonState extends ConsumerState<RowEnqueueButton> {
  bool _added = false;
  bool _hovering = false;
  Timer? _resetTimer;

  @override
  void dispose() {
    _resetTimer?.cancel();
    super.dispose();
  }

  Future<void> _enqueue() async {
    if (_added) return;
    setState(() => _added = true);
    final api = ref.read(kalinkaProxyProvider);
    final toast = ref.read(toastProvider.notifier);
    final title = widget.item.track?.title ?? widget.item.name ?? 'track';
    toast.beginQueueActivity('Adding to queue…');
    try {
      await api.add([widget.item.id]);
      toast.endQueueActivity('"$title" added to queue');
      if (!mounted) return;
      _resetTimer?.cancel();
      _resetTimer = Timer(kEnqueuedHold, () {
        if (mounted) setState(() => _added = false);
      });
    } catch (e) {
      // Back to + so it can be tried again straight away.
      if (mounted) setState(() => _added = false);
      toast.endQueueActivity('Failed to add: $e', isError: true);
    }
  }

  void _setHover(bool value) {
    if (value == _hovering) return;
    setState(() => _hovering = value);
  }

  @override
  Widget build(BuildContext context) {
    final hot = _hovering && !_added;
    final title = widget.item.track?.title ?? widget.item.name ?? 'track';
    return ClickAtOnce(
      child: Tooltip(
        message: _added ? 'Added to queue' : 'Add to queue',
        excludeFromSemantics: true,
        child: MergeSemantics(
          child: Semantics(
            button: true,
            enabled: !_added,
            label: _added ? 'Added to queue' : 'Add $title to queue',
            // As tall as the row's cover, so showing or hiding it never
            // changes the row's height.
            child: SizedBox(
              width: RowEnqueueButton.size,
              height: RowEnqueueButton.size,
              child: Center(
                child: Material(
                  type: MaterialType.transparency,
                  child: InkWell(
                    mouseCursor: _added
                        ? SystemMouseCursors.basic
                        : WidgetStateMouseCursor.clickable,
                    customBorder: const CircleBorder(),
                    // Kept while added, so the click is taken here and
                    // never falls through to the row, which would play it.
                    onTap: _enqueue,
                    overlayColor: _added
                        ? const WidgetStatePropertyAll(Colors.transparent)
                        : null,
                    onHover: _setHover,
                    focusColor: KalinkaColors.surfaceOverlay,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 120),
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _added
                            ? Colors.transparent
                            : hot
                            ? KalinkaColors.surfaceOverlay
                            : KalinkaColors.surfaceElevated,
                        border: Border.all(
                          color: _added
                              ? KalinkaColors.borderSubtle
                              : hot
                              ? KalinkaColors.textMuted
                              : KalinkaColors.borderDefault,
                        ),
                      ),
                      child: Icon(
                        _added ? Icons.check_rounded : Icons.add_rounded,
                        size: 18,
                        color: _added
                            ? KalinkaColors.textMuted
                            : KalinkaColors.textPrimary,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
