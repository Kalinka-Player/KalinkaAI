import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import 'settings_row.dart' show kSettingsGutter;

/// Collapsible section with chevron and animated content.
///
/// Used as "Advanced toggle row" within cards.
class SettingsSection extends StatefulWidget {
  final String title;
  final Widget child;

  /// Open on first build; turning true later opens it again.
  final bool initiallyExpanded;
  final bool showTopBorder;

  /// Space either side of the header, as [SettingsRow.gutter].
  final double gutter;

  const SettingsSection({
    super.key,
    required this.title,
    required this.child,
    this.initiallyExpanded = false,
    this.showTopBorder = true,
    this.gutter = kSettingsGutter,
  });

  @override
  State<SettingsSection> createState() => _SettingsSectionState();
}

class _SettingsSectionState extends State<SettingsSection>
    with SingleTickerProviderStateMixin {
  late AnimationController _chevronController;
  late bool _expanded;

  @override
  void initState() {
    super.initState();
    _expanded = widget.initiallyExpanded;
    _chevronController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
      value: _expanded ? 1.0 : 0.0,
    );
  }

  @override
  void didUpdateWidget(covariant SettingsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Asked open later, e.g. over something newly wrong inside it.
    if (widget.initiallyExpanded &&
        !oldWidget.initiallyExpanded &&
        !_expanded) {
      _expanded = true;
      _chevronController.forward();
    }
  }

  @override
  void dispose() {
    _chevronController.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() {
      _expanded = !_expanded;
      if (_expanded) {
        _chevronController.forward();
      } else {
        _chevronController.reverse();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header row
        GestureDetector(
          onTap: _toggle,
          behavior: HitTestBehavior.opaque,
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: widget.gutter,
              vertical: 10,
            ),
            decoration: widget.showTopBorder
                ? const BoxDecoration(
                    border: Border(
                      top: BorderSide(color: KalinkaColors.borderSubtle),
                    ),
                  )
                : null,
            child: Row(
              children: [
                AnimatedBuilder(
                  animation: _chevronController,
                  builder: (context, child) {
                    return Transform.rotate(
                      angle: _chevronController.value * 3.14159,
                      child: child,
                    );
                  },
                  child: const Icon(
                    Icons.keyboard_arrow_down,
                    size: 12,
                    color: KalinkaColors.textSecondary,
                  ),
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    widget.title,
                    style: KalinkaTextStyles.trayRowSublabel.copyWith(
                      fontSize: KalinkaTypography.baseSize + 3,
                      color: KalinkaColors.textSecondary,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        // Animated content
        AnimatedSize(
          duration: const Duration(milliseconds: 340),
          curve: const Cubic(0.4, 0, 0.2, 1),
          alignment: Alignment.topCenter,
          child: _expanded ? widget.child : const SizedBox.shrink(),
        ),
      ],
    );
  }
}
