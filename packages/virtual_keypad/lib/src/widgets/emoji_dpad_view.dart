import 'package:emoji_picker_flutter/emoji_picker_flutter.dart' as emoji_picker;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';

/// An emoji view a directional pad can drive.
///
/// The picker's own view is built for touch: its cells are not focusable, so on
/// a TV the emoji page opens and the remote does nothing, with no way even to
/// get back out. This replaces that view when `enableDpadNavigation` is on,
/// keeping a cursor of its own over a category strip and the grid below it.
///
/// The touch view is untouched and still the default, so nothing changes for
/// anyone not driving the keyboard with a remote.
class EmojiDpadView extends StatefulWidget {
  /// Creates the directional-pad emoji view.
  const EmojiDpadView({
    super.key,
    required this.categories,
    required this.onEmojiSelected,
    required this.theme,
    required this.columns,
    required this.emojiSize,
    required this.emojiTextStyle,
    required this.height,
    this.onLeaveTop,
  });

  /// Every category the picker resolved, in its own order.
  final List<emoji_picker.CategoryEmoji> categories;

  /// Called with the chosen emoji's characters.
  final ValueChanged<String> onEmojiSelected;

  /// Colours and metrics, shared with the rest of the keyboard.
  final VirtualKeypadTheme theme;

  /// How many emoji sit on one row, worked out from the available width.
  final int columns;

  /// The font size each emoji glyph is painted at.
  final double emojiSize;

  /// The text style the glyphs inherit, which is how a colour emoji font is
  /// supplied on platforms whose own font cannot render them.
  final TextStyle? emojiTextStyle;

  /// The height of the whole page, matching the keyboard it replaces.
  final double height;

  /// Called when the cursor is on the category strip and travels up again, so
  /// the host can hand focus back to whatever sits above the keyboard.
  final VoidCallback? onLeaveTop;

  @override
  State<EmojiDpadView> createState() => EmojiDpadViewState();
}

/// The state of an [EmojiDpadView], exposed so the keyboard can forward key
/// events to [EmojiDpadViewState.handleKey].
class EmojiDpadViewState extends State<EmojiDpadView> {
  /// Which category the strip is pointing at.
  int _category = 0;

  /// The cursor's position in the current category, or -1 while the cursor is
  /// on the category strip itself.
  int _index = -1;

  final ScrollController _scroll = ScrollController();

  /// The emoji of the category being shown, empty when it has none.
  List<emoji_picker.Emoji> get _emoji => _category < widget.categories.length
      ? widget.categories[_category].emoji
      : const [];

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Handles one key event, returning true when it was consumed.
  ///
  /// The host forwards events here while the emoji page is showing, so the
  /// grid and the keyboard never both act on the same press.
  bool handleKey(KeyEvent event) {
    if (event is KeyUpEvent) return false;
    final key = event.logicalKey;

    if (key == LogicalKeyboardKey.arrowLeft) return _moveHorizontally(-1);
    if (key == LogicalKeyboardKey.arrowRight) return _moveHorizontally(1);
    if (key == LogicalKeyboardKey.arrowUp) return _moveVertically(-1);
    if (key == LogicalKeyboardKey.arrowDown) return _moveVertically(1);

    if (key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.gameButtonA) {
      return _activate();
    }
    return false;
  }

  bool _moveHorizontally(int delta) {
    if (_index < 0) {
      // On the strip, so move between categories.
      final next = _category + delta;
      if (next < 0 || next >= widget.categories.length) return false;
      setState(() => _category = next);
      return true;
    }
    final next = _index + delta;
    if (next < 0 || next >= _emoji.length) return false;
    setState(() => _index = next);
    _revealCursor();
    return true;
  }

  bool _moveVertically(int delta) {
    if (_index < 0) {
      if (delta < 0) {
        // Already at the top of the page, so let the host take it.
        widget.onLeaveTop?.call();
        return widget.onLeaveTop != null;
      }
      if (_emoji.isEmpty) return false;
      setState(() => _index = 0);
      _revealCursor();
      return true;
    }

    final next = _index + delta * widget.columns;
    if (next < 0) {
      // Off the top row of the grid, back onto the category strip.
      setState(() => _index = -1);
      return true;
    }
    if (next >= _emoji.length) return false;
    setState(() => _index = next);
    _revealCursor();
    return true;
  }

