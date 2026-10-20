# Kalinka settings design guide

Settings use one fixed page title, a restrained dark header and directly accessible controls. This specification covers Configuration, plugin settings and About, Advanced settings, change review, Download server logs, Output settings and the older Server settings screen. All dimensions are Flutter logical pixels (dp); text sizes are before the system text scaler.

## Direction and rationale

The previous logs screen had the clearer information hierarchy: a title followed by the task. Plugin and advanced pages repeated that title in a large Playfair banner. Configuration also used a transparent bar, while logs and output settings used a raised bar with a stronger divider and shadow.

Keep the logs screen's single-title structure, using a common implementation throughout settings. A subtle filled header identifies fixed navigation; one quiet rule separates it from scrolling content. Descriptions, state and actions remain visible without a second heading consuming vertical space.

This direction applies UI/UX Pro Max's minimal, functional layout guidance and its priorities for contrast, native controls, consistent spacing, keyboard focus, touch targets, safe areas and text scaling. Local searches covered dark music-player settings, accessible configuration, navigation consistency and Flutter text scaling. Marketing layouts, suggested replacement fonts and palettes do not fit this established utility interface; retain Kalinka's bundled fonts and semantic palette.

This is the settings specification. The branded player/search bars and editorial music-browsing headings serve different purposes. `PageBanner` remains available for those browsing pages. Existing confirmation dialogs and bottom sheets retain their modal typography; they do not repeat an underlying page title within the same surface.

## Page structure and navigation

1. `SettingsTopBar`, including the top safe area: Back, current page name, optionally one icon action, connection dot. The page's outer `SafeArea` uses `top: false`; the header applies the top inset inside its opaque background so the Android status-bar area matches the header. Controls remain below the system icons. Keep the page's side and bottom safe insets.
2. Optional secondary toolbar for page-specific controls, then connection/pending-change notices.
3. Optional pinned tabs on an overview. Other pages start with an introduction or their first controls.
4. Independently scrolling content, ending with 32dp breathing room. The host reserves space for the mini-player; content must not render underneath it.

Use sentence case: **Download server logs**, **Output settings**, **Advanced settings**, **Check your changes**. Plugin titles include their subject: **Qobuz settings**, **About Qobuz**. Do not add breadcrumbs, a second large title, a logo in place of the title, or a decorative heading icon.

Back closes the current panel through `SlideInPanel.closeOf(context)`. System Back does the same. Returning preserves the parent tab, scroll position and staged edits. Only the uppermost panel owns Back. The header remains outside the content scroll.

The shell's labelled navigation rail remains available beside settings on wider windows. Settings occupy the browsing pane, leaving the player available, and use the shared adaptive split calculation. On phones, Configuration remains in the existing server menu; settings retain their Back button with no additional navigation menu. Choosing another destination runs the existing pending-change guard and cannot dismiss an active operation. Resizing preserves the current settings page and staged changes. The mini-player grows with system text size, and settings reserve that height.

About is a labelled icon button in a plugin's title bar. Install/Uninstall belongs beside its status in the scrolling introduction. Expert mode and the renderer's name belong in a secondary toolbar below **Output settings**. The older **Server settings** screen uses that toolbar for Restart and Expert mode. Do not squeeze multiple controls into the title row.

## Colours and surfaces

Read these values from `KalinkaColors`, never duplicate hex literals in a screen.

| Role | Token | Value |
| --- | --- | --- |
| Page canvas | `background` | `#080808` |
| Fixed settings header | `surfaceBase` | `#0E0E0E` |
| Cards | `surfaceRaised` | `#151513` |
| Inputs | `surfaceInput` | `#171715` |
| Unselected pills / raised controls | `surfaceElevated` | `#1C1C1A` |
| Header-button hover / press | `surfaceOverlay` | `#222220` |
| Titles, values, Back, focus outline | `textPrimary` | `#FAF5F0` |
| Descriptions, captions, section labels | `textSecondary` | `#A3A3A3` |
| Low-emphasis supporting text | `textMuted` | `#858585` |
| Header/card/row divider | `borderSubtle` | `#11FFFFFF` (white, 6.67% opacity) |
| Input borders and tab baseline | `borderDefault` | `#323235` |
| Selected tab and enabled switch | `accent` | `#C2394B` |
| Online dot | `statusOnline` | `#3D8A58` |
| Connecting/reconnecting dot | `statusPending` | `#C8943A` |
| Offline dot | `statusOffline` | `#858585` |
| Plugin error text and icon | `statusError` | `#E86A6A` |
| Online badge text on tinted fill | `statusOnlineLight` | `#5FB07E` |
| Pending badge text on tinted fill | `statusPendingLight` | `#E8B86A` |

The header always has the same opaque fill, a 1dp bottom rule and no shadow or elevation. There is no transparent variant. Card borders and internal row dividers are also 1dp. These rules group content; they are not the only cue identifying a control. The inset tab baseline is a separate boundary below the tabs, using `borderDefault` at 1dp and a 2dp berry selected indicator.

