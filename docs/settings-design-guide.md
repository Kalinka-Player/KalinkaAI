# Kalinka settings design guide

Settings use one fixed page title, a restrained dark header and directly accessible controls. This specification covers Settings, plugin settings and About, the expert settings list, change review, Download server logs and Output settings. All dimensions are Flutter logical pixels (dp); text sizes are before the system text scaler.

## Direction and rationale

The previous logs screen had the clearer information hierarchy: a title followed by the task. Plugin and advanced pages repeated that title in a large Playfair banner. Settings also used a transparent bar, while logs and output settings used a raised bar with a stronger divider and shadow.

Keep the logs screen's single-title structure, using a common implementation throughout settings. A subtle filled header identifies fixed navigation; one quiet rule separates it from scrolling content. Descriptions, state and actions remain visible without a second heading consuming vertical space.

This direction applies UI/UX Pro Max's minimal, functional layout guidance and its priorities for contrast, native controls, consistent spacing, keyboard focus, touch targets, safe areas and text scaling. Local searches covered dark music-player settings, accessible configuration, navigation consistency and Flutter text scaling. Marketing layouts, suggested replacement fonts and palettes do not fit this established utility interface; retain Kalinka's bundled fonts and semantic palette.

This is the settings specification. The branded player/search bars and editorial music-browsing headings serve different purposes. `PageBanner` remains available for those browsing pages. Existing confirmation dialogs and bottom sheets retain their modal typography; they do not repeat an underlying page title within the same surface.

## Page structure and navigation

1. `SettingsTopBar`, including the top safe area: Back, current page name, optionally one icon action, connection dot. The page's outer `SafeArea` uses `top: false`; the header applies the top inset inside its opaque background so the Android status-bar area matches the header. Controls remain below the system icons. Keep the page's side and bottom safe insets.
2. Optional secondary toolbar for page-specific controls, then the connection notice.
3. Optional pinned tabs on an overview. Other pages start with an introduction or their first controls.
4. Independently scrolling content, ending with 32dp breathing room. The host reserves space for the mini-player; content must not render underneath it.
5. While changes are staged, `PendingChangesBanner` at the foot: the amber bar (count, consequence, Discard, APPLY) that a renderer and Settings share. It is laid out under the content, never over it, so the page shrinks to make room and its last controls scroll up into view above the bar. The Settings banner sits under every page it opens; when an issue blocks applying, the bar names it and APPLY becomes REVIEW. Its actions are 48dp targets, and each first leaves the field being typed in, so its text is staged and the keyboard closes. In a field, the keyboard's Done keeps the value and closes the keyboard, and a number is staged as soon as it is one inside its bounds.

Use sentence case: **Download server logs**, **Check your changes**. A renderer's page is titled with the renderer's name alone. Plugin titles include their subject: **Qobuz settings**, **About Qobuz**. Do not add breadcrumbs, a second large title, a logo in place of the title, or a decorative heading icon.

Keep setting descriptions short, with requirements and special values beside the control. Optional `help_details` appears behind an info button beside the setting label. Use `SettingsHelpButton` in regular, expert and setup views, including read-only fields. It opens the shared dialog with the setting name, detailed text and a Close button. Keyboard dismissal returns focus to the info button; pointer dismissal leaves it idle. Hover and press brighten the icon without a filled background or ripple. Keyboard focus uses a 2dp primary outline. Missing or blank details show no button.

Omit section descriptions that repeat the heading or visible controls. When a section needs a caption, place it 4dp below the heading and leave 10dp before the card, matching collection captions.

Back closes the current panel through `SlideInPanel.closeOf(context)`. System Back does the same. Returning preserves the parent tab, scroll position and staged edits. Only the uppermost panel owns Back. The header remains outside the content scroll.

