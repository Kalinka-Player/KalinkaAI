import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

/// Text input field for settings.
///
/// Dark surface background, small font. Supports wide (145px) and full-width
/// variants. Shows accent-colored border on focus.
///
/// Edits are staged as the user types, so Apply includes the focused field.
/// Nothing is committed from dispose: writing to a provider while the widget
/// tree is being removed interrupts cleanup and breaks subsequent navigation.
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

  /// Drawn under the field and rebuilt as the user types, with the text so
  /// far and the same replace-and-commit callback as [trailingBuilder].
  final Widget Function(BuildContext, String, ValueChanged<String>)?
  belowBuilder;

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
    this.belowBuilder,
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
  }

  @override
  void didUpdateWidget(covariant SettingsTextInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Staged edits echo the controller's current text. A different value is
    // an external reset (e.g. Discard), which must also update a focused field.
    if (widget.value != oldWidget.value && _controller.text != widget.value) {
      _controller.text = widget.value;
      _controller.selection = TextSelection.collapsed(
        offset: widget.value.length,
      );
    }
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
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
      onChanged: (_) => _commitIfChanged(),
      onSubmitted: (_) => _commitIfChanged(),
    );
    final trailing = widget.trailingBuilder?.call(context, _replaceWith);

    final input = SizedBox(
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
    final below = widget.belowBuilder;
    if (below == null) return input;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        input,
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: _controller,
          builder: (context, typed, _) =>
              below(context, typed.text, _replaceWith),
        ),
      ],
    );
  }
}
