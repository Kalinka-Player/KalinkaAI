import 'dart:async';
import 'dart:math';

import 'package:emoji_picker_flutter/emoji_picker_flutter.dart' as emoji_picker;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controller.dart';
import '../emoji_font.dart';
import '../layouts/accents.dart';
import 'emoji_dpad_view.dart';
import '../enums.dart';
import '../layouts/keyboard_language.dart';
import '../layouts/keyboard_layout_provider.dart';
import '../layouts/shuffle.dart';
import '../models.dart';
import '../scope.dart';
import '../standalone_input_control.dart';
import '../standalone_scope.dart';
import '../theme.dart';

String _lettersLabelForLanguageCode(String languageCode) {
  switch (languageCode) {
    case 'bn':
      return 'কখ';
    case 'hi':
      return 'अआ';
    case 'ar':
      return 'أب';
    case 'ru':
      return 'АБВ';
    case 'ja':
      return 'あ';
    case 'ko':
      return '가나';
    case 'zh':
      return '中';
    case 'th':
      return 'กข';
    default:
      return 'ABC';
  }
}

/// A customizable virtual on-screen keyboard widget.
///
/// Renders a software keyboard inside your app: QWERTY text, a numeric keypad
/// or numpad, a phone dialer, or a custom PIN pad or OTP layout. Input keeps
/// working on kiosk, POS, ATM, touchscreen, desktop, and embedded screens where
/// the system keyboard is unavailable or unwanted.
///
/// Automatically integrates with [VirtualKeypadScope] to send input to
/// the focused [VirtualKeypadTextField]. The keyboard automatically adapts
/// its layout based on the focused text field's [KeyboardType].
///
/// ```dart
/// VirtualKeypadScope(
///   child: Column(
///     children: [
///       VirtualKeypadTextField(
///         controller: controller,
///         keyboardType: KeyboardType.emailAddress,
///       ),
///       VirtualKeypad(), // Automatically shows email layout
///     ],
///   ),
/// )
/// ```
class VirtualKeypad extends StatefulWidget {
  /// Creates a virtual keyboard.
  ///
  /// When [standalone] is true, the keyboard works with any standard Flutter
  /// [TextField] or [TextFormField] without requiring [VirtualKeypadScope].
  /// It intercepts Flutter's text input system to route key presses to the
  /// currently focused text field.
  const VirtualKeypad({
    super.key,
    this.type,
    this.inputAction,
    this.height = 280,
    this.width,
    this.theme = VirtualKeypadTheme.light,
    this.feedback = KeyFeedback.sound,
    this.onKeyPressed,
    this.onKeyPressedWithText,
    this.onStandaloneInputAction,
    this.availableLanguages,
    this.initialLanguage,
    this.onLanguageChanged,
    this.enableLanguageKey = false,
    this.languagePicker,
    this.customLayout,
    this.enableEmojiKey = false,
    this.showEmojiKeyboardInitially = false,
    this.emojiTextStyle,
    this.colorEmojiFontLoader,
    this.checkEmojiPlatformCompatibility = false,
    this.accents,
    this.accentPicker,
    this.enableDpadNavigation = false,
    this.hideWhenUnfocused = false,
    this.standalone = false,
    this.onVisibilityChanged,
    this.animationDuration = const Duration(milliseconds: 200),
    this.animationCurve = Curves.easeInOut,
    this.keyBuilder,
    this.showNumberRow = false,
    this.keyShuffle = KeyShuffle.none,
    this.shuffleTrigger,
  })  : assert(
          type != KeyboardType.custom || customLayout != null,
          'VirtualKeypad.customLayout is required when type is KeyboardType.custom.',
        ),
        assert(
          customLayout == null || type == KeyboardType.custom,
          'VirtualKeypad.customLayout can only be used when type is KeyboardType.custom.',
        );

  /// Override keyboard type. If null, uses the type from the focused text field.
  final KeyboardType? type;

  /// Override input action displayed on the enter/done key.
  /// If null, uses the action from the focused text field.
  final TextInputAction? inputAction;

  /// Height of the keyboard in logical pixels.
  final double height;

  /// Width of the keyboard. Defaults to screen width if null.
  final double? width;

  /// Visual theme for the keyboard.
  final VirtualKeypadTheme theme;

  /// Haptic and sound confirmation for each key press.
  ///
  /// Defaults to [KeyFeedback.sound], which is what the keyboard already did
  /// through Material's ink response. See [KeyFeedback].
  final KeyFeedback feedback;

  /// Optional callback invoked when any key is pressed.
  final void Function(VirtualKey key)? onKeyPressed;

  /// Optional callback invoked when any key is pressed, including the
  /// inserted `text`. The text is the character inserted for character keys
  /// (respecting shift/caps), or `null` for action keys.
  final void Function(VirtualKey key, String? text)? onKeyPressedWithText;

  /// Called when a submit-style action key is pressed in standalone mode.
  ///
  /// This is useful for actions like call, search, send, next, and done when
  /// using `VirtualKeypad(standalone: true)` with standard Flutter text fields.
  /// The callback receives the pressed [KeyAction] and the current field text.
  final void Function(KeyAction action, String text)? onStandaloneInputAction;

  /// Ordered list of language codes that can be switched from the keyboard.
  ///
  /// When multiple valid codes are provided, long-pressing the space bar opens
  /// a language picker. The first valid code acts as the fallback language for
  /// this keyboard when no runtime language has been explicitly selected.
  final List<String>? availableLanguages;

  /// Preferred initial language for the keyboard.
  ///
  /// This seeds the runtime language when the app has no explicit language
  /// selection yet, or when the current runtime language is not allowed by
  /// [availableLanguages].
  final String? initialLanguage;

  /// Called when the user selects a new language from the keyboard picker.
  final ValueChanged<String>? onLanguageChanged;

  /// Adds a globe beside Space, borrowing its width rather than shrinking rows.
  final bool enableLanguageKey;

  /// Optional presentation used by both the globe and a held Space key.
  final VirtualKeypadLanguagePicker? languagePicker;

  /// Custom layout when [type] is [KeyboardType.custom].
  final KeyboardLayout? customLayout;

  /// When true, text-style keyboards expose an emoji page.
  ///
  /// This is only applied to built-in text, email, URL, password, and name
  /// layouts. Number, phone, and custom layouts are unchanged.
  final bool enableEmojiKey;

  /// When true, supported text layouts open on the emoji page by default.
  ///
  /// If the active field switches to a layout that does not support emoji,
  /// the keyboard falls back to the normal primary page.
  final bool showEmojiKeyboardInitially;

  /// Text style used to paint the emoji glyphs in the emoji page.
  ///
  /// Leave this null and the keyboard picks a sensible default per platform,
  /// so emoji render correctly with no setup:
  ///
  /// * On Android, iOS, Windows, macOS, and Linux the platform's own emoji font
  ///   is used. It is in color and already works offline.
  /// * On Flutter web the bundled [kBundledEmojiFontFamily] is used. The
  ///   CanvasKit and Skwasm renderers ignore the browser font stack and
  ///   download a Noto fallback font on demand, so without a bundled font the
  ///   first offline load paints every emoji as a blank box. The bundled font
  ///   is monochrome, which is the trade for rendering reliably offline.
  ///
  /// Set this to override that default, for example to use a color emoji font
  /// your app bundles on web:
  ///
  /// ```dart
  /// VirtualKeypad(
  ///   standalone: true,
  ///   enableEmojiKey: true,
  ///   emojiTextStyle: const TextStyle(fontFamily: 'NotoColorEmoji'),
  /// )
  /// ```
  ///
  /// This styles the emoji grid only. Emoji inserted into your own text fields
  /// are painted by your app's text style, so on web set `fontFamilyFallback`
  /// on your theme to keep them rendering offline too.
  ///
  /// Pass an empty `TextStyle()` to opt out of the bundled font entirely and
  /// let the web renderer supply its own color emoji. Those are in color, but
  /// they arrive over the network, so they are blank until the download lands
  /// and stay blank offline. [colorEmojiFontLoader] is usually the better way
  /// to get color, since it keeps the offline fallback.
  final TextStyle? emojiTextStyle;

  /// Loads a color emoji font at runtime, replacing the bundled monochrome one.
  ///
  /// Off by default. The bundled font is monochrome to keep the package small,
  /// since a color emoji font is roughly 3.9 MB against 708 KB. Supplying a
  /// loader gets you color without putting that in every app bundle: the
  /// keyboard paints the monochrome font immediately, then swaps to color if
  /// the font arrives.
  ///
  /// A failed load is not an error. The monochrome font stays and emoji keep
  /// rendering, which is what makes this safe to enable on flaky connections.
  ///
  /// The package performs no fetch of its own, so nothing leaves the device
  /// unless you write it. Only used on web, where the bundled font would
  /// otherwise apply; native platforms already render color emoji from the
  /// system font.
  ///
  /// See [VirtualKeypadColorEmoji] for the full rationale and an example.
  final EmojiFontBytesLoader? colorEmojiFontLoader;

  /// When true, emoji the platform cannot render are filtered out of the grid.
  ///
  /// This check is Android only. It removes glyphs that would otherwise paint
  /// as blank boxes on devices with an outdated system emoji font, at the cost
  /// of extra work the first time the emoji page opens. It has no effect on
  /// web, iOS, or desktop, so it is not a fix for missing emoji there. See
  /// [emojiTextStyle] for the cross-platform option.
  ///
  /// Defaults to false to keep the emoji page fast to open.
  final bool checkEmojiPlatformCompatibility;

  /// When true, the keyboard can be driven with a D-pad or remote control.
  ///
  /// This is what makes the keyboard usable on Android TV, Fire TV, and other
  /// set-top boxes, where there is no touch screen and every interaction comes
  /// from a directional pad.
  ///
  /// One key is highlighted at a time. Arrow keys move the highlight, and
  /// select, enter, space, or the primary gamepad button presses the
  /// highlighted key. Moving up or down picks the key in the neighbouring row
  /// that sits closest horizontally, so wide keys such as space and shift stay
  /// reachable.
  ///
  /// The highlight is drawn by the keyboard itself rather than by the Flutter
  /// focus system, so the focused text field keeps focus and the keyboard does
  /// not hide while the user moves around the keys. Style it with
  /// [VirtualKeypadTheme.focusBorderColor], [VirtualKeypadTheme.focusColor],
  /// and [VirtualKeypadTheme.focusBorderWidth].
  ///
  /// Defaults to false, which leaves touch and pointer behaviour untouched.
  final bool enableDpadNavigation;