Measured sRGB contrast: primary/secondary text on the header is **17.82:1 / 7.65:1**; on cards it is **16.88:1 / 7.25:1**. Muted text on a card is **4.95:1**. Keep normal text at least 4.5:1 and meaningful icons at least 3:1. Do not use the base green as small text on cards (4.33:1); use the brighter status text token on its intended tinted surface. Recheck the composed colour when introducing any tint or opacity.

## Typography

Use the bundled IBM Plex families. System text scaling is respected, not clamped. Where a line height is not specified below, preserve the font's natural metrics and let the row grow.

| Element | Family | Size / weight | Line height / tracking |
| --- | --- | --- | --- |
| Single page title | IBM Plex Sans | 18 / 600 | 24dp; −0.1dp tracking |
| Page introduction | IBM Plex Sans | 14 / 400 | 21dp |
| Setting label or action | IBM Plex Sans | 16 / 500 | Natural; −0.1dp tracking |
| Help, caption and metadata | IBM Plex Sans | 13 / 500 | Natural; no added tracking |
| Inline plugin status | IBM Plex Sans | 13 / 500 | 18.2dp; sentence case; no added tracking |
| Section label | IBM Plex Mono | 13 / 600 | Natural; 1.8dp tracking; uppercase |
| Configuration tab | IBM Plex Mono | 14 / 600 | Natural; 1.4dp tracking; uppercase |
| Server name in identity card | Playfair Display | 24 / 500 | Natural; no added tracking |
| Server address | IBM Plex Sans | 16 / 400 | Natural; inherited −0.1dp tracking |

`KalinkaTextStyles.settingsPageTitle` and `settingsDescription` own the first two styles. Other rows use the established `trayRowLabel`, `trayRowSublabel` and `sectionHeaderMuted` tokens. Use Playfair Display for the server name in its identity card to carry the application's visual style; navigation-bar titles remain IBM Plex Sans.

## Geometry and spacing

