import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:virtual_keypad/virtual_keypad.dart';

import '../../providers/on_screen_keyboard_provider.dart';
import '../../theme/app_theme.dart';
import 'keyboard_accent_picker.dart';
import 'keyboard_language_picker.dart';
import 'keyboard_presentation_scope.dart';
import 'on_screen_input_control.dart';

const _maxKeyboardWidth = 900.0;
const _maxKeyboardHeightFraction = 0.37;
const _maxCharacterKeyAspectRatio = 2.0;
const _keyboardRowGap = 6.0;
const _keyboardColumnGap = 4.0;
const _keyboardToolbarHeight = 48.0;
const _keyboardToolbarWidth = 52.0;

/// Mounted above the app Navigator so fields in routes, dialogs and sheets all
/// use the same keyboard. Only the panel covers content; a keyboard inset lets
/// editors and sheets keep their active fields above it.
class OnScreenKeyboardHost extends ConsumerStatefulWidget {
  const OnScreenKeyboardHost({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<OnScreenKeyboardHost> createState() =>
      _OnScreenKeyboardHostState();
}

class _OnScreenKeyboardHostState extends ConsumerState<OnScreenKeyboardHost>
    with SingleTickerProviderStateMixin {
  late final OnScreenInputControl _input;
  final _presentation = KeyboardPresentationController();
  late final AnimationController _motion;
  late final CurvedAnimation _reveal;
  late final Animation<Offset> _slide;
  late bool _enabled;
  bool _refreshPending = false;
  bool _requested = false;
  bool _panelMounted = false;
  int _presentationRevision = 0;
  final _keyboardNavigatorKey = GlobalKey<NavigatorState>();
  Completer<String?>? _languageChoice;
  List<KeyboardLanguage> _languageOptions = const [];
  String _selectedLanguage = 'en';
  Offset _languageOrigin = Offset.zero;

  Future<String?> _showLanguages(
    BuildContext context,
    List<String> codes,
    String selected,
    Offset origin,
  ) {
    if (_languageChoice != null) return _languageChoice!.future;
    final choice = Completer<String?>();
    setState(() {
      _languageChoice = choice;
      _languageOptions = [
        for (final code in codes)
          ?KeyboardLayoutProvider.instance.getLanguage(code),
      ];
      _selectedLanguage = selected;
      _languageOrigin = origin;
    });
    return choice.future;
  }

  void _closeLanguages([String? selected]) {
    final choice = _languageChoice;
    if (choice == null) return;
    setState(() => _languageChoice = null);
    choice.complete(selected);
  }

  @override
  void initState() {
    super.initState();
    _motion = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
      reverseDuration: const Duration(milliseconds: 140),
    );
    _reveal = CurvedAnimation(
      parent: _motion,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    _slide = Tween(
      begin: const Offset(0, 1),
      end: Offset.zero,
    ).animate(_reveal);
    initializeKeyboardLayouts();
    _input = OnScreenInputControl(onChanged: _refresh);
    _enabled = ref.read(onScreenKeyboardProvider);
    if (_enabled) TextInput.setInputControl(_input);
    ref.listenManual(onScreenKeyboardProvider, (_, enabled) {
      // Installing a control does not attach an already-focused input client.
      // Reconnect it so both our adapter and the platform get the new config.
      final focus = FocusManager.instance.primaryFocus;
      focus?.unfocus();
      if (enabled) {
        TextInput.setInputControl(_input);
      } else {
        TextInput.restorePlatformInputControl();
        _input.hide();
      }
      setState(() => _enabled = enabled);
      _refresh();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && focus?.context?.mounted == true) focus!.requestFocus();
      });
    });
    FocusManager.instance.addEarlyKeyEventHandler(_onKeyEvent);
  }

  KeyEventResult _onKeyEvent(KeyEvent event) {
    if (_enabled &&
        _input.visible &&
        event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape) {
      if (_languageChoice != null) {
        _closeLanguages();
        return KeyEventResult.handled;
      }
      final navigator = _keyboardNavigatorKey.currentState;
      if (navigator != null && navigator.canPop()) {
        navigator.pop();
      } else {
        _input.dismiss();
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _refresh() {
    if (!mounted || _refreshPending) return;
    _refreshPending = true;
    // Text input can attach during layout or rebuild. Defer the host update.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshPending = false;
      if (!mounted) return;
      setState(() {});
      final visible = _enabled && _input.visible;
      if (visible != _requested) unawaited(_setVisible(visible));
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _motion.isCompleted) _revealFocusedField();
      });
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  Future<void> _setVisible(bool visible) async {
    _requested = visible;
    if (!visible) _closeLanguages();
    final revision = ++_presentationRevision;
    bool current() => mounted && revision == _presentationRevision;
    try {
      if (visible) {
        // The shell returns when its bar is gone. No scrim or modal route is
        // added: catalogue filters and their results remain interactive.
        await _presentation.setActive(true);
        if (!current()) return;
        setState(() => _panelMounted = true);
        await WidgetsBinding.instance.endOfFrame;
        if (!mounted || revision != _presentationRevision) return;
        if (MediaQuery.disableAnimationsOf(context)) {
          _motion.value = 1;
        } else {
          await _motion.forward().orCancel;
        }
        if (current()) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _revealFocusedField();
          });
        }
      } else {
        if (MediaQuery.disableAnimationsOf(context)) {
          _motion.value = 0;
        } else {
          await _motion.reverse().orCancel;
        }
        if (!current()) return;
        setState(() => _panelMounted = false);
        await _presentation.setActive(false);
      }
    } on TickerCanceled {
      // A newer focus change or disposal superseded this transition.
    }
  }

  void _revealFocusedField() {
    if (!_enabled || !_input.visible) return;
    final focused = FocusManager.instance.primaryFocus?.context;
    if (focused != null && focused.mounted) {
      Scrollable.ensureVisible(
        focused,
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
      );
    }
  }

  @override
  void dispose() {
    _languageChoice?.complete(null);
    FocusManager.instance.removeEarlyKeyEventHandler(_onKeyEvent);
    if (_enabled) TextInput.restorePlatformInputControl();
    _reveal.dispose();
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = math
            .min(260.0, constraints.maxHeight * _maxKeyboardHeightFraction)
            .floorToDouble();
        final toolbarAbove = constraints.maxHeight > constraints.maxWidth;
        final keyAreaHeight = math.max(
          0.0,
          height -
              media.padding.bottom -
              (toolbarAbove ? _keyboardToolbarHeight : 0),
        );
        // Allow up to 2:1 letter keys in the standard four-row, ten-column
        // layout. Include outer gaps and the toolbar in the panel width, so
        // the surface ends at the keys instead of leaving empty side bands.
        final letterHeight = math.max(
          0.0,
          (keyAreaHeight - 5 * _keyboardRowGap) / 4,
        );
        final preferredWidth =
            10 * letterHeight * _maxCharacterKeyAspectRatio +
            11 * _keyboardColumnGap +
            (toolbarAbove ? 0 : _keyboardToolbarWidth) +
            media.padding.horizontal;
        final width = math.min(
          constraints.maxWidth,
          math.min(_maxKeyboardWidth, preferredWidth),
        );
        return Stack(
          fit: StackFit.expand,
          children: [
            AnimatedBuilder(
              animation: _reveal,
              builder: (context, child) {
                final inset = _panelMounted ? height * _reveal.value : 0.0;
                return MediaQuery(
                  data: media.copyWith(
                    padding: media.padding.copyWith(
                      bottom: math.max(0, media.padding.bottom - inset),
                    ),
                    viewInsets: media.viewInsets.copyWith(
                      bottom: math.max(media.viewInsets.bottom, inset),
                    ),
                  ),
                  child: child!,
                );
              },
              child: KeyboardPresentationScope(
                controller: _presentation,
                child: widget.child,
              ),
            ),
            if (_panelMounted)
              Positioned(
                bottom: 0,
                left: (constraints.maxWidth - width) / 2,
                width: width,
                height: height,
                child: SlideTransition(
                  position: _slide,
                  child: RepaintBoundary(
                    child: IgnorePointer(
                      ignoring: !_requested,
                      child: SizedBox(
                        key: const ValueKey('on-screen-keyboard'),
                        child: TextFieldTapRegion(
                          child: ExcludeFocus(
                            // Key previews and accents keep editing focus.
                            child: DefaultTextStyle(
                              style: KalinkaTextStyles.trayRowLabel,
                              child: HeroControllerScope.none(
                                child: Navigator(
                                  key: _keyboardNavigatorKey,
                                  requestFocus: false,
                                  // First-row key previews may rise above the
                                  // panel; only the panel itself reserves space.
                                  clipBehavior: Clip.none,
                                  pages: [
                                    MaterialPage<void>(
                                      child: _KeyboardPanel(
                                        input: _input,
                                        languagePicker: _showLanguages,
                                        toolbarAbove: toolbarAbove,
                                        height: math.max(
                                          0,
                                          height - media.padding.bottom,
                                        ),
                                      ),
                                    ),
                                  ],
                                  onDidRemovePage: (_) {},
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
            if (_languageChoice != null)
              HeroControllerScope.none(
                child: Navigator(
                  requestFocus: false,
                  pages: [
                    MaterialPage<void>(
                      child: KeyboardLanguagePicker(
                        languages: _languageOptions,
                        selectedCode: _selectedLanguage,
                        origin: _languageOrigin,
                        onSelected: _closeLanguages,
                        onCancel: _closeLanguages,
                      ),
                    ),
                  ],
                  onDidRemovePage: (_) {},
                ),
              ),
          ],
        );
      },
    );
  }
}

class _KeyboardPanel extends StatelessWidget {
  const _KeyboardPanel({
    required this.input,
    required this.height,
    required this.languagePicker,
    required this.toolbarAbove,
  });

  final OnScreenInputControl input;
  final double height;
  final VirtualKeypadLanguagePicker languagePicker;
  final bool toolbarAbove;

  KeyboardType get _type {
    final type = input.configuration.inputType;
    if (type.index == TextInputType.number.index) return KeyboardType.custom;
    if (type == TextInputType.emailAddress) return KeyboardType.emailAddress;
    if (type == TextInputType.url) return KeyboardType.url;
    if (type == TextInputType.phone) return KeyboardType.phone;
    if (input.action == TextInputAction.newline) return KeyboardType.multiline;
    return KeyboardType.text;
  }

  KeyboardLayout get _numbers => [
    for (final row in ['123', '456', '789'])
      [for (final digit in row.split('')) VirtualKey.character(text: digit)],
    [
      if (input.configuration.inputType.signed == true)
        VirtualKey.character(text: '-'),
      VirtualKey.character(text: '0'),
      if (input.configuration.inputType.decimal == true)
        VirtualKey.character(text: '.'),
      VirtualKey.action(action: KeyAction.backSpace),
    ],
  ];

  String get _actionLabel => switch (input.action) {
    TextInputAction.search => 'Search',
    TextInputAction.next => 'Next',
    TextInputAction.previous => 'Previous',
    TextInputAction.go => 'Go',
    TextInputAction.send => 'Send',
    _ => 'Done',
  };

  IconData get _actionIcon => switch (input.action) {
    TextInputAction.search => Icons.search_rounded,
    TextInputAction.next => Icons.keyboard_tab_rounded,
    TextInputAction.previous => Icons.arrow_back_rounded,
    TextInputAction.go => Icons.arrow_forward_rounded,
    TextInputAction.send => Icons.send_rounded,
    _ => Icons.check_rounded,
  };

  @override
  Widget build(BuildContext context) => Material(
    color: KalinkaColors.surfaceDialog,
    borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
    clipBehavior: Clip.antiAlias,
    child: SafeArea(
      top: false,
      // Keep the keypad in the same element slot when changing orientation,
      // preserving Shift, symbol pages and any open picker during resizing.
      child: Flex(
        direction: toolbarAbove ? Axis.vertical : Axis.horizontal,
        verticalDirection: VerticalDirection.up,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: VirtualKeypad(
              type: _type,
              customLayout: _type == KeyboardType.custom ? _numbers : null,
              inputAction: input.action,
              availableLanguages: KeyboardLayoutProvider.instance.languageCodes
                  .toList(growable: false),
              height: math.max(
                0,
                height - (toolbarAbove ? _keyboardToolbarHeight : 0),
              ),
              accentPicker: showKeyboardAccentPicker,
              enableLanguageKey: true,
              languagePicker: languagePicker,
              // Render keys only. The host owns TextInputControl and routes
              // accepted edits, so standalone/scope mode must stay off.
              onKeyPressedWithText: input.onKey,
              feedback: KeyFeedback.none,
              animationDuration: Duration.zero,
              theme: VirtualKeypadTheme(
                backgroundColor: KalinkaColors.surfaceDialog,
                keyColor: KalinkaColors.surfaceElevated,
                actionKeyColor: KalinkaColors.surfaceOverlay,
                keyTextColor: KalinkaColors.textPrimary,
                keyTextStyle: KalinkaTextStyles.trayRowLabel.copyWith(
                  fontSize: 20,
                ),
                keyTextSize: 20,
                keyBorderRadius: 8,
                keyShadow: false,
                horizontalGap: _keyboardColumnGap,
                verticalGap: _keyboardRowGap,
                splashColor: KalinkaColors.borderDefault,
              ),
            ),
          ),
          SizedBox(
            width: toolbarAbove ? null : _keyboardToolbarWidth,
            height: toolbarAbove ? _keyboardToolbarHeight : null,
            child: Flex(
              direction: toolbarAbove ? Axis.horizontal : Axis.vertical,
              children: [
                IconButton(
                  key: const ValueKey('hide-on-screen-keyboard'),
                  tooltip: 'Hide keyboard',
                  onPressed: input.dismiss,
                  icon: const Icon(Icons.keyboard_hide_outlined),
                ),
                const Spacer(),
                IconButton(
                  key: const ValueKey('keyboard-submit'),
                  tooltip: _actionLabel,
                  onPressed: input.submit,
                  icon: Icon(_actionIcon),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