  bool _activate() {
    if (_index < 0) {
      // Selecting a category just keeps it and drops into the grid.
      if (_emoji.isEmpty) return false;
      setState(() => _index = 0);
      _revealCursor();
      return true;
    }
    if (_index >= _emoji.length) return false;
    widget.onEmojiSelected(_emoji[_index].emoji);
    return true;
  }

  /// Scrolls the cursor's row into view when it has moved out of it.
  void _revealCursor() {
    if (!_scroll.hasClients || _index < 0) return;
    final cell = _cellExtent;
    final row = _index ~/ widget.columns;
    final top = row * cell;
    final bottom = top + cell;
    final view = _scroll.position.viewportDimension;
    final offset = _scroll.offset;
    double? target;
    if (top < offset) {
      target = top;
    } else if (bottom > offset + view) {
      target = bottom - view;
    }
    if (target == null) return;
    _scroll.jumpTo(
      target.clamp(
        _scroll.position.minScrollExtent,
        _scroll.position.maxScrollExtent,
      ),
    );
  }

  /// The height of one grid row, which is also the width of one cell.
  double get _cellExtent => widget.emojiSize * 1.55;

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    return Container(
      height: widget.height,
      color: theme.backgroundColor,
      child: Column(
        children: [
          _buildCategoryStrip(theme),
          Expanded(child: _buildGrid(theme)),
        ],
      ),
    );
  }

  Widget _buildCategoryStrip(VirtualKeypadTheme theme) {
    return SizedBox(
      height: 40,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          for (var i = 0; i < widget.categories.length; i++)
            Expanded(
              child: GestureDetector(
                onTap: () => setState(() {
                  _category = i;
                  _index = -1;
                }),
                behavior: HitTestBehavior.opaque,
                child: Container(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 2,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    // The cursor sits on the strip only while it is not in the
                    // grid, so only one highlight shows at a time.
                    color: i == _category && _index < 0
                        ? theme.keyTextColor.withValues(alpha: 0.25)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(
                    _iconFor(widget.categories[i].category),
                    size: theme.keyTextSize * 0.9,
                    color: i == _category
                        ? theme.keyTextColor
                        : theme.keyTextColor.withValues(alpha: 0.55),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildGrid(VirtualKeypadTheme theme) {
    final emoji = _emoji;
    if (emoji.isEmpty) {
      return Center(
        child: Text(
          'No emoji in this group',
          style: TextStyle(
            fontSize: theme.keyTextSize * 0.65,
            color: theme.keyTextColor.withValues(alpha: 0.7),
          ),
        ),
      );
    }
    return GridView.builder(
      controller: _scroll,
      padding: EdgeInsets.symmetric(
        horizontal: theme.horizontalGap,
        vertical: theme.verticalGap / 2,
      ),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: widget.columns,
      ),
      itemCount: emoji.length,
      itemBuilder: (context, i) {
        final selected = i == _index;
        return GestureDetector(
          onTap: () {
            setState(() => _index = i);
            widget.onEmojiSelected(emoji[i].emoji);
          },
          behavior: HitTestBehavior.opaque,
          child: Container(
            decoration: BoxDecoration(
              color: selected
                  ? theme.keyTextColor.withValues(alpha: 0.25)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Center(
              child: Text(
                emoji[i].emoji,
                style: (widget.emojiTextStyle ?? const TextStyle()).copyWith(
                  fontSize: widget.emojiSize,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// The icon shown for one category on the strip.
  IconData _iconFor(emoji_picker.Category category) {
    switch (category) {
      case emoji_picker.Category.RECENT:
        return Icons.access_time;
      case emoji_picker.Category.SMILEYS:
        return Icons.sentiment_satisfied_alt;
      case emoji_picker.Category.ANIMALS:
        return Icons.pets;
      case emoji_picker.Category.FOODS:
        return Icons.restaurant;
      case emoji_picker.Category.ACTIVITIES:
        return Icons.sports_soccer;
      case emoji_picker.Category.TRAVEL:
        return Icons.directions_car;
      case emoji_picker.Category.OBJECTS:
        return Icons.lightbulb_outline;
      case emoji_picker.Category.SYMBOLS:
        return Icons.emoji_symbols;
      case emoji_picker.Category.FLAGS:
        return Icons.flag;
    }
  }
}
