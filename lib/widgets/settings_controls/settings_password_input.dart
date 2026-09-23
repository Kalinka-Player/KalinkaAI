import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

/// Password/masked input with eye toggle button.
///
/// Same commit semantics as [SettingsTextInput]: the typed value is held
/// locally and only propagated to [onChanged] on focus loss, submit, or
/// dispose. Re-staging on every keystroke would steal focus and the user
/// would lose every character after the first.
///
/// With [hidden] the store holds a value it never sends: the field shows a
/// mask in its place and the eye does nothing, there being nothing to
/// reveal. The first edit drops the mask and starts a new value; a deletion
/// leaves it empty, which commits as clearing the stored one.
class SettingsPasswordInput extends StatefulWidget {
  final String value;
  final bool hidden;
  final ValueChanged<String> onChanged;
  final double? width;

  const SettingsPasswordInput({
    super.key,
    required this.value,
    required this.onChanged,
    this.hidden = false,
    this.width,
  });

  @override
  State<SettingsPasswordInput> createState() => _SettingsPasswordInputState();
}

class _SettingsPasswordInputState extends State<SettingsPasswordInput> {
  // Private-use: never typed or pasted, so an edit always tells from the mask.
  static const _maskChar = '\uE000';
  static final _mask = _maskChar * 8;

  bool _obscured = true;
  late bool _masked;
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _masked = widget.hidden;
    _controller = TextEditingController(text: _masked ? _mask : widget.value);
    _focusNode = FocusNode();
    _focusNode.addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(covariant SettingsPasswordInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A held value coming back (saved, discarded, reloaded) ends the edit even
    // mid-focus, or the next blur would stage the old text over it again.
    final heldAgain = widget.hidden && !oldWidget.hidden;
    if (_focusNode.hasFocus && !heldAgain) return;
    if (widget.hidden != _masked) {
      _masked = widget.hidden;
      if (_masked) _obscured = true;
      _setText(_masked ? _mask : widget.value);
    } else if (!_masked &&
        widget.value != oldWidget.value &&
        _controller.text != widget.value) {
      _setText(widget.value);
    }
  }

  void _setText(String text) {
    _controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  void _onEdited(String text) {
    if (!text.contains(_maskChar)) {
      if (_masked) setState(() => _masked = false);
      return;
    }
    // Undo can bring the mask back: whole, it is the held value again.
    final held = widget.hidden && text == _mask;
    setState(() => _masked = held);
    if (!held) _setText(text.replaceAll(_maskChar, ''));
  }

  @override
  void dispose() {
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
    if (_masked) return;
    if (widget.hidden || _controller.text != widget.value) {
      widget.onChanged(_controller.text);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.width,
      child: Container(
        decoration: BoxDecoration(
          color: KalinkaColors.surfaceElevated,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: KalinkaColors.borderDefault),
        ),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                obscureText: _obscured || _masked,
                style: KalinkaTextStyles.searchBarInput.copyWith(
                  fontSize: KalinkaTypography.baseSize + 2,
                ),
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 7,
                  ),
                  isDense: true,
                ),
                onChanged: _onEdited,
                onSubmitted: (_) => _commitIfChanged(),
                onEditingComplete: _commitIfChanged,
              ),
            ),
            GestureDetector(
              onTap: _masked
                  ? null
                  : () => setState(() => _obscured = !_obscured),
              child: Container(
                width: 28,
                height: 28,
                margin: const EdgeInsets.only(right: 4),
                decoration: BoxDecoration(
                  color: KalinkaColors.surfaceElevated,
                  borderRadius: BorderRadius.circular(7),
                  border: Border.all(color: KalinkaColors.borderDefault),
                ),
                child: Icon(
                  _obscured ? Icons.visibility_off : Icons.visibility,
                  size: 13,
                  color: _masked
                      ? KalinkaColors.textMuted
                      : KalinkaColors.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
