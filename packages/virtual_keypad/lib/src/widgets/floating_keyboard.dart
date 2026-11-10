import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../emoji_font.dart';
import '../enums.dart';
import '../models.dart';
import '../theme.dart';
import 'keyboard.dart';

/// Controls the visibility and docking of [VirtualKeypadFloating].
class VirtualKeypadFloatingController extends ChangeNotifier {
  /// Creates a controller for a floating keyboard panel.
  ///
  /// Set [initialVisible] to true to show the draggable keypad immediately,
  /// which suits kiosk, POS, and desktop screens where the on-screen keyboard
  /// should be available before any field is focused.
  VirtualKeypadFloatingController({bool initialVisible = false})
      : _isVisible = initialVisible;

  bool _isVisible;
  Alignment? _pendingAlignment;

  /// Whether the floating keyboard should be visible.
  bool get isVisible => _isVisible;

  /// Shows the floating keyboard.
  void show() {
    if (_isVisible) return;
    _isVisible = true;
    notifyListeners();
  }

  /// Hides the floating keyboard.
  void hide() {
    if (!_isVisible) return;
    _isVisible = false;
    notifyListeners();
  }

  /// Toggles the floating keyboard visibility.
  void toggle() {
    _isVisible ? hide() : show();
  }

  /// Requests docking the panel to the top.
  void dockTop() {
    _pendingAlignment = Alignment.topCenter;
    notifyListeners();
  }

  /// Requests docking the panel to the bottom.
  void dockBottom() {
    _pendingAlignment = Alignment.bottomCenter;
    notifyListeners();
  }

  /// Consumes and returns the dock alignment requested by [dockTop] or
  /// [dockBottom], or null when no dock was requested.
  Alignment? takePendingAlignment() {
    final alignment = _pendingAlignment;
    _pendingAlignment = null;
    return alignment;
  }
}

/// Controls how [VirtualKeypadFloating] decides when the panel is visible.
enum VirtualKeypadFloatingVisibilityMode {
  /// The keyboard appears when a target field needs it and hides on demand.
  onDemand,

  /// The keyboard stays visible until explicitly closed or hidden.
  persistent,
}

/// A floating, draggable host for [VirtualKeypad].
///
/// This widget adds a new presentation mode without changing the existing
/// inline [VirtualKeypad] behavior. It keeps an internal [VirtualKeypad]
/// mounted at all times so scoped and standalone input routing continue to
/// work as they do today, while rendering the keyboard in a movable floating
/// panel above [child].
///
/// Use this when you want the keyboard to appear as a draggable overlay while
/// keeping the current package architecture intact. It suits a floating keypad
/// on a desktop, kiosk, or point of sale screen where an inline keyboard would
/// consume too much of the layout.
class VirtualKeypadFloating extends StatefulWidget {
  /// Creates a floating keyboard host.
  const VirtualKeypadFloating({
    super.key,
    required this.child,
    this.type,
    this.inputAction,
    this.height = 280,
    this.width,
    this.maxWidth = 680,
    this.theme = VirtualKeypadTheme.light,
    this.feedback = KeyFeedback.sound,
    this.onKeyPressed,
    this.onKeyPressedWithText,
    this.onStandaloneInputAction,
    this.availableLanguages,
    this.initialLanguage,
    this.onLanguageChanged,
    this.customLayout,
    this.enableEmojiKey = false,
    this.emojiTextStyle,
    this.colorEmojiFontLoader,
    this.checkEmojiPlatformCompatibility = false,
    this.enableDpadNavigation = false,
    this.standalone = false,
    this.controller,
    this.visibilityMode = VirtualKeypadFloatingVisibilityMode.onDemand,
    this.animationDuration = const Duration(milliseconds: 200),
    this.animationCurve = Curves.easeInOut,
    this.initialAlignment = Alignment.bottomCenter,
    this.margin = const EdgeInsets.all(12),
    this.borderRadius = 12,
    this.showToolbar = true,
    this.showCloseButton = true,
    this.showDockButtons = true,
  })  : assert(
          type != KeyboardType.custom || customLayout != null,
          'VirtualKeypadFloating.customLayout is required when type is KeyboardType.custom.',
        ),
        assert(
          customLayout == null || type == KeyboardType.custom,
          'VirtualKeypadFloating.customLayout can only be used when type is KeyboardType.custom.',
        ),
        assert(
          visibilityMode != VirtualKeypadFloatingVisibilityMode.persistent ||
              controller != null,
          'VirtualKeypadFloating.controller is required when visibilityMode is persistent.',
        );

