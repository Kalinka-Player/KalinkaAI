# Kalinka Palette

High-contrast grayscale with **berry** & **brass** accents. Source of truth: `KalinkaColors` in [lib/theme/app_theme.dart](lib/theme/app_theme.dart).

Flutter colors are `0xAARRGGBB`. Below they're translated to CSS: opaque values as `#RRGGBB`, alpha values as `rgba()` (with the source alpha byte noted).

## Backgrounds

Six-step depth scale — each level sits above the previous. Use the shallowest level that creates visible separation from its parent.

| Token | Hex | Usage |
|---|---|---|
| `background` | `#080808` | Page canvas — near-black, behind all surfaces |
| `surfaceBase` | `#0E0E0E` | Header · tab bar · bottom sheets |
| `surfaceRaised` | `#151513` | Cards · queue rows · mini-player |
| `surfaceInput` | `#171715` | Input fields · search bar · chips |
| `surfaceElevated` | `#1C1C1A` | Pills (unselected) · toggle off · nested |
| `surfaceOverlay` | `#222220` | Hover · pressed · active row tint |

A surface may also be spread as a *wash*: a gradient that lifts a region out of the canvas and dies inside it, marking where a section begins without a rule or a box. See *Atmosphere is neutral* under [Fill or outline](#fill-or-outline).

## Borders

Pure white alpha — clean neutral separation.

| Token | RGBA | Usage |
|---|---|---|
| `borderSubtle` | `rgba(255,255,255,0.07)` | Dividers · card edges · row separators |
| `borderDefault` | `#323235` | Controls · inputs · chips · sheet rules |

## Text

Near-white on near-black — maximum contrast.

| Token | Hex | On `background` | Usage |
|---|---|---|---|
| `textPrimary` | `#FAF5F0` | 18.5:1 | Track titles · labels · values |
| `textSecondary` | `#A3A3A3` | 7.9:1 | Subtitles · metadata · chip labels |
| `textMuted` | `#858585` | 5.4:1 | Section chrome · drag handles · inactive icons |
| `textSectionLabel` | `#B0B0B0` | 9.2:1 | Queue section headers |
| `frost` | `#EEEEEE` | 17.3:1 | Playfair Display headings only (titles) — not body/mono |

## Accent — Kalinka Berry

Primary interactive accent — deep natural red of guelder-rose berries. Active states, progress, selected indicators. Use sparingly — max 2 tinted surfaces at once; [Fill or outline](#fill-or-outline) decides which treatment a control gets.

| Token | Value | Usage |
|---|---|---|
| `accent` | `#C2394B` | Toggle on · progress · active dot |
| `accentTint` | `#D8556A` | Bright berry · labels on accent surfaces |
| `accentFaded` | `#250708` | Disabled buttons · inactive pills |
| `accentBright` | `#F59299` | Text/icons on `accentFaded` only |
| `accentSubtle` | `rgba(194,57,75,0.08)` | Now-playing row · active pill bg |
| `accentBorder` | `rgba(194,57,75,0.40)` | Focused inputs · selected cards |

### Fill or outline

Berry has two treatments, and which one a control gets is not a matter of taste.

**Fill** — `accent` background, `textPrimary` label — marks *where the decision is being made*: the active `SettingsEnumPills` segment, a selected chip inside the filter card, `SettingsToggle` on, the primary `KalinkaButton`. Fill is what makes one chip findable among twenty.

**Outline** — `accentSubtle` fill, `accentBorder` edge, `accentTint` label — marks *the one a set leads with*, or the thing the app is doing right now: `ActionPillButton(accent:)`'s Play all beside a plain Enqueue, the now-playing row tint (the bars beside its duration stay grey, `textSecondary`, as motion needs no hue to be seen). It reads as "this one", not "pick me".

**A receipt is grey.** What a decision left behind is chrome, not signal — applied-filter chips above a listing, the search-and-filters pill while filters are on — and it gets `surfaceElevated` fill, `borderDefault` edge, `textPrimary` label, lightening to `surfaceOverlay` / `textMuted` under the pointer. The one thing a receipt may carry in berry is a **count**: the filter pill's badge is a number, which says how many rather than merely that there are any, and a number is too small to shout. (Revised 2026-09-09: the chips and the lit pill were both outlined, and three berry-edged things in one title bar left berry meaning nothing in particular.)

**Atmosphere is neutral.** A *wash* — a surface colour spread as a gradient and dissolved back into the canvas inside the height of the thing it hangs off — colours a region instead of marking a control, so it can say *a different kind of section starts here* without claiming a decision. It is drawn in the depth scale, never in berry: the Inspired block's heading sits on `surfaceElevated` rising out of `background` and gone by the heading's foot, edge to edge, the only thing marking where that block begins. Its voice comes from typography, and its link to the search entry is the sparkle, not a hue. The one berry atmosphere is the Discover root's bloom, on the surface where the app is being asked. (Revised 2026-09-11: the heading carried that bloom at a section's scale, two rows above the berry now-playing row, and the two read as one signal. The wash went grey; berry is back to two treatments.) Anything with an edge you can point at is a mark, and takes the two rules above instead.

The same value takes both treatments depending on where it is drawn, and that is the rule working rather than an inconsistency: a genre chip is filled inside the filter card, where you are choosing it, and grey in the header of the listing it produced, where it is a receipt you keep looking at.

Duration settles what the first test leaves open. Berry is loud — a surface you look at for four seconds while choosing can afford it; chrome that stays on screen for a whole session cannot. That is why the filter pill holds genuine state and is still grey.

**The budget:** a screen at rest carries at most one crimson fill. A decision surface — a filter card, a dialog — is not at rest, and inside it fill is the vocabulary of choosing.

## Accent — Warm Brass

Secondary signal for streaming/external content — gold-plated connector warmth.

| Token | Value | Usage |
|---|---|---|
| `gold` | `#CDC9BE` | Tinted ivory · streaming module · progress end (reads as warm white) |
| `goldSubtle` | `rgba(205,201,190,0.09)` | Streaming module tile bg |

**Progress gradient:** linear `accent → gold` (`#C2394B → #CDC9BE`).

## Semantic — Status

Three states only: online, pending, error. Leaf green for "online" — guelder-rose leaves, alive in winter.

| Token | Value | Usage |
|---|---|---|
| `statusOnline` | `#3D8A58` | Leaf green · connected · success |
| `statusPending` | `#C8943A` | Amber · staged · reconnecting |
| `statusOffline` | `#858585` | Offline |
| `statusOnlineSurface` | `rgba(61,138,88,0.10)` | Badge bg · done step |
| `statusPendingSurface` | `rgba(200,148,58,0.09)` | Pending banner bg |
| `statusOfflineSurface` | `rgba(200,68,68,0.07)` | Error badge bg · warning note |
| `statusPendingLight` | `#E8B86A` | Text/icons on `statusPendingSurface` only |

## Semantic — Actions

Destructive and confirmatory actions in interactive controls.

| Token | Hex | Usage |
|---|---|---|
| `actionDelete` | `#C84444` | Swipe-to-delete · remove button · destructive CTA |
| `actionConfirm` | `#5AAE78` | Confirm · apply · positive CTA |

## Typography

| Role | Family | Notes |
|---|---|---|
| Sans | `IBM Plex Sans` | UI / body |
| Mono | `IBM Plex Mono` | Monospace content |
| Display | `Playfair Display` | Headings / titles only |

### Home catalog headings

Home shelf headings use `ShelfHeading`: uppercase `IBM Plex Mono` through `KalinkaTextStyles.sectionLabel`, weight 600, 1.5dp letter spacing and `textPrimary`. This is the shared treatment for **YOUR COLLECTIONS**, **BROWSE SOURCES** and the headings for Cards and List previews. Keep large-text wrapping; individual pinned headings omit the divider while other shelves retain their usual divider. Pinned previews follow the source tiles directly, without an overall **PINNED CATALOGS** heading.

Source tiles sit under **BROWSE SOURCES**, above the pinned previews. Show the source icon, source name in `trackRowTitle`, and navigation chevron. Do not show input-module descriptions or subtitles.

Use the shared Home spacing constants: 32dp between major sections (including after the search entry), 12dp between a shelf heading and its content, and 32dp of bottom scroll padding. Apply the same spacing to loaded and loading states. Keep each section’s internal labels and metadata close together.

Place **Customise Home** after the final pinned preview, centered within the content panel with 32dp of separation. Use a neutral outlined capsule button: sentence-case IBM Plex Sans at 14dp, `textSecondary` text and 18dp tune icon, `borderDefault` outline, and a minimum 48dp touch target. Use the shared hover/press overlay and a brighter neutral outline for keyboard focus. Allow the label to wrap at large system text sizes. Do not use berry, uppercase link styling or a trailing arrow for this secondary management action. Hide the footer when no catalogs are pinned.

Cards and List preview headings have two text levels: the title and the pinned BrowseItem's saved description. Show the plugin's declared source icon to the left of the title, using the shared source colour and a generic library icon when none is declared. The icon provides source attribution; do not add a separate source/filter text line. Omit missing descriptions and descriptions identical to the title. Unavailable sources show Unavailable in the description's place. The trailing **VIEW ALL** action opens the saved catalog and filters. The management action belongs to the centered Home footer; **VIEW ALL** belongs to each catalog's heading.

Compact previews use the same `CatalogTile` and responsive `CatalogTileGrid` as sources: a 12dp rounded tile, source icon, catalog name in `trackRowTitle`, source/filter metadata in `trackRowSubtitle` and a trailing navigation chevron. Tint the surface with the existing `SourceDisplayInfo.color` at 14% over `surfaceRaised`, and its border at 30%; keep text in the shared neutral colours for readability. Never add plugin-specific colour rules. Compact has no separate shelf heading or content preview and opens the saved catalog/filters directly. Adjacent Compact pins wrap with 8dp gaps; other preview types break the group so pin order is preserved. All tiles within a source grid or contiguous Compact group use equal widths and the height of the tallest wrapped tile, including the final incomplete row. Center each tile’s content vertically and keep its full surface tappable. Recalculate the shared height when width, content or system text size changes. Disabled sources retain their tile with an Unavailable label and no navigation action.

The catalog page's Pin action uses a 20dp outlined pin in a minimum 48×48dp target. When that catalog and filter selection are already pinned, show the matching crossed-out pin with the tooltip and accessible name **Unpin catalog**; pressing it removes that pin. An unpinned selection shows **Pin catalog to Home**.

Artwork has no separate section heading or **VIEW ALL** action. Place its catalog title, source icon and optional description inside the card as a vertically centered, left-aligned group. Do not add card shadows or dark gradient overlays. Use Playfair Display through `KalinkaTextStyles.blockTitle` for the title, preserving the catalog’s original casing. At a card width of 400dp, use 85% of the shared title and subtitle sizes (22.1dp and 10.2dp respectively). Scale both fonts, the source icon, padding and gaps proportionally to the actual card width above 400dp; retain the base sizes on narrower cards for readability. Respect system text scaling in addition to card scaling. Keep the description in normal IBM Plex Sans through `trackRowSubtitle`, with `textSecondary` so it stays readable over artwork. Omit missing or repeated descriptions; show Unavailable on the card when the source is unavailable. The entire available card opens the saved catalog and filters. Let the caption wrap and the card grow at large text sizes. The image follows the decoded image's native aspect ratio, without cropping or a square frame. While loading, use a valid `preview.aspect_ratio` hint, falling back to 3:1 (the generated catalog artwork format). Allow the available panel width and cap the image height at 320dp, so portrait artwork remains proportional.

Home loading placeholders use the shared `ShimmerPulse` and `ShimmerBlock`: `surfaceOverlay` shapes, a 1400ms ease-in/out opacity pulse from 0.55 to 1, and static placeholders when reduced motion is enabled. Match the content being loaded: collection rows, source/Compact tiles in `CatalogTileGrid`, horizontal Cards rails, vertical List rows and proportioned Artwork. Source placeholders use the number of catalog-capable modules once known and disappear when there are none. Keep saved pins in their loading state until module capabilities resolve; do not flash Unavailable. Use the same placeholders during image decoding, retaining existing image-error fallbacks. Home sections must not use full-width progress bars.

### Customise Home

Use the shared `SettingsTopBar` and settings typography: a single IBM Plex Sans page title, a quiet introduction, and compact catalog rows separated by subtle rules. Align content to the settings gutters (20dp on phone, 25dp on tablet). Rows show the catalog name, source/filter metadata and current preview label, with a 48dp drag handle, preview icon and Unpin action. The preview icon sits immediately to the left of Unpin. Both row actions use `kalinkaIconButtonStyle`: circular 48dp targets and the shared subtle `kalinkaOverlay` hover/press highlight. Keep the native keyboard focus feedback; do not apply the settings header’s white focus border to these menu controls. Use a 20dp crossed-out pin in a minimum 48×48dp target, with the tooltip and accessible name **Unpin [catalog name]**. Preview content stays on Home. Host this screen in the tablet right panel, leaving playback on the left interactive; use the full screen on phones and preserve the open panel across resizing.

The preview icon opens an anchored dropdown overlay containing a single bar of four icon buttons: Cards (`view_carousel_outlined`), Artwork (`image_outlined`), List (`view_list_outlined`) and Compact (`view_agenda_outlined`). Use the shared icon mapping from `homePreviewIcon`. Use the same round icon-button treatment for the choices. Highlight the active button with crimson `accent` fill, a contrasting icon and selected semantics. Show the active preview's name and description underneath the icon bar. Choices save immediately and keep the overlay open; dismiss it after three seconds without interaction, restarting that timer on selection, pointer activity or keyboard interaction. Outside taps, Escape and Back dismiss it; Back closes the dropdown before closing the screen. All icon targets are at least 48dp and have accessible labels.

Unpin opens a centered `KalinkaDialog` confirmation (`centered: true`) with the catalog name and **Cancel** / **Unpin** actions. Remove the catalog only after confirmation; cancelling, tapping outside or going back leaves it pinned. Center the dialog within the right panel on tablets and within the screen on phones. Use a fade-in rather than a bottom-sheet slide. Reordering uses the drag handle and the list’s built-in accessibility actions. Initial pinning keeps the shared `HomePreviewChoices` bottom sheet, using the same icons and descriptions.