**Customise Home** follows the same fixed header, typography and page gutters. With no pins, it shows brief pinning instructions and source tiles; choosing a source opens its catalog and closes the panel. If no sources are enabled, explain that a source must be enabled in Configuration. With pins, its scrolling introduction contains only **Drag catalogs to reorder.** and **Search, collections and sources stay in place.**, using `settingsDescription` and 20dp vertical padding. A full-width 1dp `borderSubtle` separator follows the explanation. The content below is a draggable list of catalog names and metadata, with subtle row separators. It occupies the browsing pane on wider layouts and the space above the mini-player on phones. The preview and Unpin row actions use Kalinka’s round 48dp icon buttons with the shared hover/press highlight. The preview trigger has no menu-open or focus-only fill and remains keyboard-operable; it does not use the header’s outlined focus style. The preview icon opens an anchored picker with geometric illustrations and labels for all four layouts, using a crimson outline and checkmark for the current choice; it closes after three seconds of inactivity. The crossed-out Unpin icon opens a centered confirmation dialog with Cancel and Unpin actions. Center it within the browsing pane on wider layouts and within the screen on phones; use a fade-in, not a bottom-sheet slide. Dismissing the dialog leaves the catalog pinned. See [Customise Home](../PALETTE.md#customise-home) for the interaction rules.

| Element | Specification |
| --- | --- |
| Header | 52dp minimum height; grows for wrapped/scaled titles |
| Header padding | Left 6, right 16, top/bottom 2dp |
| Back/action target | At least 48 × 48dp; icon 22dp |
| Back-to-title gap | 8dp |
| Title-to-optional-action gap | 8dp |
| Space before connection dot | 12dp |
| Connection dot | 8 × 8dp, centred in a 48dp-high status region |
| Header button corners / focus | Radius 8dp; 2dp primary-colour focus outline |
| Page gutter | 20dp below the 900dp app-window breakpoint; 25dp at/above it |
| Secondary toolbar | Page gutter horizontally; 8dp vertically; 12dp between items, 8dp between wrapped runs |
| Scrolling introduction | Page gutter horizontally; 20dp above and below |
| Status/actions-to-description | 12dp |
| Status/detail wrap | 8dp horizontal, 4dp vertical |
| Section heading inset | Page gutter; 20dp above, 10dp below |
| Source/device catalog grouping | First group 24dp below tabs; later groups 36dp above; 8dp below label |
| Card | Radius 14dp; 1dp subtle border; 12dp bottom margin |
| Standard setting row | 16dp horizontal, 12dp vertical padding; flexible height |
| Vertical field control | 10dp below its label/help block |
| Logs first card | 20dp below the header/notices |
| End of scrolling content | 32dp |

The header's 6dp outer inset places the Back glyph within the visual page gutter while retaining its full touch target. Its title aligns after Back; body sections align to the page gutter. Do not indent all body content to the title's x-position.

The 25dp tablet gutter is an existing Kalinka layout token. Keep it consistent across settings instead of independently rounding individual pages. Content layout still responds to the **actual panel width**, not just the window breakpoint.

## Plugin identity, status and description

In overview rows, group the name and its status on the first line. Wrap the whole status onto the next line when needed. The catalog description follows after 4dp; publisher/maturity tags follow that description after 6dp. Live summaries and pending-change details form the last metadata line, with 8dp above. Align the icon tile to the top of the text group.

On Settings and About pages, keep the single fixed page title. Start the scrolling introduction with the plugin's status and live summary, followed by its description after 12dp. About's compatibility information follows the description. Install/Uninstall stays alongside the status where space permits and moves below it on narrow layouts. Enabled and other controls follow the introduction, separate from the read-only live state.

Use sentence-case **Ready**, **Warning**, **Error**, **Disabled**, and operation labels as unboxed text, with a 16dp icon and a 6dp icon/text gap. Ready uses a check icon and `statusOnlineLight`; Warning uses a warning icon and `statusPendingLight`; Error uses an error icon and `statusError`; inactive states use `textSecondary`. The text and icon communicate state without relying on colour. Publisher tags remain visually distinct from operating status.

Keep a backend message with its status. An Error/Warning with an explanation gets 12dp padding, a 2dp left rule in the status colour and a 7% status-colour background; place the message 8dp below the status line using 14dp/21dp primary text. Preserve backend wording and inline formatting. Show this message once, including when the plugin has no editable settings; do not repeat it in the fields card. A return to Ready removes the obsolete error. Plugin pages expose a contextual status label to assistive technology; errors and operations can announce updates without moving focus.

## Streamer content

Keep this order directly on the tab:

| Group | Contents |
| --- | --- |
| SERVER | Identity card: name and pencil, selectable address, server version, raw backend supervisor status |
| SOFTWARE UPDATES | Bundle/component update state and automatic updates in one card |
| MANAGEMENT | Restart Kalinka, Network, dashboard, restart streamer, power off streamer, when supported |
| SUPPORT | Download server logs and Advanced settings |

The name is a prominent value, not a duplicate page heading. Its 48dp pencil opens a bottom sheet; Done stages the name, Cancel/Back discards the sheet edit. Apply/restart follows the existing settings flow. Settings reads refresh the connected server's saved label without changing its address or reconnecting.

The address has 16dp side padding, a 4dp label/value gap and 20dp bottom padding. The metadata area has 16dp padding, 8dp between details and 16dp between label/value columns. At less than `280 × textScaler.scale(1)` available width, each detail stacks its label above its value with a 4dp gap. Do not truncate an address or status.

**Network** appears only for a box with a supervisor. It opens a **Network** page that hosts the same network panel as setup: the current wired or Wi-Fi connection, and the Wi-Fi networks the box can join.

Display the supervisor status exactly as the backend returns it; do not parse a version or infer health from “Installed”. Package updates show the components the backend identifies as changed. Sound-card controls belong in Output settings. Device automation belongs in Advanced settings.

## Responsive layout and interaction

- Page titles wrap naturally with no ellipsis, fixed line limit, auto-shrink or capped text scaler. When the 18dp title scales above 27dp (1.5×), place it on a full-width second row **inside the same fixed header**, inset to the page gutter, with 10dp bottom padding plus the header’s 2dp outer padding. Back, the optional action and status stay on the first row. This avoids a narrow column of oversized text between icons.
- `SettingsPageIntro` stacks status and action below 320dp of **content width**, or when 14dp text scales above 18.2dp (1.3×). Otherwise status expands beside the action. Descriptions always use the full intro width.
- Secondary toolbars wrap. Device names and status text can occupy their own line. Do not force a long name, Expert toggle and page title into one row.
- Use native `IconButton`/`TextButton` for header/toolbar actions, with a visible keyboard focus outline. Keep visual bounds stable on focus, hover and press. Button tooltips name the action; decorative icons are excluded from semantics.
- Mark the page title as a semantic header. Give the connection dot a readable status tooltip and an accessible label containing the current server name and status. Colour alone is insufficient. The dot is not a button.
- Keep destructive confirmation and pending-change behaviour intact. Layout changes must not initiate a restart, update, download or power-off.
- Respect safe areas and the host's mini-player allocation. Lists scroll within the remaining height. Avoid placing fixed elements over the list.
- Panel motion uses `kSlideInPanelDuration` (320ms, cubic 0.4/0/0.2/1); skip the slide when the system disables animations. Header interactions add no movement or layout shifts.

## Implementation and verification

Reuse `SettingsTopBar`, `SettingsToolbar` and `SettingsPageIntro`; do not create another private header in a screen. `ConfigurationAppearance` supplies shared gutters and section spacing. The common `SlideInPanel` owns Back and panel transitions.

For changes to this system, check 375dp phone, narrow 320dp, landscape and tablet-panel layouts; normal, 2× and large system text; reduced motion; long plugin/device names; connected and disconnected states; keyboard Back and About; and pending edits on return. Verify the logs options/prepare/save flow and renderer Expert mode still work. Review actual rendered screens with bundled fonts in addition to widget assertions. These checks validate the changed settings surfaces; they are not a claim of an app-wide accessibility audit.

Reference: [UI/UX Pro Max skill](../../../.codex/skills/ui-ux-pro-max/SKILL.md), especially its `references/pro-rules.md` and accessibility, interaction and typography priorities. The repository tokens and shared widgets are the implementation source of truth; update this document with them when the design changes.
