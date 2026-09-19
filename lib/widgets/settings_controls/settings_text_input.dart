import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

/// Text input field for settings.
///
/// Dark surface background, small font. Supports wide (145px) and full-width
/// variants. Shows accent-colored border on focus.
///
/// Commit semantics: [onChanged] is **not** fired on every keystroke — that
/// would re-stage the field on each character and bounce focus when the
/// parent rebuilds. Instead, the typed value is held locally and committed
/// (a) when the field loses focus, (b) when the user submits (Enter), and
/// (c) on dispose if the field still holds an uncommitted edit. This keeps
/// the "Staged" badge from flashing while typing and stops focus loss.
class SettingsTextInput extends StatefulWidget {
  final String value;
  final String? hintText;
  final ValueChanged<String> onChanged;
  final double? width;
  final bool obscureText;
  final bool autofocus;

  /// Drawn inside the field, after the text. Built with a callback that
  /// replaces the text and commits it, so a picked suggestion needs no
  /// second commit path.
  final Widget Function(BuildContext, ValueChanged<String>)? trailingBuilder;

  /// Tinted when the value has something wrong with it.
  final Color? borderColor;

  const SettingsTextInput({
    super.key,
    required this.value,
    this.hintText,
    required this.onChanged,
    this.width,
    this.obscureText = false,
    this.autofocus = false,
    this.trailingBuilder,
    this.borderColor,
  });

  @override
  State<SettingsTextInput> createState() => _SettingsTextInputState();
}

class _SettingsTextInputState extends State<SettingsTextInput> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
    _focusNode = FocusNode();
    _focusNode.addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(covariant SettingsTextInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    // External value changed (e.g. config reload, parent reverted). Adopt
    // it only when the user isn't actively typing — otherwise we'd clobber
    // their in-progress edit mid-stroke.
    if (widget.value != oldWidget.value &&
        !_focusNode.hasFocus &&
        _controller.text != widget.value) {
      _controller.text = widget.value;
      _controller.selection = TextSelection.collapsed(
        offset: widget.value.length,
      );
    }
  }

  @override
  void dispose() {
    // If the user navigated away with focus still in the field, commit
    // their pending edit so it isn't silently dropped.
    _commitIfChanged();
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    if (!_focusNode.hasFocus) _commitIfChanged();
  }

  void _commitIfChanged() {
    if (_controller.text != widget.value) {
      widget.onChanged(_controller.text);
    }
  }

  void _replaceWith(String value) {
    _controller.text = value;
    _controller.selection = TextSelection.collapsed(offset: value.length);
    _commitIfChanged();
  }

  @override
  Widget build(BuildContext context) {
    final field = TextField(
      controller: _controller,
      focusNode: _focusNode,
      autofocus: widget.autofocus,
      obscureText: widget.obscureText,
      style: KalinkaTextStyles.textFieldInput,
      textInputAction: TextInputAction.done,
      decoration: InputDecoration(
        hintText: widget.hintText,
        hintStyle: KalinkaTextStyles.searchPlaceholder.copyWith(
          fontSize: KalinkaTypography.baseSize + 2,
          color: KalinkaColors.textSecondary,
        ),
        border: InputBorder.none,
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(7),
          borderSide: const BorderSide(color: Color(0x55FFFFFF)),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        isDense: true,
      ),
      onSubmitted: (_) => _commitIfChanged(),
      onEditingComplete: _commitIfChanged,
    );
    final trailing = widget.trailingBuilder?.call(context, _replaceWith);

    return SizedBox(
      width: widget.width,
      child: Container(
        decoration: BoxDecoration(
          color: KalinkaColors.surfaceElevated,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: widget.borderColor ?? KalinkaColors.borderDefault,
          ),
        ),
        child: trailing == null
            ? field
            : Row(
                children: [
                  Expanded(child: field),
                  const SizedBox(width: 4),
                  trailing,
                  const SizedBox(width: 6),
                ],
              ),
      ),
    );
  }
}