  /// Whether to put a row of digits above the letters.
  ///
  /// A phone keyboard hides the digits behind its symbols page, which costs
  /// two taps for every number. A tablet or a desktop has the room to show
  /// them, and a form full of quantities or codes is much faster with them
  /// out. The row is `1` through `0`, and it is added only to the letter page:
  /// the symbols and accent pages carry their own digits already, and a
  /// numeric keypad is all digits to begin with.
  ///
  /// Defaults to false, which leaves the layouts as their language defines
  /// them.
  final bool showNumberRow;

  /// The alternates offered when a character key is held down, keyed by the
  /// lowercase base letter.
  ///
  /// Defaults to [kLatinAccents], which covers the accented letters the Latin
  /// layouts need. Pass your own map to change or extend it, or an empty map
  /// to turn the popup off. Uppercase forms are derived when shift is on, so
  /// the map only holds lowercase keys.
  final Map<String, List<String>>? accents;

  /// Optional presentation for accent choices. Insertion and shift handling
  /// stay with the keypad. Defaults to the standard vertical popup menu.
  final VirtualKeypadAccentPicker? accentPicker;

  /// When true, hides the keyboard with animation when no text field is focused.
  final bool hideWhenUnfocused;

  /// When true, the keyboard works with any standard Flutter [TextField] or
  /// [TextFormField] without requiring [VirtualKeypadScope] or
  /// [VirtualKeypadTextField].
  ///
  /// In standalone mode, the keyboard intercepts Flutter's text input system
  /// and routes key presses to whichever [TextField] currently has focus.
  ///
  /// ```dart
  /// Column(
  ///   children: [
  ///     TextField(controller: myController),
  ///     VirtualKeypad(standalone: true),
  ///   ],
  /// )
  /// ```
  final bool standalone;

  /// Called when the keyboard's active visibility changes.
  ///
  /// The callback reports whether the keyboard currently has an active target
  /// and should be shown for input. This is useful for custom containers such
  /// as floating or docked hosts that need to react to focus changes while
  /// keeping the keyboard mounted.
  final ValueChanged<bool>? onVisibilityChanged;

  /// Duration for show/hide animation when [hideWhenUnfocused] is true.
  final Duration animationDuration;

  /// Animation curve for show/hide transitions.
  final Curve animationCurve;

  /// Draws the content of a key, overriding the default label or icon.
  ///
  /// Return `null` for a key you do not want to change, which is what makes it
  /// practical to restyle one key and leave the rest alone:
  ///
  /// ```dart
  /// VirtualKeypad(
  ///   keyBuilder: (context, info) => info.key.action == KeyAction.enter
  ///       ? const Text('GO', style: TextStyle(fontWeight: FontWeight.bold))
  ///       : null,
  /// )
  /// ```
  ///
  /// This controls content only. The key's background, size, tap handling,
  /// repeat, D-pad focus and accessibility stay with the package, so a builder
  /// cannot break the keyboard's behaviour.
  final VirtualKeypadKeyBuilder? keyBuilder;

  /// When the digit keys change position, for PIN and payment entry.
  ///
  /// A fixed keypad leaks the PIN to anyone watching the hand or a camera
  /// above the terminal, because finger positions are enough. Shuffling
  /// removes that. Off by default, since it also costs the muscle memory a
  /// regular user builds.
  ///
  /// Only single digits move. Backspace, the decimal point and every other key
  /// stay put, and the full set of digits is always on screen.
  final KeyShuffle keyShuffle;

  /// Draws a fresh digit arrangement each time this fires.
  ///
  /// [KeyShuffle.onShow] reshuffles when the keypad appears, which leaves no
  /// way to reshuffle during an entry: after a wrong PIN the keypad is already
  /// on screen, and that is exactly the moment a watcher has learned the most.
  /// Fire a `ChangeNotifier` here to force a new arrangement.
  ///
  /// ```dart
  /// final reshuffle = ChangeNotifier();
  /// VirtualKeypad(keyShuffle: KeyShuffle.onShow, shuffleTrigger: reshuffle);
  /// // on a failed attempt:
  /// reshuffle.notifyListeners();
  /// ```
  ///
  /// Ignored when [keyShuffle] is [KeyShuffle.none]. You own the listenable
  /// and its disposal.
  final Listenable? shuffleTrigger;

  @override
  State<VirtualKeypad> createState() => _VirtualKeypadState();
}

class _VirtualKeypadState extends State<VirtualKeypad> {
  LayoutStage _layoutStage = LayoutStage.primary;
  LayoutStage _layoutStageBeforeEmoji = LayoutStage.primary;
  bool _shift = false;
  bool _capsLock = false;
  VirtualKeypadScopeState? _scope;
  KeyboardType? _lastKeyboardType;
  TextInputAction _lastScopedInputAction = TextInputAction.done;
  VirtualKeypadController? _lastScopedController;
  int? _lastScopedMaxLength;

  // Cache the layout when keyboard is visible for smooth close animation
  KeyboardLayout? _cachedLayout;

  /// Row of the key currently highlighted for D-pad navigation.
  int _dpadRow = 0;

  /// Column of the key currently highlighted for D-pad navigation.
  int _dpadCol = 0;

  /// Layout the D-pad highlight is currently addressing.
  ///
  /// Set during build so the key handler navigates whatever the user can
  /// actually see, including custom layouts and symbol pages.
  KeyboardLayout? _dpadLayout;

  /// The emoji grid's state while the D-pad view is showing, so key events can
  /// be handed to it instead of to the key highlight.
  final GlobalKey<EmojiDpadViewState> _emojiDpadKey =
      GlobalKey<EmojiDpadViewState>();

  /// Whether the keyboard is currently on screen.
  ///
  /// The keys are still built while the keyboard is collapsed, so this is what
  /// stops the D-pad handler from acting on an invisible keyboard.
  bool _dpadVisible = false;

  /// The one keyboard allowed to act on D-pad events.
  ///
  /// Handlers registered with [HardwareKeyboard] all run for every event, so
  /// two visible keyboards with D-pad navigation on would each insert the same
  /// character. The first to become visible claims the D-pad and holds it until
  /// it hides or is disposed.
  static _VirtualKeypadState? _dpadOwner;

  void _updateDpadOwnership(bool visible) {
    if (visible && widget.enableDpadNavigation) {
      _dpadOwner ??= this;
    } else if (identical(_dpadOwner, this)) {
      _dpadOwner = null;
    }
  }

  bool _wasVisible = false;
  bool? _reportedVisibility;
  bool _languagePickerVisible = false;

  /// Whether the accent popup is open, so a second long press cannot stack.
  bool _accentPickerVisible = false;

  // Standalone mode state
  StandaloneInputControl? _inputControl;
  bool _controlInstalled = false;
  bool _standaloneVisible = false;

  @override
  void initState() {
    super.initState();
    _reshuffle();
    widget.shuffleTrigger?.addListener(_onShuffleTrigger);
    KeyboardLayoutProvider.instance.addListener(_onLanguageChanged);
    _syncLanguageConfiguration();
    _resetLayoutStage();
    if (widget.standalone) {
      _initStandalone();
    }
    if (widget.enableDpadNavigation) {
      HardwareKeyboard.instance.addHandler(_handleDpadKey);
    }
    _startColorEmojiLoad();
    VirtualKeypadColorEmoji.isLoaded.addListener(_onColorEmojiLoaded);
  }

  /// Kicks off the runtime color emoji load, if the caller opted in.
  ///
  /// Only on web: native platforms already render color emoji from the system
  /// font, so downloading one would be wasted bytes.
  void _startColorEmojiLoad() {
    final loader = widget.colorEmojiFontLoader;
    if (!kIsWeb || loader == null) return;
    VirtualKeypadColorEmoji.load(loader);
  }

  void _onColorEmojiLoaded() {
    if (mounted) setState(() {});
  }

  /// Emoji style for the picker grid, in precedence order.
  TextStyle? get _effectiveEmojiTextStyle {
    final explicit = widget.emojiTextStyle;
    if (explicit != null) return explicit;
    if (kIsWeb && VirtualKeypadColorEmoji.isLoaded.value) {
      return const TextStyle(fontFamily: VirtualKeypadColorEmoji.fontFamily);
    }
    return defaultEmojiTextStyle();
  }