  /// Content rendered underneath the floating keyboard panel.
  final Widget child;

  /// Override keyboard type. If null, uses the type from the focused text field.
  final KeyboardType? type;

  /// Override input action displayed on the enter/done key.
  final TextInputAction? inputAction;

  /// Height of the keyboard in logical pixels.
  final double height;

  /// Width of the keyboard. If null, a responsive floating width is used.
  final double? width;

  /// Maximum width to use when [width] is not provided.
  final double maxWidth;

  /// Visual theme for the keyboard.
  final VirtualKeypadTheme theme;

  /// Haptic and sound confirmation for each key press.
  ///
  /// Defaults to [KeyFeedback.sound]. Forwarded to the keypad inside the
  /// floating panel; see [KeyFeedback].
  final KeyFeedback feedback;

  /// Optional callback invoked when any key is pressed.
  final void Function(VirtualKey key)? onKeyPressed;

  /// Optional callback invoked when any key is pressed with resolved text.
  final void Function(VirtualKey key, String? text)? onKeyPressedWithText;

  /// Called when a submit-style action key is pressed in standalone mode.
  final void Function(KeyAction action, String text)? onStandaloneInputAction;

  /// Ordered list of language codes that can be switched from the keyboard.
  final List<String>? availableLanguages;

  /// Preferred initial language for the keyboard.
  final String? initialLanguage;

  /// Called when the user selects a new language from the keyboard picker.
  final ValueChanged<String>? onLanguageChanged;

  /// Custom layout when [type] is [KeyboardType.custom].
  final KeyboardLayout? customLayout;

  /// When true, text-style keyboards expose an emoji page.
  final bool enableEmojiKey;

  /// Text style used to paint the emoji glyphs in the emoji page.
  ///
  /// Leave null to use the platform emoji font on native and the bundled
  /// monochrome font on web, which renders offline. See
  /// [VirtualKeypad.emojiTextStyle].
  final TextStyle? emojiTextStyle;

  /// Loads a color emoji font at runtime on web, replacing the bundled
  /// monochrome one. Off by default.
  ///
  /// See [VirtualKeypad.colorEmojiFontLoader].
  final EmojiFontBytesLoader? colorEmojiFontLoader;

  /// When true, emoji the platform cannot render are filtered out of the grid.
  ///
  /// Android only, and off by default. See
  /// [VirtualKeypad.checkEmojiPlatformCompatibility].
  final bool checkEmojiPlatformCompatibility;

  /// When true, the keys can be driven with a D-pad or remote control.
  ///
  /// See [VirtualKeypad.enableDpadNavigation]. Note that this navigates the
  /// keys only; dragging the floating panel itself still needs a pointer.
  final bool enableDpadNavigation;

  /// When true, the keyboard works with any standard Flutter [TextField].
  final bool standalone;

  /// Optional controller for showing, hiding, and docking the floating panel.
  final VirtualKeypadFloatingController? controller;

  /// Determines whether the floating panel is demand-driven or persistent.
  final VirtualKeypadFloatingVisibilityMode visibilityMode;

  /// Duration for show/hide animations.
  final Duration animationDuration;

  /// Animation curve for show/hide transitions.
  final Curve animationCurve;

  /// Initial alignment of the floating panel inside the available safe area.
  final Alignment initialAlignment;

  /// Padding between the floating panel and the host edges.
  final EdgeInsets margin;

  /// Border radius applied to the entire floating panel.
  ///
  /// This rounds the toolbar and keyboard body together as one clipped surface.
  final double borderRadius;

  /// Whether to show the floating toolbar.
  final bool showToolbar;

  /// Whether to show a close button in the toolbar.
  final bool showCloseButton;

  /// Whether to show dock-to-top and dock-to-bottom buttons.
  final bool showDockButtons;

  @override
  State<VirtualKeypadFloating> createState() => _VirtualKeypadFloatingState();
}

class _VirtualKeypadFloatingState extends State<VirtualKeypadFloating> {
  static const double _toolbarHeight = 44;
  static const ValueKey<String> panelKey = ValueKey(
    'virtual_keypad_floating_panel',
  );

