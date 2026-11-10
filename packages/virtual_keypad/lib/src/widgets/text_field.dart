import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../controller.dart';
import '../emoji_font.dart';
import '../enums.dart';
import '../scope.dart';

/// A text field that integrates with [VirtualKeypad] through [VirtualKeypadScope].
///
/// By default, prevents the system keyboard from appearing while maintaining
/// full cursor and selection functionality. Use [allowPhysicalKeyboard] to
/// enable both physical and virtual keyboard input.
///
/// ```dart
/// VirtualKeypadScope(
///   child: Column(
///     children: [
///       VirtualKeypadTextField(
///         controller: controller,
///         decoration: InputDecoration(labelText: 'Password'),
///         obscureText: true,
///       ),
///       VirtualKeypad(),
///     ],
///   ),
/// )
/// ```
class VirtualKeypadTextField extends StatefulWidget {
  /// Creates a text field optimized for virtual keyboard input.
  const VirtualKeypadTextField({
    super.key,
    required this.controller,
    this.decoration,
    this.style,
    this.maxLength,
    this.obscureText = false,
    this.obscuringCharacter = '•',
    this.enabled = true,
    this.readOnly = false,
    this.autofocus = false,
    this.textAlign = TextAlign.start,
    this.textAlignVertical,
    this.maxLines = 1,
    this.minLines,
    this.onChanged,
    this.onTap,
    this.onSubmitted,
    this.onInputAction,
    this.allowPhysicalKeyboard = false,
    this.keyboardType = KeyboardType.text,
    this.textInputAction,
  });

  /// Controller for the text field's content and selection.
  final VirtualKeypadController controller;

  /// Decoration for the text field (border, label, hint, etc.).
  final InputDecoration? decoration;

  /// Text style for the input text.
  final TextStyle? style;

  /// Maximum number of characters allowed.
  final int? maxLength;

  /// Whether to hide the text (for passwords).
  final bool obscureText;

  /// Character used when [obscureText] is true.
  final String obscuringCharacter;

  /// Whether the text field accepts input.
  final bool enabled;

  /// Whether the text field is read-only.
  ///
  /// When true, the field displays text but doesn't accept any input.
  /// The cursor is also hidden.
  final bool readOnly;

  /// Whether to automatically focus when the widget is created.
  final bool autofocus;

  /// How to align the text horizontally.
  final TextAlign textAlign;

  /// How to align the text vertically within the field.
  final TextAlignVertical? textAlignVertical;

  /// Maximum number of lines for the text field.
  ///
  /// Set to null for unlimited lines.
  final int? maxLines;

  /// Minimum number of lines for the text field.
  final int? minLines;

  /// Called when the text content changes.
  final ValueChanged<String>? onChanged;

  /// Called when the text field is tapped.
  final VoidCallback? onTap;

  /// Called when the user submits (e.g., presses enter/done).
  final ValueChanged<String>? onSubmitted;

  /// Called when a submit-like keyboard action is triggered.
  ///
  /// This reports which [KeyAction] was pressed, such as search, send,
  /// call, next, or done, along with the current field text.
  final void Function(KeyAction action, String text)? onInputAction;

  /// Whether to allow physical keyboard input alongside virtual keyboard.
  ///
  /// When false (default), the system keyboard is suppressed.
  /// When true, both keyboards work together.
  final bool allowPhysicalKeyboard;

  /// The type of virtual keyboard to display.
  ///
  /// Determines which layout the [VirtualKeypad] shows when this field is focused.
  /// For example, [KeyboardType.emailAddress] shows @ on the primary layout.
  final KeyboardType keyboardType;

  /// The action button to show on the keyboard (done, next, search, etc.).
  ///
  /// If null, defaults based on [maxLines]: enter for multiline, done for single-line.
  final TextInputAction? textInputAction;

  @override
  State<VirtualKeypadTextField> createState() => _VirtualKeypadTextFieldState();
}

