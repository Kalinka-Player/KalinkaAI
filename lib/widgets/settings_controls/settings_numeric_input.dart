import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// Numeric input with optional constraints. 80px wide, right-aligned.
/// Shows accent-colored border on focus.
///
/// A number inside the bounds is propagated as it is typed; anything else
/// waits for blur or dispose, which pulls it inside them or, unparseable,
/// reverts to the value the edit began from.
class SettingsNumericInput extends StatefulWidget {
  final num value;
  final ValueChanged<num> onChanged;
  final double width;
  // Optional unit label (e.g. "s", "min", "ms") rendered to the right of
  // the input box. Sourced from the field's constraints.unit.
  final String? unit;
  // Bounds the backend declared, if any. A value outside them is pulled back
  // in on commit rather than sent to be refused.
  final num? min;
  final num? max;

  const SettingsNumericInput({
    super.key,
    required this.value,
    required this.onChanged,
    this.width = 80,
    this.unit,
    this.min,
    this.max,
  });

  @override
  State<SettingsNumericInput> createState() => _SettingsNumericInputState();
}

class _SettingsNumericInputState extends State<SettingsNumericInput> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  // Track the value we last reported to the parent so we don't re-emit
  // an unchanged value on a focus-blur after the user typed and then
  // erased back to where they started.
  late num _committedValue;

  // What the field held when the edit began, for unparseable text to revert
  // to: typing stages the numbers on the way, which are not the user's choice.
  late num _valueAtFocus;

  @override
  void initState() {
    super.initState();
    _committedValue = widget.value;
    _valueAtFocus = widget.value;
    _controller = TextEditingController(text: widget.value.toString());
    _focusNode = FocusNode();
    _focusNode.addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(covariant SettingsNumericInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value && !_focusNode.hasFocus) {
      _committedValue = widget.value;
      _showValue(widget.value.toString());
    }
  }

  /// A bound is a [double] even for a field that only holds whole numbers, so
  /// it is rounded to what the user was typing — a clamped `10` must go out as
  /// `64000`, not `64000.0`.
  num _pulledInsideBounds(num value) {
    final min = widget.min;
    final max = widget.max;
    if (min != null && value < min) return value is int ? min.round() : min;
    if (max != null && value > max) return value is int ? max.round() : max;
    return value;
  }

  void _showValue(String text) {
    if (_controller.text == text) return;
    _controller.text = text;
    _controller.selection = TextSelection.collapsed(offset: text.length);
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
    if (_focusNode.hasFocus) {
      _valueAtFocus = _committedValue;
    } else {
      _commitIfChanged();
    }
  }

  /// A number inside the bounds is staged as it is typed, so the change is
  /// recorded with the keyboard still up; anything else waits for the field
  /// to be left, which pulls it inside them.
  void _stageTyped() {
    final parsed = num.tryParse(_controller.text);
    if (parsed == null || _pulledInsideBounds(parsed) != parsed) return;
    if (parsed != _committedValue) {
      _committedValue = parsed;
      widget.onChanged(parsed);
    }
  }

  /// Parse + emit only if the text is a valid number and differs from
  /// what the parent currently holds. Unparseable text reverts to
  /// [_valueAtFocus]. A number outside the declared bounds is pulled
  /// back to the nearest one it may hold, and the field shows what it sent.
  void _commitIfChanged() {
    final typed = num.tryParse(_controller.text);
    final parsed = typed == null ? _valueAtFocus : _pulledInsideBounds(typed);
    _showValue(parsed.toString());
    if (parsed != _committedValue) {
      _committedValue = parsed;
      widget.onChanged(parsed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final box = Container(
      decoration: BoxDecoration(
        color: KalinkaColors.surfaceElevated,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: KalinkaColors.borderDefault),
      ),
      child: TextField(
        controller: _controller,
        focusNode: _focusNode,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        textAlign: TextAlign.right,
        textInputAction: TextInputAction.done,
        style: KalinkaTextStyles.searchBarInput.copyWith(
          fontSize: KalinkaTypography.baseSize + 2,
        ),
        decoration: InputDecoration(
          border: InputBorder.none,
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(7),
            borderSide: const BorderSide(color: Color(0x55FFFFFF)),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 10,
            vertical: 7,
          ),
          isDense: true,
        ),
        // Done closes the keyboard, and leaving the field commits it.
        onChanged: (_) => _stageTyped(),
      ),
    );

    final unit = widget.unit;
    if (unit == null || unit.isEmpty) {
      return SizedBox(width: widget.width, child: box);
    }

    // Append the unit to the right of the box. The box keeps its intrinsic
    // width when finite (compact rows); on the full-width expert layout it
    // flexes so the unit label stays pinned beside it.
    final unitLabel = Padding(
      padding: const EdgeInsets.only(left: 8),
      child: Text(unit, style: KalinkaTextStyles.trayRowSublabel),
    );
    return Row(
      mainAxisSize: widget.width.isFinite ? MainAxisSize.min : MainAxisSize.max,
      children: [
        widget.width.isFinite
            ? SizedBox(width: widget.width, child: box)
            : Expanded(child: box),
        unitLabel,
      ],
    );
  }
}
