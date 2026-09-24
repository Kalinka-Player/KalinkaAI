import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import 'inline_markdown.dart';
import 'settings_toggle.dart';

/// Collapsible section header with an integrated enable/disable switch.
///
/// Layout — matches the chevron-on-left convention used by `SettingsSection`
/// everywhere else in the app:
///
/// ```
/// ┌────────────────────────────────────────────┬──────────┐
/// │  [tap to expand]                           │  [tap]   │
/// │ [v] Section title                          │ [switch] │
/// │     optional status text (markdown)        │          │
/// └────────────────────────────────────────────┴──────────┘
/// ```
///
/// The two header zones have independent tap targets, separated by a
/// thin vertical divider:
///
///   * Left zone — expands/collapses the section body.
///   * Right zone — flips the enabled toggle. The switch itself sits at
///     its natural 42x24 size, vertically centered; only the tap area
///     extends.
///
/// `statusMarkdown` lets a plugin-resolved sub-feature status appear
/// directly under the title, no separate "Status" label. When the
/// section is disabled, the body still expands on tap so users can see
/// what they'd be enabling, but the rows render dimmed.
class SettingsToggleableSection extends StatefulWidget {
  final String title;
  final bool enabled;
  final ValueChanged<bool> onToggle;
  final String? statusMarkdown;
  final Widget? body;
  final bool initiallyExpanded;
  final bool isStaged;

  const SettingsToggleableSection({
    super.key,
    required this.title,
    required this.enabled,
    required this.onToggle,
    this.statusMarkdown,
    this.body,
    this.initiallyExpanded = false,
    this.isStaged = false,
  });

  @override
  State<SettingsToggleableSection> createState() =>
      _SettingsToggleableSectionState();
}

class _SettingsToggleableSectionState extends State<SettingsToggleableSection>
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
  void dispose() {
    _chevronController.dispose();
    super.dispose();
  }

  void _toggleExpanded() {
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
    final hasBody = widget.body != null;
    final hasStatus =
        widget.statusMarkdown != null && widget.statusMarkdown!.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Staged amber bar on the far left when this section's enabled
        // toggle has unsaved changes — visually consistent with the
        // amber accent SettingsRow uses for staged fields. Clear, not
        // absent, when unstaged, so staging never shifts the title.
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: 1,
                decoration: BoxDecoration(
                  color: widget.isStaged
                      ? KalinkaColors.statusPending
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Title + status (chevron on the left, matching the
              // chevron-leading convention used by SettingsSection
              // everywhere else in the app). Tap-to-expand.
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: hasBody ? _toggleExpanded : null,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        if (hasBody) ...[
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
                          const SizedBox(width: 8),
                        ],
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                widget.title,
                                style: KalinkaTextStyles.trayRowLabel.copyWith(
                                  // Slightly muted when disabled, to
                                  // reinforce the off state without
                                  // hiding the title.
                                  color: widget.enabled
                                      ? KalinkaColors.textPrimary
                                      : KalinkaColors.textSecondary,
                                ),
                              ),
                              if (hasStatus) ...[
                                const SizedBox(height: 3),
                                InlineMarkdown(
                                  text: widget.statusMarkdown!,
                                  style: KalinkaTextStyles.trayRowSublabel
                                      .copyWith(
                                        color: widget.enabled
                                            ? KalinkaColors.textSecondary
                                            : KalinkaColors.textMuted,
                                        height: 1.4,
                                      ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              // Vertical divider between title and switch — visual cue
              // for two independent tap zones.
              const VerticalDivider(
                width: 1,
                thickness: 1,
                color: KalinkaColors.borderSubtle,
              ),
              // Toggle zone (right). Switch stays at its natural 42x24
              // size, vertically centered; only the tap target extends
              // to the row's height.
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => widget.onToggle(!widget.enabled),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Center(
                    widthFactor: 1.0,
                    child: SettingsToggle(
                      value: widget.enabled,
                      onChanged: widget.onToggle,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (hasBody)
          AnimatedSize(
            duration: const Duration(milliseconds: 340),
            curve: const Cubic(0.4, 0, 0.2, 1),
            alignment: Alignment.topCenter,
            child: _expanded
                ? Opacity(
                    // Dim the body when the sub-feature is off so the
                    // user sees what they'd be configuring but can tell
                    // at a glance that nothing's running yet.
                    opacity: widget.enabled ? 1.0 : 0.45,
                    child: widget.body!,
                  )
                : const SizedBox.shrink(),
          ),
      ],
    );
  }
}