class _VirtualKeypadTextFieldState extends State<VirtualKeypadTextField> {
  late FocusNode _focusNode;
  final GlobalKey _textFieldKey = GlobalKey();
  bool _isActiveInScope = false;
  VirtualKeypadScopeState? _scope;
  String _previousText = '';

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
    _focusNode.addListener(_onFocusChanged);
    widget.controller.addListener(_onControllerChanged);
    // Repaint when a runtime color emoji font arrives, so text already on
    // screen switches to color along with the emoji grid.
    VirtualKeypadColorEmoji.isLoaded.addListener(_onEmojiFontChanged);
    _previousText = widget.controller.text;
  }

  void _onEmojiFontChanged() {
    if (mounted) setState(() {});
  }

  TextInputType _toTextInputType(KeyboardType type) {
    switch (type) {
      case KeyboardType.text:
        return TextInputType.text;
      case KeyboardType.multiline:
        return TextInputType.multiline;
      case KeyboardType.number:
        return TextInputType.number;
      case KeyboardType.numberSigned:
        return const TextInputType.numberWithOptions(signed: true);
      case KeyboardType.numberDecimal:
        return const TextInputType.numberWithOptions(decimal: true);
      case KeyboardType.phone:
        return TextInputType.phone;
      case KeyboardType.datetime:
        return TextInputType.datetime;
      case KeyboardType.emailAddress:
        return TextInputType.emailAddress;
      case KeyboardType.url:
        return TextInputType.url;
      case KeyboardType.visiblePassword:
        return TextInputType.visiblePassword;
      case KeyboardType.name:
        return TextInputType.name;
      case KeyboardType.streetAddress:
        return TextInputType.streetAddress;
      case KeyboardType.none:
      case KeyboardType.custom:
        return TextInputType.none;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final newScope = VirtualKeypadScope.of(context);
    if (_scope != newScope) {
      _scope?.removeActiveControllerListener(_onScopeChanged);
      _scope = newScope;
      _scope?.addActiveControllerListener(_onScopeChanged);
    }
    _updateActiveState();
  }

  @override
  void didUpdateWidget(VirtualKeypadTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != oldWidget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      widget.controller.addListener(_onControllerChanged);
    }
  }

  @override
  void dispose() {
    _clearScopeCallbacks();
    _scope?.removeActiveControllerListener(_onScopeChanged);
    _focusNode.removeListener(_onFocusChanged);
    _focusNode.dispose();
    widget.controller.removeListener(_onControllerChanged);
    VirtualKeypadColorEmoji.isLoaded.removeListener(_onEmojiFontChanged);
    super.dispose();
  }

  void _onScopeChanged() {
    _updateActiveState();
  }

  void _updateActiveState() {
    final isActive = _scope?.activeController == widget.controller;

    if (isActive != _isActiveInScope) {
      _isActiveInScope = isActive;

      if (isActive && !_focusNode.hasFocus) {
        _focusNode.requestFocus();
      }

      if (mounted) setState(() {});
    }
  }

  void _onFocusChanged() {
    if (_focusNode.hasFocus) {
      _registerWithScope();
    } else {
      _clearScopeCallbacks();
      _scope?.clearActiveController();
      _isActiveInScope = false;
    }
    setState(() {});
  }

  void _onControllerChanged() {
    final currentText = widget.controller.text;
    final textChanged = currentText != _previousText;
    _previousText = currentText;

    widget.onChanged?.call(currentText);

    if (textChanged) {
      _ensureCursorVisible();
    }
  }

  void _ensureCursorVisible() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      final selection = widget.controller.selection;
      if (!selection.isValid || !selection.isCollapsed) return;

      final textFieldContext = _textFieldKey.currentContext;
      if (textFieldContext == null) return;

      void visitChildren(Element element) {
        if (element.widget is EditableText) {
          final editableTextState =
              (element as StatefulElement).state as EditableTextState;
          editableTextState.bringIntoView(
            TextPosition(offset: selection.baseOffset),
          );
          return;
        }
        element.visitChildren(visitChildren);
      }

      (textFieldContext as Element).visitChildren(visitChildren);
    });
  }

  void _registerWithScope() {
    if (_scope != null && widget.enabled && !widget.readOnly) {
      final inputAction = widget.textInputAction ??
          (widget.maxLines != 1
              ? TextInputAction.newline
              : TextInputAction.done);

      _scope!.setActiveController(
        widget.controller,
        maxLength: widget.maxLength,
        keyboardType: widget.keyboardType,
        inputAction: inputAction,
        allowPhysicalKeyboard: widget.allowPhysicalKeyboard,
      );
      _scope!.setDeleteSelectionCallback(_deleteSelection);
      _scope!.setGetSelectionCallback(_getSelection);
      _scope!.setClearSelectionCallback(_clearSelection);
      _scope!.setOnSubmitCallback(_handleSubmit);

      _isActiveInScope = true;
    }
  }

  void _handleSubmit(KeyAction action) {
    widget.onInputAction?.call(action, widget.controller.text);
    widget.onSubmitted?.call(widget.controller.text);
  }

  void _clearScopeCallbacks() {
    _scope?.setDeleteSelectionCallback(null);
    _scope?.setGetSelectionCallback(null);
    _scope?.setClearSelectionCallback(null);
    _scope?.setOnSubmitCallback(null);
  }

  void unfocus() {
    _isActiveInScope = false;
    _focusNode.unfocus();
    _clearScopeCallbacks();
    setState(() {});
  }

  Future<void> _handlePaste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null && data!.text!.isNotEmpty) {
      final selection = widget.controller.selection;
      if (selection.isValid) {
        widget.controller.replaceRange(
          selection.start,
          selection.end,
          data.text!,
        );
      }
    }
  }

  Widget _buildContextMenu(
    BuildContext context,
    EditableTextState editableTextState,
  ) {
    final List<ContextMenuButtonItem> buttonItems = [];

    if (!editableTextState.textEditingValue.selection.isCollapsed) {
      buttonItems.add(
        ContextMenuButtonItem(
          label: 'Cut',
          onPressed: () {
            final selection = widget.controller.selection;
            if (selection.isValid && !selection.isCollapsed) {
              final selectedText = widget.controller.text.substring(
                selection.start,
                selection.end,
              );
              Clipboard.setData(ClipboardData(text: selectedText));
              widget.controller.deleteRange(selection.start, selection.end);
            }
            editableTextState.hideToolbar();
          },
        ),
      );
    }

    if (!editableTextState.textEditingValue.selection.isCollapsed) {
      buttonItems.add(
        ContextMenuButtonItem(
          label: 'Copy',
          onPressed: () {
            editableTextState.copySelection(SelectionChangedCause.toolbar);
          },
        ),
      );
    }

    buttonItems.add(
      ContextMenuButtonItem(
        label: 'Paste',
        onPressed: () {
          _handlePaste();
          editableTextState.hideToolbar();
        },
      ),
    );

    buttonItems.add(
      ContextMenuButtonItem(
        label: 'Select All',
        onPressed: () {
          editableTextState.selectAll(SelectionChangedCause.toolbar);
        },
      ),
    );

    return AdaptiveTextSelectionToolbar.buttonItems(
      anchors: editableTextState.contextMenuAnchors,
      buttonItems: buttonItems,
    );
  }

  bool _deleteSelection() {
    final selection = widget.controller.selection;
    if (selection.isValid && !selection.isCollapsed) {
      widget.controller.deleteRange(selection.start, selection.end);
      return true;
    }
    return false;
  }

  (int, int)? _getSelection() {
    final selection = widget.controller.selection;
    if (selection.isValid && !selection.isCollapsed) {
      return (selection.start, selection.end);
    }
    return null;
  }

  void _clearSelection() {
    final pos = widget.controller.selection.start;
    widget.controller.selection = TextSelection.collapsed(offset: pos);
  }

  void _handleTap() {
    if (!widget.enabled) return;
    _registerWithScope();
    _focusNode.requestFocus();
    widget.onTap?.call();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      key: _textFieldKey,
      controller: widget.controller,
      focusNode: _focusNode,
      decoration: widget.decoration,
      // On web the bundled emoji font is appended as a fallback so emoji
      // inserted from the keyboard render without a network connection.
      // Off the web this returns widget.style untouched.
      style: withBundledEmojiFallback(widget.style),
      obscureText: widget.obscureText,
      obscuringCharacter: widget.obscuringCharacter,
      enabled: widget.enabled,
      readOnly: widget.readOnly || !widget.allowPhysicalKeyboard,
      showCursor: !widget.readOnly,
      autofocus: widget.autofocus,
      textAlign: widget.textAlign,
      textAlignVertical: widget.textAlignVertical,
      maxLines: widget.maxLines,
      minLines: widget.minLines,
      maxLength: widget.maxLength,
      maxLengthEnforcement: widget.maxLength != null
          ? MaxLengthEnforcement.enforced
          : MaxLengthEnforcement.none,
      keyboardType: widget.allowPhysicalKeyboard
          ? _toTextInputType(widget.keyboardType)
          : TextInputType.none,
      enableInteractiveSelection: true,
      onTap: _handleTap,
      onSubmitted: widget.onSubmitted,
      contextMenuBuilder: _buildContextMenu,
    );
  }
}
