import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/app_theme.dart';

/// The input row of the docked search surface. Chromeless — the parent
/// container paints the surface and border — so the field and the suggestion
/// list below read as one surface (Material 3 docked search bar).
///
/// A magnifier leads — the card around it already carries the AI mark; a
/// neutral ✕ (clear) and the accent send arrow surface on the right once the
/// field holds non-whitespace text.
///
/// There is deliberately no onChanged search hook: typing never triggers a
/// query. The query fires on the soft keyboard's search action, hardware
/// Enter (Shift+Enter inserts a newline), or the send button — kept for
/// mouse-only paste on desktop, where no Enter press is available.
class SearchComposer extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onSubmit;

  /// Placeholder shown while the field is empty.
  final String hint;

  /// When set, the leading mark is a back arrow that dismisses the search
  /// overlay instead of the AI sparkle. Null at rest (sparkle).
  final VoidCallback? onBack;

  const SearchComposer({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.onSubmit,
    this.hint = 'Ask for music…',
    this.onBack,
  });

  @override
  State<SearchComposer> createState() => _SearchComposerState();
}

class _SearchComposerState extends State<SearchComposer> {
  void _submit() {
    final text = widget.controller.text.trim();
    if (text.isEmpty) return;
    widget.onSubmit(text);
    widget.controller.clear();
    // Drop focus and dismiss the keyboard once the query is sent.
    widget.focusNode.unfocus();
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.enter &&
        !HardwareKeyboard.instance.isShiftPressed) {
      _submit();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    // One row, everything anchored to the top: at one line it reads as a
    // centred bar; as the field wraps taller, the leading icon and the
    // clear + send stay pinned to the first line and only the text grows
    // downward.
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 4, 6, 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Back arrow where the caller asked for one, magnifier at rest.
          if (widget.onBack != null)
            Semantics(
              label: 'Close search',
              button: true,
              child: GestureDetector(
                onTap: widget.onBack,
                behavior: HitTestBehavior.opaque,
                child: const SizedBox(
                  width: 38,
                  height: 32,
                  child: Icon(
                    Icons.arrow_back,
                    size: 20,
                    color: KalinkaColors.textSecondary,
                  ),
                ),
              ),
            )
          else
            const SizedBox(
              width: 38,
              height: 32,
              child: Icon(
                Icons.search_rounded,
                size: 19,
                color: KalinkaColors.accentTint,
              ),
            ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: Focus(
                onKeyEvent: _onKeyEvent,
                child: TextField(
                  controller: widget.controller,
                  focusNode: widget.focusNode,
                  style: KalinkaTextStyles.searchBarInput,
                  cursorColor: KalinkaColors.accent,
                  minLines: 1,
                  maxLines: 5,
                  keyboardType: TextInputType.multiline,
                  // Enter on the soft keyboard finishes the entry: submits
                  // and closes the keyboard (newlines only via Shift+Enter
                  // on hardware keyboards; pasted ones still wrap).
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _submit(),
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    hintText: widget.hint,
                    hintStyle: KalinkaTextStyles.searchPlaceholder,
                    border: InputBorder.none,
                    isCollapsed: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ),
            ),
          ),
          // Clear (✕) + send — appear only when there's text; pinned to
          // the first line as the field grows.
          _buildTrailingButtons(),
        ],
      ),
    );
  }

  void _clear() {
    widget.controller.clear();
    // Keep focus so a corrected query can be typed straight away.
    widget.focusNode.requestFocus();
  }

  Widget _buildTrailingButtons() {
    // Rebuilds on every keystroke (without firing any search) so the buttons
    // show up only once there's non-whitespace text. Results appear below the
    // bar, so a downward accent arrow reads as "send it down".
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final hasText = widget.controller.text.trim().isNotEmpty;
        if (!hasText) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Semantics(
                label: 'Clear search text',
                button: true,
                child: GestureDetector(
                  onTap: _clear,
                  behavior: HitTestBehavior.opaque,
                  child: const SizedBox(
                    width: 32,
                    height: 32,
                    child: Icon(
                      Icons.close_rounded,
                      size: 20,
                      color: KalinkaColors.textSecondary,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 2),
              Semantics(
                label: 'Send',
                button: true,
                child: GestureDetector(
                  onTap: _submit,
                  behavior: HitTestBehavior.opaque,
                  child: const SizedBox(
                    width: 32,
                    height: 32,
                    child: Icon(
                      Icons.arrow_downward_rounded,
                      size: 22,
                      color: KalinkaColors.accent,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