  late Offset _normalizedAnchor = Offset(
    (widget.initialAlignment.x + 1) / 2,
    (widget.initialAlignment.y + 1) / 2,
  );
  bool _keyboardRequestedVisible = false;

  bool get _visible {
    switch (widget.visibilityMode) {
      case VirtualKeypadFloatingVisibilityMode.onDemand:
        return _keyboardRequestedVisible;
      case VirtualKeypadFloatingVisibilityMode.persistent:
        return widget.controller?.isVisible ?? false;
    }
  }

  @override
  void initState() {
    super.initState();
    widget.controller?.addListener(_handleControllerChanged);
  }

  @override
  void didUpdateWidget(covariant VirtualKeypadFloating oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?.removeListener(_handleControllerChanged);
      widget.controller?.addListener(_handleControllerChanged);
    }
  }

  @override
  void dispose() {
    widget.controller?.removeListener(_handleControllerChanged);
    super.dispose();
  }

  void _setVisible(bool visible) {
    if (_keyboardRequestedVisible == visible) return;
    setState(() => _keyboardRequestedVisible = visible);
  }

  void _dockTop() {
    setState(() => _normalizedAnchor = const Offset(0.5, 0.0));
  }

  void _dockBottom() {
    setState(() => _normalizedAnchor = const Offset(0.5, 1.0));
  }

  void _closeKeyboard() {
    FocusManager.instance.primaryFocus?.unfocus();
    if (widget.visibilityMode ==
        VirtualKeypadFloatingVisibilityMode.persistent) {
      widget.controller?.hide();
    }
  }

  void _handleControllerChanged() {
    final alignment = widget.controller?.takePendingAlignment();
    if (alignment != null) {
      _normalizedAnchor = Offset(
        (alignment.x + 1) / 2,
        (alignment.y + 1) / 2,
      );
    }

    if (!mounted) return;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final mediaQuery = MediaQuery.of(context);
        final panelBorderRadius = BorderRadius.circular(widget.borderRadius);
        final safePadding = EdgeInsets.only(
          left: mediaQuery.padding.left + widget.margin.left,
          top: mediaQuery.padding.top + widget.margin.top,
          right: mediaQuery.padding.right + widget.margin.right,
          bottom: mediaQuery.padding.bottom + widget.margin.bottom,
        );

        final availableWidth = math.max(
          0,
          constraints.maxWidth - safePadding.left - safePadding.right,
        );
        final availableHeight = math.max(
          0,
          constraints.maxHeight - safePadding.top - safePadding.bottom,
        );

        final effectiveWidth = (widget.width != null
                ? math.min(widget.width!, availableWidth)
                : math.min(widget.maxWidth, availableWidth))
            .toDouble();
        final toolbarHeight = widget.showToolbar ? _toolbarHeight : 0.0;
        final panelHeight = widget.height + toolbarHeight;
        final travelWidth = math.max(0, availableWidth - effectiveWidth);
        final travelHeight = math.max(0, availableHeight - panelHeight);
        final left = safePadding.left + travelWidth * _normalizedAnchor.dx;
        final top = safePadding.top + travelHeight * _normalizedAnchor.dy;

        return Stack(
          fit: StackFit.expand,
          children: [
            widget.child,
            Positioned(
              left: left,
              top: top,
              width: effectiveWidth,
              child: IgnorePointer(
                ignoring: !_visible,
                child: ExcludeSemantics(
                  excluding: !_visible,
                  child: AnimatedOpacity(
                    duration: widget.animationDuration,
                    curve: widget.animationCurve,
                    opacity: _visible ? 1 : 0,
                    child: AnimatedSlide(
                      duration: widget.animationDuration,
                      curve: widget.animationCurve,
                      offset: _visible ? Offset.zero : const Offset(0, 0.08),
                      child: TextFieldTapRegion(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: panelBorderRadius,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.16),
                                blurRadius: 20,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: panelBorderRadius,
                            child: Material(
                              key: panelKey,
                              color: widget.theme.backgroundColor,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (widget.showToolbar)
                                    _FloatingKeyboardToolbar(
                                      theme: widget.theme,
                                      borderRadius: widget.borderRadius,
                                      showCloseButton: widget.showCloseButton,
                                      showDockButtons: widget.showDockButtons,
                                      onClose: _closeKeyboard,
                                      onDockTop: _dockTop,
                                      onDockBottom: _dockBottom,
                                      onPanUpdate: (details) {
                                        if (travelWidth == 0 &&
                                            travelHeight == 0) {
                                          return;
                                        }

                                        setState(() {
                                          _normalizedAnchor = Offset(
                                            travelWidth == 0
                                                ? _normalizedAnchor.dx
                                                : (_normalizedAnchor.dx +
                                                        details.delta.dx /
                                                            travelWidth)
                                                    .clamp(0.0, 1.0),
                                            travelHeight == 0
                                                ? _normalizedAnchor.dy
                                                : (_normalizedAnchor.dy +
                                                        details.delta.dy /
                                                            travelHeight)
                                                    .clamp(0.0, 1.0),
                                          );
                                        });
                                      },
                                    ),
                                  VirtualKeypad(
                                    type: widget.type,
                                    inputAction: widget.inputAction,
                                    height: widget.height,
                                    width: effectiveWidth,
                                    theme: widget.theme,
                                    feedback: widget.feedback,
                                    onKeyPressed: widget.onKeyPressed,
                                    onKeyPressedWithText:
                                        widget.onKeyPressedWithText,
                                    onStandaloneInputAction:
                                        widget.onStandaloneInputAction,
                                    availableLanguages:
                                        widget.availableLanguages,
                                    initialLanguage: widget.initialLanguage,
                                    onLanguageChanged: widget.onLanguageChanged,
                                    customLayout: widget.customLayout,
                                    enableEmojiKey: widget.enableEmojiKey,
                                    emojiTextStyle: widget.emojiTextStyle,
                                    colorEmojiFontLoader:
                                        widget.colorEmojiFontLoader,
                                    checkEmojiPlatformCompatibility:
                                        widget.checkEmojiPlatformCompatibility,
                                    enableDpadNavigation:
                                        widget.enableDpadNavigation,
                                    hideWhenUnfocused: false,
                                    standalone: widget.standalone,
                                    onVisibilityChanged: _setVisible,
                                    animationDuration: widget.animationDuration,
                                    animationCurve: widget.animationCurve,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _FloatingKeyboardToolbar extends StatelessWidget {
  const _FloatingKeyboardToolbar({
    required this.theme,
    required this.borderRadius,
    required this.showCloseButton,
    required this.showDockButtons,
    required this.onClose,
    required this.onDockTop,
    required this.onDockBottom,
    required this.onPanUpdate,
  });

  final VirtualKeypadTheme theme;
  final double borderRadius;
  final bool showCloseButton;
  final bool showDockButtons;
  final VoidCallback onClose;
  final VoidCallback onDockTop;
  final VoidCallback onDockBottom;
  final GestureDragUpdateCallback onPanUpdate;

  Widget _buildToolbarButton({
    required VoidCallback onPressed,
    required String tooltip,
    required IconData icon,
  }) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints.tightFor(width: 32, height: 32),
      icon: Icon(icon, size: 18),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanUpdate: onPanUpdate,
      child: Container(
        height: _VirtualKeypadFloatingState._toolbarHeight,
        decoration: BoxDecoration(
          color: theme.actionKeyColor,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(borderRadius),
            topRight: Radius.circular(borderRadius),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: IconTheme.merge(
          data: IconThemeData(color: theme.keyTextColor),
          child: DefaultTextStyle.merge(
            style: TextStyle(
              color: theme.keyTextColor,
              fontWeight: FontWeight.w600,
            ),
            child: Row(
              children: [
                const Icon(Icons.drag_handle_rounded, size: 18),
                const Spacer(),
                if (showDockButtons) ...[
                  _buildToolbarButton(
                    tooltip: 'Dock to top',
                    onPressed: onDockTop,
                    icon: Icons.vertical_align_top_rounded,
                  ),
                  _buildToolbarButton(
                    tooltip: 'Dock to bottom',
                    onPressed: onDockBottom,
                    icon: Icons.vertical_align_bottom_rounded,
                  ),
                ],
                if (showCloseButton)
                  _buildToolbarButton(
                    tooltip: 'Close keyboard',
                    onPressed: onClose,
                    icon: Icons.close_rounded,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