  void _initStandalone() {
    _inputControl = StandaloneInputControl(
      onShow: _onStandaloneShow,
      onHide: () {
        _standaloneVisible = false;
        // onHide can be called during build
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          setState(() {});
        });
      },
    );
    _installControl(true);
    FocusManager.instance.addListener(_onFocusChanged);
  }

  /// Install or hand back the application-wide platform text input control.
  ///
  /// [TextInput.setInputControl] replaces the control for the whole
  /// application, not just this widget, and it stays replaced until it is
  /// handed back. Every install therefore needs a matching restore, or text
  /// fields elsewhere in the app keep their system keyboard suppressed.
  void _installControl(bool install) {
    if (_inputControl == null || _controlInstalled == install) return;
    _controlInstalled = install;
    if (install) {
      TextInput.setInputControl(_inputControl!);
    } else {
      TextInput.restorePlatformInputControl();
    }
  }

  void _disposeStandalone() {
    FocusManager.instance.removeListener(_onFocusChanged);
    if (_inputControl != null) {
      _installControl(false);
      _inputControl = null;
    }
  }

  void _onFocusChanged() {
    if (!widget.standalone || !mounted) return;
    // If primary focus is lost entirely, hide keyboard
    final focus = FocusManager.instance.primaryFocus;
    if (focus == null || focus.context == null) {
      if (_standaloneVisible) {
        setState(() => _standaloneVisible = false);
      }
      return;
    }

    // If wrapped in a scope, hide when focus moves outside that scope.
    //
    // The keypad keeps the platform input control while it is alive, rather
    // than swapping it per focus change. A text field attaches to the platform
    // before FocusManager notifies its listeners, so toggling the control here
    // would apply to the field focused after next, not this one, and a scoped
    // keypad would end up suppressing exactly the fields it should leave alone.
    final myScope = VirtualKeypadStandaloneScope.maybeOf(context);
    if (myScope != null && _standaloneVisible) {
      final focusedScope = VirtualKeypadStandaloneScope.maybeOf(focus.context!);
      if (focusedScope != myScope) {
        setState(() => _standaloneVisible = false);
      }
    }
  }

  /// Called when the [StandaloneInputControl] requests the keyboard to show.
  ///
  /// If the keyboard is wrapped in a [VirtualKeypadStandaloneScope], the
  /// focused text field must be within the same scope for the keyboard to
  /// appear. This prevents the keyboard from responding to text fields that
  /// belong to a different part of the widget tree.
  void _onStandaloneShow() {
    if (!mounted) return;

    // If this keyboard is inside a VirtualKeypadStandaloneScope, only show
    // when the focused widget is in the same scope.
    final myScope = VirtualKeypadStandaloneScope.maybeOf(context);
    if (myScope != null) {
      final focusedContext = FocusManager.instance.primaryFocus?.context;
      final focusedScope = focusedContext != null
          ? VirtualKeypadStandaloneScope.maybeOf(focusedContext)
          : null;
      if (focusedScope != myScope) {
        // The focused field is outside our scope, so hide the keyboard.
        if (_standaloneVisible) setState(() => _standaloneVisible = false);
        return;
      }
    }

    _reshuffle();
    setState(() => _standaloneVisible = true);
    _onStandaloneFieldChanged();
  }

  void _onStandaloneFieldChanged() {
    if (!mounted || _inputControl == null) return;
    final newType = _inputControl!.keyboardType;
    if (_lastKeyboardType != newType) {
      _resetLayoutStage();
      _shift = false;
      _capsLock = false;
      _lastKeyboardType = newType;
    }
    _cachedLayout = _currentLayout;
    _wasVisible = true;
    setState(() {});
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!widget.standalone) {
      final newScope = VirtualKeypadScope.of(context);
      if (_scope != newScope) {
        _scope?.removeActiveControllerListener(_onActiveControllerChanged);
        _scope = newScope;
        _scope?.addActiveControllerListener(_onActiveControllerChanged);
      }
    }
  }

  @override
  void didUpdateWidget(VirtualKeypad oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.shuffleTrigger != widget.shuffleTrigger) {
      oldWidget.shuffleTrigger?.removeListener(_onShuffleTrigger);
      widget.shuffleTrigger?.addListener(_onShuffleTrigger);
    }
    if (widget.availableLanguages != oldWidget.availableLanguages ||
        widget.initialLanguage != oldWidget.initialLanguage) {
      _syncLanguageConfiguration();
    }
    if (widget.enableEmojiKey != oldWidget.enableEmojiKey ||
        widget.showEmojiKeyboardInitially !=
            oldWidget.showEmojiKeyboardInitially) {
      _resetLayoutStage();
    }
    if (widget.standalone != oldWidget.standalone) {
      if (widget.standalone) {
        // Switching to standalone
        _scope?.removeActiveControllerListener(_onActiveControllerChanged);
        _scope = null;
        _initStandalone();
      } else {
        // Switching away from standalone
        _disposeStandalone();
        _standaloneVisible = false;
      }
    }
    if (widget.colorEmojiFontLoader != oldWidget.colorEmojiFontLoader) {
      _startColorEmojiLoad();
    }
    if (widget.enableDpadNavigation != oldWidget.enableDpadNavigation) {
      if (widget.enableDpadNavigation) {
        HardwareKeyboard.instance.addHandler(_handleDpadKey);
      } else {
        HardwareKeyboard.instance.removeHandler(_handleDpadKey);
        _dpadRow = 0;
        _dpadCol = 0;
      }
    }
  }

  @override
  void dispose() {
    widget.shuffleTrigger?.removeListener(_onShuffleTrigger);
    KeyboardLayoutProvider.instance.removeListener(_onLanguageChanged);
    VirtualKeypadColorEmoji.isLoaded.removeListener(_onColorEmojiLoaded);
    if (identical(_dpadOwner, this)) {
      _dpadOwner = null;
    }
    if (widget.enableDpadNavigation) {
      HardwareKeyboard.instance.removeHandler(_handleDpadKey);
    }
    if (widget.standalone) {
      _disposeStandalone();
    } else {
      _scope?.removeActiveControllerListener(_onActiveControllerChanged);
    }
    super.dispose();
  }

  void _onActiveControllerChanged() {
    if (mounted) {
      final hasController = _scope?.hasActiveController ?? false;
      final allowPhysical = _scope?.allowPhysicalKeyboard ?? false;
      final isVisible = hasController && !allowPhysical;

      // Only reset layout when a new field gains focus (not when losing focus)
      if (isVisible) {
        final newType = _effectiveKeyboardType;
        if (_lastKeyboardType != newType) {
          _resetLayoutStage();
          _shift = false;
          _capsLock = false;
          _lastKeyboardType = newType;
        }
        _lastScopedController = _scope?.activeController;
        _lastScopedMaxLength = _scope?.activeMaxLength;
        _lastScopedInputAction =
            _scope?.activeInputAction ?? TextInputAction.done;
        // Cache the current layout while visible
        _cachedLayout = _currentLayout;
        _wasVisible = true;
      }

      setState(() {});
    }
  }

  void _onLanguageChanged() {
    _syncLanguageConfiguration();
    if (!mounted) return;

    _resetLayoutStage();
    _shift = false;
    _capsLock = false;
    _cachedLayout = _currentLayout;
    setState(() {});
  }

  void _resetLayoutStage() {
    _layoutStage = _preferredInitialLayoutStage;
    _layoutStageBeforeEmoji = LayoutStage.primary;
  }

  LayoutStage get _preferredInitialLayoutStage {
    if (widget.showEmojiKeyboardInitially && _supportsEmojiLayout) {
      return LayoutStage.emoji;
    }
    return LayoutStage.primary;
  }

  void _setLayoutStage(LayoutStage stage) {
    _layoutStage = stage;
    if (stage != LayoutStage.emoji) {
      _layoutStageBeforeEmoji = stage;
    }
  }

  List<KeyboardLanguage> get _availableLanguages {
    final codes = widget.availableLanguages;
    if (codes == null || codes.isEmpty) return const [];

    final seen = <String>{};
    final languages = <KeyboardLanguage>[];
    final provider = KeyboardLayoutProvider.instance;

    for (final code in codes) {
      if (!seen.add(code)) continue;
      final language = provider.getLanguage(code);
      if (language != null) {
        languages.add(language);
      }
    }

    return languages;
  }

  bool get _canSwitchLanguages => _availableLanguages.length > 1;

  void _syncLanguageConfiguration() {
    final provider = KeyboardLayoutProvider.instance;
    final allowedCodes =
        _availableLanguages.map((language) => language.code).toList();

    if (allowedCodes.isEmpty) {
      final initialLanguage = widget.initialLanguage;
      if (!provider.hasExplicitLanguageSelection &&
          initialLanguage != null &&
          provider.hasLanguage(initialLanguage)) {
        provider.setLanguage(initialLanguage, userInitiated: false);
      }
      return;
    }

    final currentLanguage = provider.currentLanguageCode;
    if (provider.hasExplicitLanguageSelection &&
        allowedCodes.contains(currentLanguage)) {
      return;
    }

    final initialLanguage = widget.initialLanguage;
    final targetLanguage =
        initialLanguage != null && allowedCodes.contains(initialLanguage)
            ? initialLanguage
            : allowedCodes.contains(currentLanguage)
                ? currentLanguage
                : allowedCodes.first;

    if (currentLanguage != targetLanguage) {
      provider.setLanguage(targetLanguage, userInitiated: false);
    }
  }

  /// The alternates for [character], cased to match the keyboard right now.
  List<String> _accentsFor(String character) {
    final table = widget.accents ?? kLatinAccents;
    final options = table[character.toLowerCase()];
    if (options == null || options.isEmpty) return const [];
    final upper = _shift || _capsLock;
    if (!upper) return options;
    // A plain toUpperCase gets two of these wrong. `ß` has no uppercase in
    // that mapping and stayed lowercase in an uppercase menu, and Turkish `ı`
    // becomes `I`, which is just the key being held; what a Turkish writer
    // needs on that key is the dotted capital `İ`. Anything that would only
    // repeat the held key, or an earlier option, is left out.
    final held = character.toUpperCase();
    final seen = <String>{};
    return [
      for (final o in options)
        if (_accentUppercase[o] ?? o.toUpperCase() case final u
            when u != held && seen.add(u))
          u,
    ];
  }

  /// Uppercase forms that `String.toUpperCase` does not give for an accent.
  static const Map<String, String> _accentUppercase = {
    'ß': 'ẞ',
    'ı': 'İ',
  };

  /// Shows the alternates for a held key and inserts whichever is chosen.
  Future<void> _showAccentPicker(String character, Offset at) async {
    final options = _accentsFor(character);
    if (options.isEmpty || _accentPickerVisible) return;
    setState(() => _accentPickerVisible = true);
    final overlayBox =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    try {
      final chosen = widget.accentPicker != null
          ? await widget.accentPicker!(context, options, at)
          : await showMenu<String>(
              context: context,
              position: RelativeRect.fromLTRB(
                at.dx,
                at.dy,
                overlayBox.size.width - at.dx,
                overlayBox.size.height - at.dy,
              ),
              items: [
                for (final option in options)
                  PopupMenuItem<String>(
                    value: option,
                    child: Text(
                      option,
                      style: widget.theme.effectiveKeyTextStyle.copyWith(
                        fontSize: widget.theme.keyTextSize,
                      ),
                    ),
                  ),
              ],
            );
      if (chosen != null) _insertAccent(chosen);
    } finally {
      if (mounted) setState(() => _accentPickerVisible = false);
    }
  }

  /// Inserts a chosen accent and reports it like any other character.
  ///
  /// The text is already cased, so it is inserted as it stands rather than
  /// going back through the shift handling that produced it.
  void _insertAccent(String text) {
    _playKeyFeedback();
    _insertTextIntoTarget(text);
    if (_shift && !_capsLock) {
      setState(() => _shift = false);
    }
    final key = VirtualKey.character(text: text);
    widget.onKeyPressed?.call(key);
    widget.onKeyPressedWithText?.call(key, text);
  }

  Future<void> _showLanguagePicker(Offset globalPosition) async {
    if (!_canSwitchLanguages || _languagePickerVisible) return;

    if (mounted) {
      setState(() => _languagePickerVisible = true);
    }

    final overlayBox =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    try {
      final selectedLanguage = widget.languagePicker != null
          ? await widget.languagePicker!(
              context,
              _availableLanguages.map((language) => language.code).toList(),
              KeyboardLayoutProvider.instance.currentLanguageCode,
              globalPosition)
          : await showMenu<String>(
              context: context,
              position: RelativeRect.fromLTRB(
                globalPosition.dx,
                globalPosition.dy,
                overlayBox.size.width - globalPosition.dx,
                overlayBox.size.height - globalPosition.dy,
              ),
              items: _availableLanguages.map((language) {
                final isCurrent = language.code ==
                    KeyboardLayoutProvider.instance.currentLanguageCode;

                return PopupMenuItem<String>(
                  value: language.code,
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          language.nativeName,
                          style: widget.theme.effectiveKeyTextStyle,
                        ),
                      ),
                      if (isCurrent) const Icon(Icons.check, size: 16),
                    ],
                  ),
                );
              }).toList(),
            );

      if (selectedLanguage != null) {
        final changed = KeyboardLayoutProvider.instance.setLanguage(
          selectedLanguage,
          userInitiated: true,
        );
        if (changed) {
          widget.onLanguageChanged?.call(selectedLanguage);
        }
      }
    } finally {
      if (mounted) {
        setState(() => _languagePickerVisible = false);
      }
    }
  }

  KeyboardType get _effectiveKeyboardType {
    if (widget.type != null) return widget.type!;
    if (widget.standalone && _inputControl != null) {
      return _inputControl!.keyboardType;
    }
    return _scope?.activeKeyboardType ?? _lastKeyboardType ?? KeyboardType.text;
  }

  TextInputAction get _effectiveInputAction {
    if (widget.inputAction != null) return widget.inputAction!;
    if (widget.standalone && _inputControl != null) {
      return _inputControl!.inputAction;
    }
    return _scope?.activeInputAction ?? _lastScopedInputAction;
  }

  KeyboardLayout get _currentLayout {
    final type = _effectiveKeyboardType;

    if (type == KeyboardType.custom && widget.customLayout != null) {
      return _applyShuffle(widget.customLayout!);
    }

    final inputType = _toInputType(type);
    final layoutSet = KeyboardLayoutProvider.instance.getLayouts(inputType);

    return _applyShuffle(
      _decorateLayoutWithLanguageKey(
        _decorateLayoutWithNumberRow(
          _decorateLayoutWithEmojiToggle(_getLayoutForStage(layoutSet)),
        ),
      ),
    );
  }

  KeyboardLayout _decorateLayoutWithLanguageKey(KeyboardLayout layout) {
    if (!widget.enableLanguageKey ||
        !_canSwitchLanguages ||
        layout.any((row) =>
            row.any((key) => key.action == KeyAction.switchLanguage))) {
      return layout;
    }
    return [
      for (final row in layout)
        [
          for (final key in row)
            if (key.action == KeyAction.space) ...[
              VirtualKey.action(action: KeyAction.switchLanguage),
              VirtualKey.action(
                  action: KeyAction.space,
                  text: key.text,
                  label: key.label,
                  altLabel: key.altLabel,
                  flex: max(1, key.flex - 1)),
            ] else
              key,
        ],
    ];
  }

  /// Whether a digit row belongs above this layout.
  ///
  /// Only the letter page gets one. The symbols and accent pages carry digits
  /// of their own, a numeric or phone keypad is already all digits, and the
  /// emoji picker is not a layout the user types letters on.
  bool get _wantsNumberRow {
    if (!widget.showNumberRow) return false;
    if (_layoutStage != LayoutStage.primary) return false;
    switch (_effectiveKeyboardType) {
      case KeyboardType.text:
      case KeyboardType.multiline:
      case KeyboardType.emailAddress:
      case KeyboardType.url:
      case KeyboardType.visiblePassword:
      case KeyboardType.name:
      case KeyboardType.streetAddress:
        return true;
      case KeyboardType.number:
      case KeyboardType.numberSigned:
      case KeyboardType.numberDecimal:
      case KeyboardType.phone:
      case KeyboardType.datetime:
      case KeyboardType.none:
      case KeyboardType.custom:
        return false;
    }
  }

  /// Puts `1` through `0` above [layout] when [VirtualKeypad.showNumberRow]
  /// asks for it.
  KeyboardLayout _decorateLayoutWithNumberRow(KeyboardLayout layout) {
    if (!_wantsNumberRow || layout.isEmpty) return layout;
    // A layout that already opens with ten digits needs nothing added, which
    // keeps a custom layout from growing a second row on every build.
    final first = layout.first;
    if (first.length == 10 &&
        first.every((key) => key.isCharacter && _digits.contains(key.text))) {
      return layout;
    }
    return [
      [for (final digit in _digits) VirtualKey.character(text: digit)],
      ...layout,
    ];
  }

  /// The digits of the number row, in the order a keyboard shows them.
  static const List<String> _digits = [
    '1', '2', '3', '4', '5', '6', '7', '8', '9', '0', //
  ];

  /// Applies [VirtualKeypad.keyShuffle] to [layout].
  ///
  /// The permutation is held in state rather than recomputed here, because
  /// this getter runs on every build and a fresh shuffle per build would make
  /// the digits move while the user is looking at them.
  KeyboardLayout _applyShuffle(KeyboardLayout layout) {
    if (widget.keyShuffle == KeyShuffle.none) return layout;
    final seed = _shuffleSeed;
    if (seed == null) return layout;
    return shuffleDigitKeys(layout, random: Random(seed));
  }

  /// Seed for the current permutation, or null when nothing is shuffled.
  int? _shuffleSeed;

  /// Redraws the arrangement when the caller's trigger fires.
  void _onShuffleTrigger() {
    if (widget.keyShuffle == KeyShuffle.none || !mounted) return;
    setState(_reshuffle);
  }

  /// Draws a new permutation. Called when the keypad appears, and after each
  /// keypress under [KeyShuffle.onEveryKey].
  void _reshuffle() {
    if (widget.keyShuffle == KeyShuffle.none) {
      _shuffleSeed = null;
      return;
    }
    _shuffleSeed = _shuffleRandom.nextInt(1 << 32);
  }

  final Random _shuffleRandom = Random();

  bool get _supportsEmojiLayout {
    if (!widget.enableEmojiKey) return false;

    switch (_effectiveKeyboardType) {
      case KeyboardType.text:
      case KeyboardType.multiline:
      case KeyboardType.emailAddress:
      case KeyboardType.url:
      case KeyboardType.visiblePassword:
      case KeyboardType.name:
      case KeyboardType.streetAddress:
        return true;
      case KeyboardType.number:
      case KeyboardType.numberSigned:
      case KeyboardType.numberDecimal:
      case KeyboardType.phone:
      case KeyboardType.datetime:
      case KeyboardType.none:
      case KeyboardType.custom:
        return false;
    }
  }

  KeyboardLayout _decorateLayoutWithEmojiToggle(KeyboardLayout layout) {
    if (!_supportsEmojiLayout || layout.isEmpty) {
      return layout;
    }

    final bottomRow = layout.last;
    if (bottomRow.any((key) => key.action == KeyAction.emoji)) {
      return layout;
    }

    final spaceIndex = bottomRow.indexWhere(
      (key) => key.action == KeyAction.space,
    );
    if (spaceIndex == -1) {
      return layout;
    }

    final updatedRow = List<VirtualKey>.from(bottomRow);
    final spaceKey = updatedRow[spaceIndex];
    updatedRow[spaceIndex] = VirtualKey.action(
      action: KeyAction.space,
      text: spaceKey.text,
      label: spaceKey.label,
      altLabel: spaceKey.altLabel,
      flex: max(1.0, spaceKey.flex - 1),
    );
    updatedRow.insert(
      spaceIndex,
      VirtualKey.action(action: KeyAction.emoji, flex: 1),
    );

    return [
      ...layout.take(layout.length - 1),
      updatedRow,
    ];
  }

  KeyboardInputType _toInputType(KeyboardType type) {
    switch (type) {
      case KeyboardType.emailAddress:
        return KeyboardInputType.email;
      case KeyboardType.url:
        return KeyboardInputType.url;
      case KeyboardType.number:
        return KeyboardInputType.number;
      case KeyboardType.numberSigned:
        return KeyboardInputType.numberSigned;
      case KeyboardType.numberDecimal:
      case KeyboardType.datetime:
        return KeyboardInputType.numberDecimal;
      case KeyboardType.phone:
        return KeyboardInputType.phone;
      case KeyboardType.text:
      case KeyboardType.multiline:
      case KeyboardType.visiblePassword:
      case KeyboardType.name:
      case KeyboardType.streetAddress:
      case KeyboardType.none:
      case KeyboardType.custom:
        return KeyboardInputType.text;
    }
  }

  KeyboardLayout _getLayoutForStage(KeyboardLayoutSet layoutSet) {
    switch (_layoutStage) {
      case LayoutStage.primary:
        return layoutSet.primary;
      case LayoutStage.secondary:
        return layoutSet.secondary ?? layoutSet.primary;
      case LayoutStage.tertiary:
        return layoutSet.tertiary ?? layoutSet.secondary ?? layoutSet.primary;
      case LayoutStage.emoji:
        return layoutSet.primary;
    }
  }

  bool get _isEmojiPickerVisible =>
      _layoutStage == LayoutStage.emoji && _supportsEmojiLayout;

  void _insertTextIntoTarget(String text) {
    if (widget.standalone) {
      _inputControl?.insertText(text);
      return;
    }

    if (_scope?.activeController != null) {
      _scope?.insertText(text);
      return;
    }

    final controller = _lastScopedController;
    if (controller == null) return;
    if (_wouldExceedLastScopedMaxLength(controller, text)) return;
    controller.insertText(text);
  }

  bool _wouldExceedLastScopedMaxLength(
    VirtualKeypadController controller,
    String text,
  ) {
    final maxLength = _lastScopedMaxLength;
    if (maxLength == null) return false;

    final selection = controller.selection;
    final selectedLength = selection.isValid && !selection.isCollapsed
        ? (selection.end - selection.start).abs()
        : 0;
    final newLength = controller.text.length - selectedLength + text.length;
    return newLength > maxLength;
  }

  void _deleteBackwardFromTarget() {
    if (widget.standalone) {
      _inputControl?.deleteBackward();
      return;
    }

    if (_scope?.activeController != null) {
      _scope?.deleteBackward();
      return;
    }

    _lastScopedController?.deleteBackward();
  }

  String get _targetText {
    if (widget.standalone) {
      return _inputControl?.currentValue.text ?? '';
    }
    return _scope?.activeController?.text ?? _lastScopedController?.text ?? '';
  }

  void _notifyEmojiSelection(String emoji) {
    final virtualKey = VirtualKey.character(text: emoji);
    widget.onKeyPressed?.call(virtualKey);
    widget.onKeyPressedWithText?.call(virtualKey, emoji);
  }

  Locale get _emojiLocale {
    switch (KeyboardLayoutProvider.instance.currentLanguageCode) {
      case 'de':
      case 'en':
      case 'es':
      case 'fr':
      case 'hi':
      case 'ja':
      case 'nl':
      case 'pt':
      case 'ru':
      case 'zh':
        return Locale(KeyboardLayoutProvider.instance.currentLanguageCode);
      default:
        return const Locale('en');
    }
  }

  /// Emoji size used in the picker grid.
  double get _emojiSize => max(26, widget.theme.keyTextSize + 8);

  /// Columns that keep emoji at a roughly constant density.
  ///
  /// A fixed column count makes each grid cell grow with the window, so on a
  /// desktop or full-width web keyboard the emoji end up marooned in padding.
  /// Deriving the count from a target cell size instead keeps the spacing the
  /// same at every width, and only relaxes past the upper clamp, where the
  /// alternative would be an unscannable number of columns.
  int _emojiColumnsForWidth(double width) {
    final targetCell = _emojiSize * 1.55;
    return (width / targetCell).round().clamp(7, 32);
  }

  String get _emojiRestoreLabel {
    final languageCode = KeyboardLayoutProvider.instance.currentLanguageCode;
    return _layoutStageBeforeEmoji == LayoutStage.primary
        ? _lettersLabelForLanguageCode(languageCode)
        : '123';
  }

  bool get _enableEmojiSkinToneSelector => !widget.standalone;

  Widget _buildEmojiPickerKeyboard(double width) {
    final theme = widget.theme;

    return Container(
      width: width,
      height: widget.height,
      color: theme.backgroundColor,
      child: emoji_picker.EmojiPicker(
        customWidget: _isEmojiDpadActive
            ? (config, state, showSearchBar) => EmojiDpadView(
                  key: _emojiDpadKey,
                  categories: state.categoryEmoji,
                  theme: theme,
                  columns: _emojiColumnsForWidth(width),
                  emojiSize: _emojiSize,
                  emojiTextStyle: _effectiveEmojiTextStyle,
                  height: widget.height,
                  onEmojiSelected: (emoji) {
                    _insertTextIntoTarget(emoji);
                    _notifyEmojiSelection(emoji);
                  },
                  onLeaveTop: () => _handleAction(KeyAction.emoji),
                )
            : null,
        onEmojiSelected: (_, emoji) {
          _insertTextIntoTarget(emoji.emoji);
          _notifyEmojiSelection(emoji.emoji);
        },
        config: emoji_picker.Config(
          height: widget.height,
          checkPlatformCompatibility: widget.checkEmojiPlatformCompatibility,
          emojiTextStyle: _effectiveEmojiTextStyle,
          locale: _emojiLocale,
          customSearchIcon: Icon(
            Icons.search,
            size: theme.keyTextSize * 0.85,
            color: theme.keyTextColor,
          ),
          emojiViewConfig: emoji_picker.EmojiViewConfig(
            columns: _emojiColumnsForWidth(width),
            emojiSizeMax: _emojiSize,
            backgroundColor: theme.backgroundColor,
            buttonMode: emoji_picker.ButtonMode.NONE,
            gridPadding: EdgeInsets.symmetric(
              horizontal: theme.horizontalGap,
              vertical: theme.verticalGap / 2,
            ),
            noRecents: Center(
              child: Text(
                'Recent emoji will appear here',
                style: TextStyle(
                  fontSize: theme.keyTextSize * 0.65,
                  color: theme.keyTextColor.withValues(alpha: 0.7),
                ),
              ),
            ),
          ),
          categoryViewConfig: emoji_picker.CategoryViewConfig(
            backgroundColor: theme.backgroundColor,
            dividerColor: Colors.transparent,
            initCategory: emoji_picker.Category.SMILEYS,
            iconColor: theme.keyTextColor.withValues(alpha: 0.55),
            iconColorSelected: theme.keyTextColor,
            indicatorColor: theme.keyTextColor,
            tabBarHeight: 40,
            recentTabBehavior: emoji_picker.RecentTabBehavior.NONE,
          ),
          searchViewConfig: emoji_picker.SearchViewConfig(
            backgroundColor: theme.keyColor,
            buttonIconColor: theme.keyTextColor,
            hintText: 'Search emoji',
            hintTextStyle: TextStyle(
              color: theme.keyTextColor.withValues(alpha: 0.55),
              fontSize: theme.keyTextSize * 0.7,
            ),
            inputTextStyle: TextStyle(
              color: theme.keyTextColor,
              fontSize: theme.keyTextSize * 0.7,
            ),
          ),
          skinToneConfig: emoji_picker.SkinToneConfig(
            enabled: _enableEmojiSkinToneSelector,
            dialogBackgroundColor: theme.keyColor,
            indicatorColor: theme.keyTextColor.withValues(alpha: 0.35),
          ),
          bottomActionBarConfig: emoji_picker.BottomActionBarConfig(
            enabled: true,
            backgroundColor: theme.backgroundColor,
            customBottomActionBar: (config, state, showSearchView) {
              return _EmojiActionBar(
                theme: theme,
                restoreLabel: _emojiRestoreLabel,
                showSearchButton: !widget.standalone,
                onRestore: () => _handleAction(KeyAction.emoji),
                onSearch: showSearchView,
                onSpace: () => _handleAction(KeyAction.space),
                onBackspace: () => _handleAction(KeyAction.backSpace),
                onEnter: () => _handleAction(KeyAction.enter),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildStandardKeyboard(double width, KeyboardLayout layout) {
    final rows = layout.length;
    final maxColumns = layout.map((row) => row.length).reduce(max);

    final totalFlex = layout
        .map((row) => row.fold(0.0, (sum, key) => sum + key.flex))
        .reduce(max);

    final usedHeight = (rows + 1) * widget.theme.verticalGap;
    final keyHeight = (widget.height - usedHeight) / rows;
    final usedWidth = (maxColumns + 1) * widget.theme.horizontalGap;
    final baseKeyWidth = (width - usedWidth) / totalFlex;

    if (widget.enableDpadNavigation) {
      _syncDpadLayout(layout);
    }

    return ExcludeFocus(
      child: Container(
        width: width,
        height: widget.height,
        color: widget.theme.backgroundColor,
        padding: EdgeInsets.symmetric(
          vertical: widget.theme.verticalGap / 2,
          horizontal: widget.theme.horizontalGap / 2,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(layout.length, (rowIndex) {
            final row = layout[rowIndex];
            return Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(row.length, (colIndex) {
                final key = row[colIndex];
                return _KeyWidget(
                  key: ValueKey('${key.text ?? key.action}'),
                  virtualKey: key,
                  isDpadFocused: widget.enableDpadNavigation &&
                      rowIndex == _dpadRow &&
                      colIndex == _dpadCol,
                  type: _effectiveKeyboardType,
                  height: keyHeight,
                  baseWidth: baseKeyWidth,
                  theme: widget.theme,
                  shift: _shift,
                  capsLock: _capsLock,
                  layoutStage: _layoutStage,
                  inputAction: _effectiveInputAction,
                  languageCode:
                      KeyboardLayoutProvider.instance.currentLanguageCode,
                  canOpenLanguagePicker: _canSwitchLanguages,
                  onSpaceLongPress: _showLanguagePicker,
                  onCharacterLongPress: _showAccentPicker,
                  hasAccents: (c) => _accentsFor(c).isNotEmpty,
                  onPressed: _onKeyPressed,
                  keyBuilder: widget.keyBuilder,
                );
              }),
            );
          }),
        ),
      ),
    );
  }

  /// Clamps the highlight into [layout] and records it for the key handler.
  ///
  /// Layouts change under the highlight when the user shifts, opens the symbol
  /// page, or switches language, and rows are not all the same length.
  void _syncDpadLayout(KeyboardLayout layout) {
    _dpadLayout = layout;
    if (layout.isEmpty) return;
    final row = _dpadRow.clamp(0, layout.length - 1);
    final col =
        layout[row].isEmpty ? 0 : _dpadCol.clamp(0, layout[row].length - 1);
    _dpadRow = row;
    _dpadCol = col;
  }

  /// Whether the emoji page is showing its directional-pad view.
  ///
  /// Only when D-pad navigation is on, so the touch picker stays the default
  /// and nothing changes for anyone not driving the keyboard with a remote.
  bool get _isEmojiDpadActive =>
      widget.enableDpadNavigation &&
      identical(_dpadOwner, this) &&
      _dpadVisible &&
      _isEmojiPickerVisible;

  /// Whether the highlight should respond to D-pad events right now.
  bool get _dpadActive =>
      widget.enableDpadNavigation &&
      identical(_dpadOwner, this) &&
      _dpadVisible &&
      !_isEmojiPickerVisible &&
      !_languagePickerVisible &&
      _isDpadCursorInBounds;

  /// Whether the highlight still points at a real key.
  ///
  /// A key event can land between a layout change and the rebuild that clamps
  /// the highlight, so the indices are re-checked before they are used.
  bool get _isDpadCursorInBounds {
    final layout = _dpadLayout;
    if (layout == null || _dpadRow >= layout.length) return false;
    return _dpadCol < layout[_dpadRow].length;
  }

  /// Normalized horizontal centre, from 0 to 1, of the key at [index].
  ///
  /// Rows are laid out by flex and centred, so comparing normalized centres is
  /// what keeps wide keys such as space and shift reachable from the row above.
  double _dpadCenter(KeyRow row, int index) {
    final total = row.fold<double>(0, (sum, key) => sum + key.flex);
    if (total <= 0) return 0;
    var before = 0.0;
    for (var i = 0; i < index; i++) {
      before += row[i].flex;
    }
    return (before + row[index].flex / 2) / total;
  }

  bool _moveDpadHorizontally(int delta) {
    final layout = _dpadLayout!;
    final next = _dpadCol + delta;
    // Out of bounds is left unhandled so the surrounding app can move focus
    // off the keyboard instead of trapping the user inside it.
    if (next < 0 || next >= layout[_dpadRow].length) return false;
    setState(() => _dpadCol = next);
    return true;
  }

  bool _moveDpadVertically(int delta) {
    final layout = _dpadLayout!;
    final targetRow = _dpadRow + delta;
    if (targetRow < 0 || targetRow >= layout.length) return false;

    final target = layout[targetRow];
    if (target.isEmpty) return false;

    final anchor = _dpadCenter(layout[_dpadRow], _dpadCol);
    var best = 0;
    var bestDistance = double.infinity;
    for (var i = 0; i < target.length; i++) {
      final distance = (_dpadCenter(target, i) - anchor).abs();
      if (distance < bestDistance) {
        bestDistance = distance;
        best = i;
      }
    }

    setState(() {
      _dpadRow = targetRow;
      _dpadCol = best;
    });
    return true;
  }

  bool _handleDpadKey(KeyEvent event) {
    if (event is KeyUpEvent) return false;

    // The emoji page has its own cursor, so while it is showing it takes the
    // keys rather than the key highlight behind it.
    if (_isEmojiDpadActive) {
      return _emojiDpadKey.currentState?.handleKey(event) ?? false;
    }

    if (!_dpadActive) return false;

    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowLeft) return _moveDpadHorizontally(-1);
    if (key == LogicalKeyboardKey.arrowRight) return _moveDpadHorizontally(1);
    if (key == LogicalKeyboardKey.arrowUp) return _moveDpadVertically(-1);
    if (key == LogicalKeyboardKey.arrowDown) return _moveDpadVertically(1);

    // Space is deliberately left alone: on a keyboard it is a character, and
    // hijacking it would surprise anyone pairing a Bluetooth keyboard to a TV.
    if (key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.gameButtonA) {
      _onKeyPressed(_dpadLayout![_dpadRow][_dpadCol]);
      return true;
    }

    return false;
  }

  /// Fires the configured haptic and sound for one key press.
  ///
  /// Called for every activation, including D-pad and long-press repeat, so the
  /// confirmation does not depend on how the key was reached. The key's ink
  /// response has `enableFeedback: false` for the same reason: Material would
  /// otherwise play the click on taps only, and play it twice here.
  ///
  /// Both calls are fire and forget. A platform with no vibration motor or no
  /// key click resolves them to a no-op, and waiting on either would delay the
  /// character reaching the field.
  void _playKeyFeedback() {
    switch (widget.feedback) {
      case KeyFeedback.none:
        return;
      case KeyFeedback.haptic:
        unawaited(HapticFeedback.lightImpact());
      case KeyFeedback.sound:
        unawaited(SystemSound.play(SystemSoundType.click));
      case KeyFeedback.both:
        unawaited(HapticFeedback.lightImpact());
        unawaited(SystemSound.play(SystemSoundType.click));
        break;
    }
  }

  void _onKeyPressed(VirtualKey key) {
    _playKeyFeedback();
    if (widget.keyShuffle == KeyShuffle.onEveryKey) {
      _reshuffle();
    }
    String? insertedText;

    if (key.isCharacter) {
      insertedText = key.getInsertText(shift: _shift, capsLock: _capsLock);

      _insertTextIntoTarget(insertedText);

      if (_shift && !_capsLock) {
        setState(() => _shift = false);
      }
    } else if (key.isAction) {
      _handleAction(key.action!);
    }

    widget.onKeyPressed?.call(key);
    widget.onKeyPressedWithText?.call(key, insertedText);
  }

  void _handleAction(KeyAction action) {
    switch (action) {
      case KeyAction.backSpace:
        _deleteBackwardFromTarget();
        break;

      case KeyAction.enter:
        final inputAction = _effectiveInputAction;
        if (inputAction == TextInputAction.newline ||
            _effectiveKeyboardType == KeyboardType.multiline) {
          _insertTextIntoTarget('\n');
        } else {
          _submitOrTraverse(_keyActionForSubmitKey(action));
        }
        break;

      case KeyAction.space:
        _insertTextIntoTarget(' ');
        final text = _targetText;
        if (text.endsWith('. ') || text.endsWith('? ') || text.endsWith('! ')) {
          if (!_shift && !_capsLock) {
            setState(() => _shift = true);
          }
        }
        break;

      case KeyAction.shift:
        setState(() {
          if (!_shift) {
            _shift = true;
          } else if (_shift && !_capsLock) {
            _capsLock = true;
          } else {
            _shift = false;
            _capsLock = false;
          }
        });
        break;

      case KeyAction.symbols:
        setState(() {
          if (_layoutStage == LayoutStage.primary ||
              _layoutStage == LayoutStage.emoji) {
            _setLayoutStage(LayoutStage.secondary);
          } else {
            _setLayoutStage(LayoutStage.primary);
          }
        });
        break;

      case KeyAction.symbolsAlt:
        setState(() {
          if (_layoutStage == LayoutStage.secondary) {
            _setLayoutStage(LayoutStage.tertiary);
          } else {
            _setLayoutStage(LayoutStage.secondary);
          }
        });
        break;

      case KeyAction.emoji:
        if (!_supportsEmojiLayout) break;

        setState(() {
          if (_layoutStage == LayoutStage.emoji) {
            final restoredStage = _layoutStageBeforeEmoji == LayoutStage.emoji
                ? LayoutStage.primary
                : _layoutStageBeforeEmoji;
            _setLayoutStage(restoredStage);
          } else {
            _layoutStageBeforeEmoji = _layoutStage;
            _layoutStage = LayoutStage.emoji;
            _shift = false;
            _capsLock = false;
          }
        });
        break;

      case KeyAction.done:
        _submitOrTraverse(_keyActionForSubmitKey(action));
        break;

      case KeyAction.go:
      case KeyAction.search:
      case KeyAction.send:
      case KeyAction.call:
        _submitOrTraverse(action);
        break;

      case KeyAction.next:
        _submitOrTraverse(KeyAction.next);
        break;

      case KeyAction.previous:
        _submitOrTraverse(KeyAction.previous);
        break;

      case KeyAction.switchLanguage:
        final box = context.findRenderObject() as RenderBox?;
        if (box != null) {
          unawaited(_showLanguagePicker(
              box.localToGlobal(box.size.bottomCenter(Offset.zero))));
        }
        break;
    }
  }

  void _submitOrTraverse(KeyAction action) {
    if (widget.standalone) {
      widget.onStandaloneInputAction?.call(
        action,
        _inputControl?.currentValue.text ?? '',
      );

      final inputAction = _textInputActionForKeyAction(action);
      if (inputAction != null) {
        _inputControl?.performAction(inputAction);
      } else {
        _inputControl?.submit();
      }
      return;
    }

    _scope?.submit(action);

    switch (action) {
      case KeyAction.next:
        FocusScope.of(context).nextFocus();
        break;
      case KeyAction.previous:
        FocusScope.of(context).previousFocus();
        break;
      default:
        break;
    }
  }

  KeyAction _keyActionForSubmitKey(KeyAction action) {
    if (action != KeyAction.done && action != KeyAction.enter) {
      return action;
    }

    switch (_effectiveInputAction) {
      case TextInputAction.go:
        return KeyAction.go;
      case TextInputAction.search:
        return KeyAction.search;
      case TextInputAction.send:
        return KeyAction.send;
      case TextInputAction.next:
        return KeyAction.next;
      case TextInputAction.previous:
        return KeyAction.previous;
      default:
        return KeyAction.done;
    }
  }

  TextInputAction? _textInputActionForKeyAction(KeyAction action) {
    switch (action) {
      case KeyAction.done:
        return TextInputAction.done;
      case KeyAction.go:
        return TextInputAction.go;
      case KeyAction.search:
        return TextInputAction.search;
      case KeyAction.send:
        return TextInputAction.send;
      case KeyAction.next:
        return TextInputAction.next;
      case KeyAction.previous:
        return TextInputAction.previous;
      default:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool shouldShowKeyboard;
    final keepEmojiVisible = _isEmojiPickerVisible;
    if (widget.standalone) {
      shouldShowKeyboard =
          (_standaloneVisible && (_inputControl?.isAttached ?? false)) ||
              keepEmojiVisible ||
              _languagePickerVisible;
    } else {
      final hasController = _scope?.hasActiveController ?? false;
      final allowPhysical = _scope?.allowPhysicalKeyboard ?? false;
      shouldShowKeyboard = (hasController && !allowPhysical) ||
          _languagePickerVisible ||
          keepEmojiVisible;
    }

    _notifyVisibilityChanged(shouldShowKeyboard);

    final isVisible = !widget.hideWhenUnfocused || shouldShowKeyboard;

    // The keyboard still builds its keys while collapsed, so the D-pad handler
    // has to be told when it is off screen. Without this it keeps swallowing
    // arrow keys and types characters the user cannot see.
    _dpadVisible = isVisible;
    _updateDpadOwnership(isVisible);

    if (_effectiveKeyboardType == KeyboardType.none) {
      _dpadVisible = false;
      _updateDpadOwnership(false);
      return const SizedBox.shrink();
    }

    // Update cache when visible
    if (shouldShowKeyboard) {
      _cachedLayout = _currentLayout;
      _wasVisible = true;
    }

    // Use cached layout during close animation, or current layout when visible
    final layout = shouldShowKeyboard
        ? _currentLayout
        : (_wasVisible && _cachedLayout != null
            ? _cachedLayout!
            : _currentLayout);

    // Reset cache after animation would complete
    if (!shouldShowKeyboard && _wasVisible && !widget.hideWhenUnfocused) {
      _wasVisible = false;
      _cachedLayout = null;
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : MediaQuery.of(context).size.width;
        final width = widget.width != null
            ? min(widget.width!, availableWidth)
            : availableWidth;

        final keyboardContent = TextFieldTapRegion(
          child: _isEmojiPickerVisible
              ? _buildEmojiPickerKeyboard(width)
              : _buildStandardKeyboard(width, layout),
        );

        if (!widget.hideWhenUnfocused) {
          return keyboardContent;
        }

        return ClipRect(
          child: AnimatedAlign(
            duration: widget.animationDuration,
            curve: widget.animationCurve,
            alignment: Alignment.topCenter,
            heightFactor: isVisible ? 1.0 : 0.0,
            child: keyboardContent,
          ),
        );
      },
    );
  }

  void _notifyVisibilityChanged(bool visible) {
    if (widget.onVisibilityChanged == null || _reportedVisibility == visible) {
      return;
    }

    _reportedVisibility = visible;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.onVisibilityChanged?.call(visible);
    });
  }
}

class _KeyWidget extends StatefulWidget {
  const _KeyWidget({
    super.key,
    required this.virtualKey,
    required this.type,
    required this.height,
    required this.baseWidth,
    required this.theme,
    required this.shift,
    required this.capsLock,
    required this.layoutStage,
    required this.inputAction,
    required this.languageCode,
    required this.canOpenLanguagePicker,
    required this.onSpaceLongPress,
    required this.onCharacterLongPress,
    required this.hasAccents,
    required this.onPressed,
    required this.keyBuilder,
    this.isDpadFocused = false,
  });

  /// Whether this key is the current D-pad target and should be highlighted.
  final bool isDpadFocused;

  final VirtualKey virtualKey;
  final KeyboardType type;
  final double height;
  final double baseWidth;
  final VirtualKeypadTheme theme;
  final bool shift;
  final bool capsLock;
  final LayoutStage layoutStage;
  final TextInputAction inputAction;
  final String languageCode;
  final bool canOpenLanguagePicker;
  final ValueChanged<Offset> onSpaceLongPress;

  /// Opens the accent popup for a held character key.
  final void Function(String character, Offset at) onCharacterLongPress;

  /// Whether a character has alternates worth showing.
  final bool Function(String character) hasAccents;
  final void Function(VirtualKey) onPressed;
  final VirtualKeypadKeyBuilder? keyBuilder;

  @override
  State<_KeyWidget> createState() => _KeyWidgetState();
}

class _KeyWidgetState extends State<_KeyWidget> {
  Timer? _repeatTimer;
  bool _isLongPressing = false;
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _popupEntry;
  Timer? _popupTimer;

  @override
  void dispose() {
    _repeatTimer?.cancel();
    _removePopup();
    super.dispose();
  }

  void _startRepeat() {
    if (widget.virtualKey.action != KeyAction.backSpace) return;

    _isLongPressing = true;
    _repeatTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (_isLongPressing) {
        widget.onPressed(widget.virtualKey);
      } else {
        _repeatTimer?.cancel();
      }
    });
  }

  void _stopRepeat() {
    _isLongPressing = false;
    _repeatTimer?.cancel();
  }

  void _showKeyPreview() {
    if (!widget.virtualKey.isCharacter) return;

    _removePopup();

    final keyWidth = widget.baseWidth * widget.virtualKey.flex +
        (widget.virtualKey.flex - 1) * widget.theme.horizontalGap;
    final popupWidth = keyWidth + 14;
    final popupHeight = widget.height + 12;
    const gap = 6.0;

    _popupEntry = OverlayEntry(
      builder: (context) => UnconstrainedBox(
        child: CompositedTransformFollower(
          link: _layerLink,
          showWhenUnlinked: false,
          offset: Offset(-(popupWidth - keyWidth) / 2, -popupHeight - gap),
          child: _KeyPreviewBubble(
            text: widget.virtualKey.getDisplayText(
              shift: widget.shift,
              capsLock: widget.capsLock,
            ),
            width: popupWidth,
            height: popupHeight,
            theme: widget.theme,
          ),
        ),
      ),
    );

    Overlay.of(context).insert(_popupEntry!);

    _popupTimer = Timer(const Duration(milliseconds: 120), _removePopup);
  }

  void _removePopup() {
    _popupTimer?.cancel();
    _popupTimer = null;
    _popupEntry?.remove();
    _popupEntry = null;
  }

  void _activateKey() {
    if (widget.virtualKey.action == KeyAction.switchLanguage) {
      _requestSpaceLanguagePicker();
      return;
    }
    _showKeyPreview();
    widget.onPressed(widget.virtualKey);
  }

  void _requestSpaceLanguagePicker([Offset? globalPosition]) {
    if (!widget.canOpenLanguagePicker ||
        (widget.virtualKey.action != KeyAction.space &&
            widget.virtualKey.action != KeyAction.switchLanguage)) {
      return;
    }

    final renderBox = context.findRenderObject() as RenderBox?;
    final resolvedPosition = globalPosition ??
        (renderBox != null
            ? renderBox.localToGlobal(
                Offset(renderBox.size.width / 2, renderBox.size.height / 2),
              )
            : Offset.zero);

    widget.onSpaceLongPress(resolvedPosition);
  }

  void _handleLongPressStart(LongPressStartDetails details) {
    if (widget.virtualKey.action == KeyAction.backSpace) {
      _startRepeat();
      return;
    }

    // A held letter offers its accents, which is where every mobile keyboard
    // keeps them. Space keeps the language picker it already had.
    final key = widget.virtualKey;
    final text = key.text;
    if (key.isCharacter && text != null && widget.hasAccents(text)) {
      widget.onCharacterLongPress(text, details.globalPosition);
      return;
    }

    _requestSpaceLanguagePicker(details.globalPosition);
  }

  void _handleSecondaryTapDown(TapDownDetails details) {
    _requestSpaceLanguagePicker(details.globalPosition);
  }

  @override
  Widget build(BuildContext context) {
    final key = widget.virtualKey;
    final isAction = key.isAction;
    final decoration = isAction
        ? widget.theme.actionKeyDecoration
        : widget.theme.keyDecoration;

    final width = widget.baseWidth * key.flex +
        (key.flex - 1) * widget.theme.horizontalGap;

    return CompositedTransformTarget(
      link: _layerLink,
      child: Semantics(
        button: true,
        enabled: true,
        // Left null rather than false when unfocused: passing false would mark
        // every key isFocusable, which is wrong for a touch-only keyboard.
        focused: widget.isDpadFocused ? true : null,
        label: _semanticLabel(),
        value: _semanticValue(),
        hint: _semanticHint(),
        onTap: _activateKey,
        onLongPress: widget.canOpenLanguagePicker &&
                widget.virtualKey.action == KeyAction.space
            ? _requestSpaceLanguagePicker
            : null,
        child: Container(
          margin: EdgeInsets.symmetric(
            vertical: widget.theme.verticalGap / 2,
            horizontal: widget.theme.horizontalGap / 2,
          ),
          height: widget.height,
          width: width,
          decoration: widget.isDpadFocused
              ? widget.theme.focusedDecoration(_getDecoration(decoration))
              : _getDecoration(decoration),
          clipBehavior: Clip.antiAlias,
          child: Material(
            color: Colors.transparent,
            child: GestureDetector(
              onLongPressStart: _handleLongPressStart,
              onLongPressEnd: (_) => _stopRepeat(),
              onLongPressCancel: _stopRepeat,
              onSecondaryTapDown: _handleSecondaryTapDown,
              child: InkWell(
                // Feedback is driven from the key handler instead, so that a
                // D-pad press is confirmed the same way a tap is.
                enableFeedback: false,
                splashColor: widget.theme.splashColor ?? VkpColors.splashColor,
                onTap: _activateKey,
                child: ExcludeSemantics(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: _buildKeyContent(),
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

  BoxDecoration _getDecoration(BoxDecoration base) {
    final key = widget.virtualKey;

    if (key.action == KeyAction.shift && (widget.shift || widget.capsLock)) {
      return base.copyWith(
        color: widget.capsLock
            ? widget.theme.keyTextColor.withValues(alpha: 0.3)
            : widget.theme.keyColor,
      );
    }

    return base;
  }

  String _semanticLabel() {
    final key = widget.virtualKey;

    if (key.isCharacter) {
      return key.getDisplayText(shift: widget.shift, capsLock: widget.capsLock);
    }

    switch (key.action) {
      case KeyAction.backSpace:
        return 'Backspace';
      case KeyAction.enter:
        return widget.type == KeyboardType.multiline
            ? 'New line'
            : _inputActionLabel(widget.inputAction);
      case KeyAction.shift:
        return 'Shift';
      case KeyAction.space:
        return 'Space';
      case KeyAction.symbols:
        return widget.layoutStage == LayoutStage.primary ||
                widget.layoutStage == LayoutStage.emoji
            ? 'Show symbols'
            : 'Show letters';
      case KeyAction.symbolsAlt:
        return widget.layoutStage == LayoutStage.secondary
            ? 'Show more symbols'
            : 'Show main symbols';
      case KeyAction.emoji:
        return widget.layoutStage == LayoutStage.emoji
            ? 'Show letters'
            : 'Show emoji';
      case KeyAction.done:
        return 'Done';
      case KeyAction.go:
        return 'Go';
      case KeyAction.search:
        return 'Search';
      case KeyAction.send:
        return 'Send';
      case KeyAction.call:
        return 'Call';
      case KeyAction.next:
        return 'Next field';
      case KeyAction.previous:
        return 'Previous field';
      case KeyAction.switchLanguage:
        return 'Switch language';
      default:
        return 'Key';
    }
  }

  String? _semanticValue() {
    final key = widget.virtualKey;

    switch (key.action) {
      case KeyAction.switchLanguage:
        return KeyboardLayoutProvider.instance
            .getLanguage(widget.languageCode)
            ?.name;
      case KeyAction.shift:
        if (widget.capsLock) return 'Caps lock on';
        return widget.shift ? 'On' : 'Off';
      case KeyAction.symbols:
        if (widget.layoutStage == LayoutStage.primary) {
          return 'Letters keyboard';
        }
        if (widget.layoutStage == LayoutStage.emoji) {
          return 'Emoji keyboard';
        }
        return 'Symbols keyboard';
      case KeyAction.symbolsAlt:
        return widget.layoutStage == LayoutStage.tertiary
            ? 'More symbols'
            : 'Main symbols';
      case KeyAction.emoji:
        return widget.layoutStage == LayoutStage.emoji
            ? 'Emoji keyboard'
            : null;
      default:
        return null;
    }
  }

  String? _semanticHint() {
    final key = widget.virtualKey;

    if (key.isCharacter) {
      final text =
          key.getDisplayText(shift: widget.shift, capsLock: widget.capsLock);
      return 'Inserts $text';
    }

    switch (key.action) {
      case KeyAction.backSpace:
        return 'Deletes the previous character. Long press to repeat.';
      case KeyAction.enter:
        return widget.type == KeyboardType.multiline
            ? 'Inserts a new line.'
            : _inputActionHint(widget.inputAction);
      case KeyAction.shift:
        if (widget.capsLock) {
          return 'Turns caps lock off.';
        }
        return widget.shift
            ? 'Turns caps lock on.'
            : 'Turns uppercase on for the next character.';
      case KeyAction.space:
        return widget.canOpenLanguagePicker
            ? 'Inserts a space. Long press to switch language.'
            : 'Inserts a space.';
      case KeyAction.symbols:
        return widget.layoutStage == LayoutStage.primary ||
                widget.layoutStage == LayoutStage.emoji
            ? 'Switches to the symbols keyboard.'
            : 'Switches back to letters.';
      case KeyAction.symbolsAlt:
        return widget.layoutStage == LayoutStage.secondary
            ? 'Shows more symbols.'
            : 'Returns to the main symbols page.';
      case KeyAction.emoji:
        return widget.layoutStage == LayoutStage.emoji
            ? 'Returns to the previous keyboard.'
            : 'Switches to the emoji keyboard.';
      case KeyAction.done:
        return 'Submits the current field.';
      case KeyAction.go:
        return 'Triggers the go action.';
      case KeyAction.search:
        return 'Triggers the search action.';
      case KeyAction.send:
        return 'Triggers the send action.';
      case KeyAction.call:
        return 'Triggers the call action.';
      case KeyAction.next:
        return 'Moves focus to the next field.';
      case KeyAction.previous:
        return 'Moves focus to the previous field.';
      case KeyAction.switchLanguage:
        return 'Switches the keyboard language.';
      default:
        return null;
    }
  }

  String _inputActionLabel(TextInputAction inputAction) {
    switch (inputAction) {
      case TextInputAction.go:
        return 'Go';
      case TextInputAction.search:
        return 'Search';
      case TextInputAction.send:
        return 'Send';
      case TextInputAction.next:
        return 'Next field';
      case TextInputAction.previous:
        return 'Previous field';
      case TextInputAction.newline:
        return 'New line';
      default:
        return 'Done';
    }
  }

  String _inputActionHint(TextInputAction inputAction) {
    switch (inputAction) {
      case TextInputAction.next:
        return 'Moves focus to the next field.';
      case TextInputAction.previous:
        return 'Moves focus to the previous field.';
      case TextInputAction.search:
        return 'Triggers the search action.';
      case TextInputAction.send:
        return 'Triggers the send action.';
      case TextInputAction.go:
        return 'Triggers the go action.';
      default:
        return 'Submits the current field.';
    }
  }

  Widget _buildKeyContent() {
    final key = widget.virtualKey;

    final builder = widget.keyBuilder;
    if (builder != null) {
      // A builder that returns null is declining this key, so fall through to
      // the default content rather than drawing nothing.
      final custom = builder(
        context,
        VirtualKeyContext(
          key: key,
          label: key.isCharacter
              ? key.getDisplayText(
                  shift: widget.shift,
                  capsLock: widget.capsLock,
                )
              : null,
          shift: widget.shift,
          capsLock: widget.capsLock,
          isFocused: widget.isDpadFocused,
          theme: widget.theme,
        ),
      );
      if (custom != null) return custom;
    }

    if (key.isCharacter) {
      return Text(
        key.getDisplayText(shift: widget.shift, capsLock: widget.capsLock),
        style: widget.theme.effectiveKeyTextStyle,
      );
    }

    switch (key.action) {
      case KeyAction.backSpace:
        return Icon(
          Icons.backspace_outlined,
          size: widget.theme.keyTextSize,
          color: widget.theme.keyTextColor,
        );

      case KeyAction.enter:
        if (widget.type == KeyboardType.multiline) {
          return Icon(
            Icons.keyboard_return,
            size: widget.theme.keyTextSize,
            color: widget.theme.keyTextColor,
          );
        }
        return Icon(
          _getActionIcon(),
          size: widget.theme.keyTextSize,
          color: widget.theme.keyTextColor,
        );

      case KeyAction.shift:
        return Icon(
          widget.capsLock
              ? Icons.keyboard_capslock
              : (widget.shift
                  ? Icons.arrow_upward
                  : Icons.arrow_upward_outlined),
          size: widget.theme.keyTextSize,
          color: widget.theme.keyTextColor,
        );

      case KeyAction.space:
        return Text(
          widget.virtualKey.label ?? 'space',
          style: widget.theme.effectiveKeyTextStyle.copyWith(
            fontSize: widget.theme.keyTextSize * 0.7,
            color: widget.theme.keyTextColor,
          ),
        );

      case KeyAction.symbols:
        return Text(
          widget.layoutStage == LayoutStage.primary ||
                  widget.layoutStage == LayoutStage.emoji
              ? (widget.virtualKey.label ?? '123')
              : (widget.virtualKey.altLabel ?? _getLettersLabel()),
          style: widget.theme.effectiveKeyTextStyle.copyWith(
            fontSize: widget.theme.keyTextSize * 0.8,
            color: widget.theme.keyTextColor,
          ),
        );

      case KeyAction.emoji:
        if (widget.layoutStage == LayoutStage.emoji) {
          return Text(
            widget.virtualKey.altLabel ?? _getLettersLabel(),
            style: widget.theme.effectiveKeyTextStyle.copyWith(
              fontSize: widget.theme.keyTextSize * 0.8,
              color: widget.theme.keyTextColor,
            ),
          );
        }
        return Icon(
          Icons.emoji_emotions_outlined,
          size: widget.theme.keyTextSize,
          color: widget.theme.keyTextColor,
        );

      case KeyAction.symbolsAlt:
        return Text(
          widget.layoutStage == LayoutStage.secondary
              ? (widget.virtualKey.label ?? '#+=')
              : (widget.virtualKey.altLabel ?? '123'),
          style: widget.theme.effectiveKeyTextStyle.copyWith(
            fontSize: widget.theme.keyTextSize * 0.8,
            color: widget.theme.keyTextColor,
          ),
        );

      case KeyAction.done:
        return Icon(
          _getActionIcon(),
          size: widget.theme.keyTextSize,
          color: widget.theme.keyTextColor,
        );

      case KeyAction.go:
        return Icon(
          Icons.arrow_forward,
          size: widget.theme.keyTextSize,
          color: widget.theme.keyTextColor,
        );

      case KeyAction.search:
        return Icon(
          Icons.search,
          size: widget.theme.keyTextSize,
          color: widget.theme.keyTextColor,
        );

      case KeyAction.send:
        return Icon(
          Icons.send,
          size: widget.theme.keyTextSize,
          color: widget.theme.keyTextColor,
        );

      case KeyAction.call:
        return Icon(
          Icons.call,
          size: widget.theme.keyTextSize,
          color: widget.theme.keyTextColor,
        );

      case KeyAction.next:
        return Icon(
          Icons.keyboard_tab,
          size: widget.theme.keyTextSize,
          color: widget.theme.keyTextColor,
        );

      case KeyAction.previous:
        return Transform.flip(
          flipX: true,
          child: Icon(
            Icons.keyboard_tab,
            size: widget.theme.keyTextSize,
            color: widget.theme.keyTextColor,
          ),
        );

      case KeyAction.switchLanguage:
        return Tooltip(
          message: 'Switch keyboard layout',
          child: Icon(Icons.language_outlined,
              size: widget.theme.keyTextSize + 4,
              color: widget.theme.keyTextColor),
        );

      default:
        return const SizedBox.shrink();
    }
  }

  IconData _getActionIcon() {
    switch (widget.inputAction) {
      case TextInputAction.go:
        return Icons.arrow_forward;
      case TextInputAction.search:
        return Icons.search;
      case TextInputAction.send:
        return Icons.send;
      case TextInputAction.next:
        return Icons.keyboard_tab;
      case TextInputAction.previous:
        return Icons.keyboard_tab;
      default:
        return Icons.check;
    }
  }

  String _getLettersLabel() {
    return _lettersLabelForLanguageCode(widget.languageCode);
  }
}

class _EmojiActionBar extends StatelessWidget {
  const _EmojiActionBar({
    required this.theme,
    required this.restoreLabel,
    required this.showSearchButton,
    required this.onRestore,
    required this.onSearch,
    required this.onSpace,
    required this.onBackspace,
    required this.onEnter,
  });

  final VirtualKeypadTheme theme;
  final String restoreLabel;
  final bool showSearchButton;
  final VoidCallback onRestore;
  final VoidCallback onSearch;
  final VoidCallback onSpace;
  final VoidCallback onBackspace;
  final VoidCallback onEnter;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: theme.backgroundColor,
      padding: EdgeInsets.fromLTRB(
        theme.horizontalGap,
        theme.verticalGap / 2,
        theme.horizontalGap,
        theme.verticalGap,
      ),
      child: Row(
        children: [
          _EmojiActionButton(
            theme: theme,
            label: restoreLabel,
            semanticLabel: 'Show letters',
            onTap: onRestore,
            flex: 1.2,
          ),
          if (showSearchButton)
            _EmojiActionButton(
              theme: theme,
              icon: Icons.search,
              semanticLabel: 'Search emoji',
              onTap: onSearch,
            ),
          _EmojiActionButton(
            theme: theme,
            label: 'space',
            semanticLabel: 'Space',
            onTap: onSpace,
            flex: 2.4,
          ),
          _EmojiActionButton(
            theme: theme,
            icon: Icons.backspace_outlined,
            semanticLabel: 'Backspace',
            onTap: onBackspace,
          ),
          _EmojiActionButton(
            theme: theme,
            icon: Icons.check,
            semanticLabel: 'Done',
            onTap: onEnter,
            flex: 1.2,
          ),
        ],
      ),
    );
  }
}

class _EmojiActionButton extends StatelessWidget {
  const _EmojiActionButton({
    required this.theme,
    required this.semanticLabel,
    required this.onTap,
    this.label,
    this.icon,
    this.flex = 1,
  });

  final VirtualKeypadTheme theme;
  final String semanticLabel;
  final VoidCallback onTap;
  final String? label;
  final IconData? icon;
  final double flex;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: (flex * 10).round(),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: theme.horizontalGap / 2),
        child: Semantics(
          button: true,
          enabled: true,
          label: semanticLabel,
          child: Container(
            height: 40,
            decoration: theme.actionKeyDecoration,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                splashColor: theme.splashColor ?? VkpColors.splashColor,
                borderRadius: BorderRadius.circular(theme.keyBorderRadius),
                onTap: onTap,
                child: Center(
                  child: label != null
                      ? Text(
                          label!,
                          style: TextStyle(
                            fontSize: theme.keyTextSize * 0.68,
                            color: theme.keyTextColor,
                          ),
                        )
                      : Icon(
                          icon,
                          size: theme.keyTextSize * 0.9,
                          color: theme.keyTextColor,
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

class _KeyPreviewBubble extends StatelessWidget {
  const _KeyPreviewBubble({
    required this.text,
    required this.width,
    required this.height,
    required this.theme,
  });

  final String text;
  final double width;
  final double height;
  final VirtualKeypadTheme theme;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: theme.keyColor,
          borderRadius: BorderRadius.circular(theme.keyBorderRadius + 2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        alignment: Alignment.center,
        child: Text(
          text,
          style: theme.effectiveKeyTextStyle.copyWith(
            fontSize: theme.keyTextSize * 1.4,
            fontWeight: FontWeight.w500,
            color: theme.keyTextColor,
            decoration: TextDecoration.none,
          ),
        ),
      ),
    );
  }
}