Use the shared `KalinkaBackButton`: a 40dp outlined circle in a 48dp target, matching filter controls, with neutral hover/press and a primary keyboard focus ring. This also applies to browsing, search and setup; the album view retains its separate treatment. See [Back buttons](../PALETTE.md#back-buttons) for exact states.

The shell's labelled navigation rail remains available beside settings on wider windows. Settings occupy the browsing pane, leaving the player available, and use the shared adaptive split calculation. On phones, Settings remains in the existing server menu; settings retain their Back button with no additional navigation menu. Beside the rail, which names Settings and is how it is left, Settings has no top bar: its tabs start at the top of the pane, taking the top safe inset themselves. Choosing another destination runs the existing pending-change guard and cannot dismiss an active operation. Resizing preserves the current settings page and staged changes. The mini-player grows with system text size, and settings reserve that height.

Keep all three Settings tabs visible, with widths proportional to their label lengths. Uppercase mono labels ellipsize when needed, with full names in tooltips and accessibility labels. Music sources and HiFi control show a 7.8dp crimson dot (`accent`, `#C2394B`, matching the Update button) at the top right of their text while an installed plugin in that tab has an available update. Streamer shows the same dot when its software update status reports an available, supported system update, including component-only updates. System updates are independent of plugin update-check support. Include the plugin update count or “system update available” in the tab's tooltip and accessible name. Anchor the dot to the text, including when truncated, using the existing padding so updates do not move the tabs or their labels. Clear it when updates finish or their status reloads without an available update; unsupported checks show none.

About is a labelled icon button in a plugin's title bar. Install/Uninstall belongs beside its status in the scrolling introduction. A renderer's page is titled with the renderer's name, in the top bar's title face, and ends its top bar with the Expert settings switch: a round 40dp `{}` icon button with a matching compact tap target, grey (`surfaceElevated`, `borderDefault`, `textSecondary` icon) while off and outlined in berry (`accentSubtle`, `accentBorder`, `accentTint` icon) while on, since expert is a mode the page stays in. Do not add further controls to the title row.

## Colours and surfaces

Read these values from `KalinkaColors`, never duplicate hex literals in a screen.

| Role | Token | Value |
| --- | --- | --- |
| Page canvas | `background` | `#080808` |
| Fixed settings header | `surfaceBase` | `#0E0E0E` |
| Cards | `surfaceRaised` | `#151513` |
| Dialogs, popovers and bottom sheets (Connect reference) | `surfaceDialog` | `#151513` |
| Inputs | `surfaceInput` | `#171715` |
| Unselected pills / raised controls | `surfaceElevated` | `#1C1C1A` |
| Header-button hover / press | `surfaceOverlay` | `#222220` |
| Titles, values, Back, focus outline | `textPrimary` | `#FAF5F0` |
| Descriptions, captions, section labels | `textSecondary` | `#A3A3A3` |
| Low-emphasis supporting text | `textMuted` | `#858585` |
| Header/card/row divider | `borderSubtle` | `#11FFFFFF` (white, 6.67% opacity) |
| Input borders | `borderDefault` | `#323235` |
| Selected tab and switch track when on (thumb `textPrimary`) | `accent` | `#C2394B` |
| Switch when off: thumb `textSecondary` on a `surfaceElevated` track edged in `borderDefault`; disabled, either state at reduced opacity, the thumb still visible | `textSecondary` | `#A3A3A3` |
| Online dot | `statusOnline` | `#3D8A58` |
| Connecting/reconnecting dot | `statusPending` | `#C8943A` |
| Offline dot | `statusOffline` | `#858585` |
| Plugin error text and icon | `statusError` | `#E86A6A` |
| Online badge text on tinted fill | `statusOnlineLight` | `#5FB07E` |
| Pending badge text on tinted fill | `statusPendingLight` | `#E8B86A` |

The header always has the same opaque fill, a 1dp bottom rule and no shadow or elevation. There is no transparent variant. Card borders and internal row dividers are also 1dp. These rules group content; they are not the only cue identifying a control. Settings and search tabs share the PLAYING / QUEUE button: 8dp horizontal and 12dp vertical padding, 8dp gaps, 6dp rounded corners, `surfaceInput` on hover and `surfaceOverlay` on keyboard focus. The underline sits inside the horizontal padding, 4dp above the bottom, with 1dp rounded ends. Align the first tab’s visible label to the page content gutter; its 8dp highlight padding extends outside that gutter and remains visible inside the scroll viewport. They have no rule under them: only the selected tab's 2dp berry indicator, then the content. Tab labels stay on one line at their full width in a horizontally scrollable strip, with 48dp minimum targets. Keep the active tab visible when selecting a tab or resizing the pane, and keep the strip pinned above the vertically scrolling content.

Dialogs and bottom sheets share Connect's neutral `surfaceDialog` background, including plugin editors, option pickers and confirmations. Keep Material surface tint transparent. Their X uses the shared `OverlayCloseButton`: the filter dialog's 34dp outlined circle, 18dp primary icon and 48dp target. Hover/press use a neutral fill and brighter ring; keyboard focus uses a primary ring. See [dialog and sheet chrome](../PALETTE.md#dialogs-and-bottom-sheets) for the exact states. Preserve the kiosk output panel's dedicated controls.

Sheets remain bottom sheets on phones. On desktop/tablet windows they become centered dialogs without a beak, with a 60% black scrim behind them. All dialogs opened from settings, including Drives & Shares’ **+** form, center in the **whole window**, as do confirmations and notices. Cap settings dialogs at the shared settings content width, `kKalinkaContentMaxWidth` (560dp), using `dialogMaxWidth` for adaptive editors and pickers. Compact forms and confirmations retain their narrower 460dp cap. Only output selector, Filters and Connect use beaked dialogs, with no background dimming. Use the whole window's usable dimensions (width at least 720dp and greater than the 640dp sheet cap, height at least 480dp), even for a narrow settings or player pane. Short landscape phones keep sheets and their dimmed background. Use the shared helpers so positioning avoids screen edges and keyboards, outside tap/Escape dismiss, and staged edits survive crossing the breakpoint. References to sheets below describe their content and phone presentation; their wide presentation defaults to a centered, dimmed dialog.

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
| Settings tab | IBM Plex Mono | 13 / 600 | `sectionLabel`, as PLAYING / QUEUE; 1.5dp tracking; uppercase |
| Server name in identity card | Playfair Display | 24 / 500 | Natural; no added tracking |
| Server address | IBM Plex Sans | 16 / 400 | Natural; inherited −0.1dp tracking |

`KalinkaTextStyles.settingsPageTitle` and `settingsDescription` own the first two styles. Other rows use the established `trayRowLabel`, `trayRowSublabel` and `sectionHeaderMuted` tokens. Use Playfair Display for the server name in its identity card to carry the application's visual style; navigation-bar titles remain IBM Plex Sans.

## Geometry and spacing

**Customise Home** follows the same fixed header, typography and page gutters. With no pins, it shows one-tap pinning instructions and source tiles. With pins, its introduction explains drag reorder and tapping a name to change it on Home, then notes that search, collections and sources stay in place. Use `settingsDescription`, 20dp vertical padding and a full-width `borderSubtle` separator. Rows contain the editable Home name, source/filter metadata, preview preference, drag handle and round 48dp preview/unpin buttons. Preview content stays on Home. The anchored picker offers Automatic / Small preview / Large preview / Shortcut only with geometric illustrations, a crimson outline and checkmark on the current choice, immediate saving and the existing three-second idle dismissal. It uses four columns when they fit, two on narrower panes, and one at large text sizes. Tapping a name opens a centered optional-name editor; an empty name restores the original. Unpin uses a centered Cancel / Unpin confirmation. All dialogs use the whole window and dimmed backdrop. See [Customise Home](../PALETTE.md#customise-home) and [adaptive Home previews](home-catalogs.md).

| Element | Specification |
| --- | --- |
| Header | 52dp minimum height; grows for wrapped/scaled titles |
| Header padding | Left 6, right 16, top/bottom 2dp |
| Back/action target | At least 48 × 48dp; icon 22dp |
| Back-to-title gap | 8dp |
| Title-to-optional-action gap | 8dp |
| Space before connection dot | 12dp |
| Connection dot | 8 × 8dp, centred in a 48dp-high status region |
| Back shape / focus | 40dp circle; 2dp primary-colour focus outline |
| Other header button corners / focus | Radius 8dp; 2dp primary-colour focus outline |
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

The 25dp tablet gutter is an existing Kalinka layout token. Keep it consistent across settings instead of independently rounding individual pages. Content layout still responds to the **actual panel width**, not just the window breakpoint. On a wider panel the gutter grows, so settings and Customise Home content stays at most 560dp wide (`kKalinkaContentMaxWidth`), centred, while backgrounds, scroll areas and the top bar's Back keep to the panel's edges. Read the gutter below `ConfigurationAppearance`, which measures the panel. Setup screens — server discovery, Bluetooth and hotspot setup, and every setup step — share one centred 600dp column with 20dp sides: the same 560dp of content.

## Plugin identity, status and description

In overview rows, group the name and its status on the first line. Wrap the whole status onto the next line when needed. The catalog description follows after 4dp; publisher/maturity tags follow that description after 6dp. Live summaries and pending-change details form the last metadata line, with 8dp above. Align the icon tile to the top of the text group.

On Settings and About pages, keep the single fixed page title. Start the scrolling introduction with the plugin's status and live summary, followed by its description after 12dp. About's compatibility information follows the description. Install/Uninstall stays alongside the status where space permits and moves below it on narrow layouts. Enabled and other controls follow the introduction, separate from the read-only live state.

Use sentence-case **Ready**, **Warning**, **Error**, **Disabled**, and operation labels as unboxed text, with a 16dp icon and a 6dp icon/text gap. Ready uses a check icon and `statusOnlineLight`; Warning uses a warning icon and `statusPendingLight`; Error uses an error icon and `statusError`; inactive states use `textSecondary`. The text and icon communicate state without relying on colour. Publisher tags remain visually distinct from operating status.

Keep a backend message with its status. An Error/Warning with an explanation gets 12dp padding, a 2dp left rule in the status colour and a 7% status-colour background; place the message 8dp below the status line using 14dp/21dp primary text. Preserve backend wording and inline formatting. Show this message once, including when the plugin has no editable settings; do not repeat it in the fields card. A return to Ready removes the obsolete error. Plugin pages expose a contextual status label to assistive technology; errors and operations can announce updates without moving focus.

## Plugin settings

A plugin's settings follow its introduction and controls as labelled cards, with nothing folded away. Each collection, each section and each run of fields opened by a heading takes a card under a section label, the collection's help as a caption under its label; fields before any of these share an unlabelled first card. The server sets the order: a collection follows the field it is placed after, a section comes before the field it is placed before. A section with a switch of its own starts its card with that switch, and its other rows dim while it is off. A section inside a card opens in place under a small label, or with none where it only groups other sections. A status field reads as a line under the help of the setting before it, never as a row of its own.

A collection lists one row per entry: a 36dp icon tile, where the entry points, and its kind beneath. A row opens the entry in a sheet. The status the server reports for the collection follows the rows, and the card ends with one compact neutral button per kind of entry (**Folder on the server**, **Network share**), or a single **Add** where there is one kind; a long label is cut at large text rather than overflowing. A button opens the sheet for that kind, titled with it and describing it, so the sheet never asks for the kind again. The form's first group has no heading, as the sheet's title already introduces it.

Temporarily hide the **Choose a folder on the server** button in all settings, regardless of server capabilities, while server folder browsing is broken. Keep manual path entry and server-provided suggestions available. Retain the folder picker implementation for later repair.

**Storage** is a section of the Streamer tab (`base_config.storage`): **Mount USB drives automatically** and **Show drives as a source**, then the **Mounts** collection with one button per kind, **NFS share** and **Disk on this machine**, as any collection lays them out.

## Streamer content

On the Streamer tab, the Expert settings switch ends the Settings top bar, as on a renderer's page; where the top bar is hidden beside the navigation rail, it ends the tab row instead. It is the same round `{}` button and the same setting: one switch for the whole app, kept on the device so it survives switching tabs, leaving and restarting. On, the tab's body is the expert list in place of the groups below; there is no separate Advanced settings page.

The expert list is drawn as the simple page draws settings: a search field alone at the top (no introduction above it), pinned under the tabs on the page's own background, then every field as a standard setting row in one card (`surfaceRaised`, 14dp radius, 1dp `borderSubtle` border and dividers; rows 16dp × 12dp, `trayRowLabel` name, the dotted path in `textMuted` mono under it, `trayRowSublabel` help, the control 10dp below; staged rows tinted and ruled in amber as elsewhere). A renderer's expert list is the same.

Off, keep this order directly on the tab:

| Group | Contents |
| --- | --- |
| SERVER | Identity card: name and pencil, selectable address, server version, raw backend supervisor status |
| DISPLAY | Shown when the saved `base_config.display.enabled` is true or the app is launched with kiosk enabled: local display inactivity timeouts |
| THIS DEVICE | Always available in the simple Streamer tab: the local on-screen keyboard switch |
| SOFTWARE UPDATES | Bundle/component update state and automatic updates in one card |
| MANAGEMENT | Restart Kalinka, Network, dashboard, restart streamer, power off streamer, when supported |
| SUPPORT | Download server logs |

The name is a prominent value, not a duplicate page heading. Its 48dp pencil opens a bottom sheet; Done stages the name, Cancel/Back discards the sheet edit. Apply follows the existing settings flow. Fields marked `applies_live` save without restarting Core; mixed changes still use the restart flow. Renaming the streamer can interrupt AirPlay receivers that inherit its name, as the server-provided help explains. Settings reads refresh the connected server's saved label without changing its address or reconnecting.

The address has 16dp side padding, a 4dp label/value gap and 20dp bottom padding. The metadata area has 16dp padding, 8dp between details and 16dp between label/value columns. At less than `280 × textScaler.scale(1)` available width, each detail stacks its label above its value with a 4dp gap. Do not truncate an address or status.

**Network** appears only for a box with a supervisor. It opens a **Network** page that hosts the same network panel as setup: the current wired or Wi-Fi connection, and the Wi-Fi networks the box can join.

**Display** contains **Return to now playing** (15 s, 30 s, 1 min, 2 min; default 30 s) and **Blank screen after** (Off, 5 min, 10 min, 15 min, 30 min; default 5 min). Place each dropdown to the right of its label and help, reserving room by wrapping the text on the left. Use an anchored popup with the Bluetooth device menu's neutral surface and border, not a bottom sheet. Show whole-minute durations in minutes. Keep help brief: **After inactivity.** and **When idle and paused or stopped.**, plus a short backlight capability note. Save immediately in the local display's SharedPreferences, using seconds internally and 0 for Off. Remote clients show a note directing the user to the streamer's screen instead of editing unrelated local preferences. An explicit kiosk launch (`KALINKA_KIOSK`) also shows editable controls for testing, even when the server display setting is off. Blanking runs only while paused or stopped; touch, keyboard input or resumed playback wakes it, and the waking input does not activate a control. These changes do not stage server settings or require a restart.

Display the supervisor status exactly as the backend returns it; do not parse a version or infer health from “Installed”. Package updates show the components the backend identifies as changed. Sound-card controls belong in Output settings. Device automation belongs in the expert list.

**This device** contains **On-screen keyboard**. Default it on for Kalinka's
Flutter Pi launcher (`localDisplayKioskProvider`), and off elsewhere. Use that
default only when no preference is saved; an explicit on or off always wins.
Save immediately
to this device's SharedPreferences (`Kalinka.client.onScreenKeyboard`), independent
of server connections, display capability and staged server settings. Switching it
off restores platform input. Keyboard labels, previews and pickers use Kalinka's
existing IBM Plex Sans; do not bundle additional keyboard fonts.
The keyboard uses neutral Kalinka surfaces and labels;
the setting's enabled switch carries the crimson fill. Float the keyboard over
the whole app Navigator, centered at the bottom, with no full-width strip behind
it. Keep the catalogue and rail painted and interactive beside it. Supply its
height as a keyboard inset so forms, sheets and dialogs avoid the keys.
Keep the whole panel within 37% of the window height (260dp at most),
including the bottom safe area. Derive its width from the available key height
and the standard four-row, ten-column letter layout, allowing character keys up
to twice as wide as they are tall. Include the 4dp column gaps and toolbar in
that width; cap it at the available window width and 900dp. Center the panel and
its surface together so
there are no empty side bands. At 1024×600 the English layout is 900×222, with
48dp-tall letter keys and 378dp above it. Use clearly visible 6dp gaps between
rows. In landscape windows, put Hide and Done/Search/Next in a 52dp side column.
In portrait windows, move these controls into a 48dp toolbar above the
keys so the keypad uses the full panel width. The toolbar stays within the
panel's height limit. Preserve keypad state when resizing changes the toolbar
position. Use tooltips and accessible labels; character labels are 20dp IBM Plex Sans.
Use the neutral sheet surface with rounded top corners. Slide up in 180ms and
down in 140ms without a backdrop or dismiss barrier. First let the phone or
tablet mini-player slide out; restore it only once the keyboard has closed.
This applies to catalogue text filters as well as main search and settings.
Skip both transitions with reduced motion, and do not wait for a bar that is
already hidden. Keep the catalogue and its results interactive above the keys.
Keep the field's focus while tapping keys or opening accent/language menus;
preserve the active field, draft and selection when resizing moves a catalogue
search between its toolbar and narrow-screen row. Resizing must not reopen a
keyboard the user has dismissed. Preserve formatters,
password masking, selection and field submit actions. Provide Hide and an explicit
Done/Search/Next action even on numeric layouts. Touches count as local kiosk
activity, and the blanking host covers both the app and keyboard.

Long-press accents use compact horizontal rows of at least 48dp character buttons,
wrapping on narrow screens without a scrollbar. Keep uppercase alternatives and
the field's selection intact. Outside tap or Escape dismisses the choices without
inserting a character; Escape leaves the keyboard open while a picker is showing.

Place an outlined globe key immediately beside Space. A tap opens a language
grid with all 16 layouts: four columns on smaller panes and five when the picker
is at least 800dp wide. Keep at least 48dp targets and 8dp gaps. Mark the current
layout with a check and neutral outline. The picker can extend above the keyboard
without enlarging it or dimming the app; retain field focus and selection. It
reflows when the window resizes. Use full language names normally, and short
language codes on narrow panes where names would break across lines. Large text
can reduce the column count to keep the codes readable; full names remain in
tooltips and accessibility labels. Never use a scrolling list. A
selection applies immediately; X, outside tap or Escape cancels it. Holding
Space remains an alternative way to open the same grid.

## Responsive layout and interaction

- Page titles wrap naturally with no ellipsis, fixed line limit, auto-shrink or capped text scaler. When the 18dp title scales above 27dp (1.5×), place it on a full-width second row **inside the same fixed header**, inset to the page gutter, with 10dp bottom padding plus the header’s 2dp outer padding. Back, the optional action and status stay on the first row. This avoids a narrow column of oversized text between icons.
- `SettingsPageIntro` stacks status and action below 320dp of **content width**, or when 14dp text scales above 18.2dp (1.3×). Otherwise status expands beside the action. Descriptions always use the full intro width.
- A device name in the top bar stays on one line beside the title: each keeps its own width while both fit, else the shorter keeps its width or each takes half, and the name ends in an ellipsis with its full text in a tooltip. When the title takes its own row at large text, the name keeps the first row's room before the switch.
- Use native `IconButton`/`TextButton` for header/toolbar actions, with a visible keyboard focus outline. Keep visual bounds stable on focus, hover and press. Button tooltips name the action; decorative icons are excluded from semantics.
- Mark the page title as a semantic header. Give the connection dot a readable status tooltip and an accessible label containing the current server name and status. Colour alone is insufficient. The dot is not a button.
- Keep destructive confirmation and pending-change behaviour intact. Layout changes must not initiate a restart, update, download or power-off.
- Respect safe areas and the host's mini-player allocation. Lists scroll within the remaining height. Avoid placing fixed elements over the list.
- Panel motion uses `kSlideInPanelDuration` (320ms, cubic 0.4/0/0.2/1); skip the slide when the system disables animations, and where Settings is switched to as a destination (from the rail or Customise Home). Header interactions add no movement or layout shifts.

## Implementation and verification

Reuse `SettingsTopBar`, `SettingsToolbar` and `SettingsPageIntro`; do not create another private header in a screen. `ConfigurationAppearance` supplies shared gutters and section spacing. The common `SlideInPanel` owns Back and panel transitions.

For changes to this system, check 375dp phone, narrow 320dp, landscape and tablet-panel layouts; normal, 2× and large system text; reduced motion; long plugin/device names; connected and disconnected states; keyboard Back and About; and pending edits on return. Verify the logs options/prepare/save flow and renderer Expert mode still work. Review actual rendered screens with bundled fonts in addition to widget assertions. These checks validate the changed settings surfaces; they are not a claim of an app-wide accessibility audit.

Reference: [UI/UX Pro Max skill](../../../.codex/skills/ui-ux-pro-max/SKILL.md), especially its `references/pro-rules.md` and accessibility, interaction and typography priorities. The repository tokens and shared widgets are the implementation source of truth; update this document with them when the design changes.


## Receiver connections

Mobile **Connect** belongs in the existing music-source strip. Wide layouts
show one **Connect** button with the same icon in the sidebar, opening a compact
anchored popup with the same content as Home's Connect. Collections follows the
last music source, then a subtle divider and Connect, without a CONNECT section
heading. Keep the Connect button even with only one enabled receiver.
Show installed, enabled receivers only, independently of
catalog availability. There is no dedicated Bluetooth header action, large
Home connection row, or duplicated renderer picker. Enable/disable stays in
plugin Settings.

The sidebar popup has a small pointer toward the centre of its Connect button,
drawn as part of the same neutral surface and border. Keep the popup within the
screen and move the pointer along its edge when height requires shifting it.
Reveal it from the button outward over 180ms with an ease-out curve and subtle
fade, matching More's shelf; clip the reveal so the content never compresses or
reflows. Closing takes 120ms and can be interrupted by reopening. Reduced motion
shows and hides it immediately. Preserve outside-tap and Escape dismissal and
return keyboard focus to Connect after keyboard dismissal. Pointer dismissal
clears its focus. Connect's grey highlight follows the popup's open state only;
hover and restored keyboard focus do not fill it, and keyboard focus uses a
separate outline.

The compact sheet shows actual receiver names and sessions. Bluetooth renders
**Bluetooth · Pair new**, followed by a separate Paired devices group; no expansion or
separate audio-permission switch. Pair new uses the shared compact primary
`KalinkaButton`, with its berry fill and pill shape. Pair opens the backend's two-minute Just Works
window. The sender may show its normal pairing prompt, but Kalinka needs no
comparison code or second approval. The backend countdown appears beside Bluetooth while pairing is open. A compact
Stop pairing action sits beside it. The countdown uses a monotonic deadline per
window and ticks at each second boundary between backend updates. Delayed
snapshots do not extend the window or restart the tick phase. Closing the sheet
leaves pairing running.
Successful pairing grants audio access automatically. Device rows show an icon, name and Paired/Connected status, with a green dot
for connected audio. Each row has a vertical ellipsis menu with **Disconnect** for an
audio session and **Forget** for the bond. Use a generic device icon until the
server supplies a device type. Forget requires confirmation: it removes shared setup
pairing too, keeps Wi-Fi configuration and requires re-pairing. Leave 16dp before
the paired-device label and 8dp before its rows. Align a custom receiver name
under the receiver title, keeping it separate from the devices. Device names
wrap at large text sizes.
Use `KalinkaDialog` and shared buttons: centered in the whole window with a dimmed background at every width. Cancel is neutral and gets
initial keyboard focus. Forget uses the berry action style. Keep the message
short: "Removes the Bluetooth pairing. Pair again to reconnect."

Separate the panel introduction from the first receiver by 20dp, and put 20dp
on either side of the divider between receivers. Receiver failures, failed
actions and inventory errors use the shared `FailureNote`, with an error icon,
readable wrapped text and live-region semantics, 12dp below the related controls.
Show the backend error once instead of repeating a generic unavailable line.
Keep any reported paired devices visible and respect the backend's action
availability even when the module reports an error. An unavailable backend can
return an empty peer list without deleting its bonds: show **No paired devices**
in `textMuted` only when the receiver is ready and inventory is available.
Hide that empty-state message during errors, startup and shutdown. AirPlay's
password status is shown only while its receiver state is available and ready.

The generic app-wide approval host remains available for controllers which
actually publish a pending request. It preserves supplied comparison codes,
explicit decisions and backend cancellation/expiry, including when the panel
is closed. The current Just Works controller publishes no such requests.
Commands are never automatically replayed after a timeout.

AirPlay is one row with its icon, title and password status. Without a password,
show **No password required**. When reveal is allowed, show **Password required -
click to reveal** with a downward chevron. Tapping the row reveals the password
in large monospace text directly below it. Tapping again hides it. Do not add
instructions or a separate Show password button. Keep custom receiver names
visible. Unavailable receivers must not offer a reveal action.
Password application uses the existing secret setting; its help warns that
applying it restarts AirPlay and ends its session. Revealed text is discarded
and pending reveals are invalidated as soon as closing starts, including when
the exit animation is interrupted by reopening. Also discard it on
backgrounding, lost availability or removal of the password. These
surfaces reuse the existing theme, text styles and responsive spacing.

Receiver operations use a spinner in the existing control bounds. AirPlay replaces
its password chevron while fetching. Bluetooth replaces the affected device's
ellipsis during Disconnect or Forget. Pairing uses the Pair new or Stop pairing
control's space. Loading indicators must not add a row or change the panel size.
