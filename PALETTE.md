# Kalinka Palette

High-contrast grayscale with **berry** & **brass** accents. Source of truth: `KalinkaColors` in [lib/theme/app_theme.dart](lib/theme/app_theme.dart).

For the target navigation model, adaptive player/browsing layout, grids and wide lists, follow the [browsing design guide](docs/browsing-design-guide.md). The palette and detailed Home control rules below remain its visual foundation.

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

**Outline** — `accentSubtle` fill (laid on `background` where it is a pill, so it reads the same over a page's art), `accentBorder` edge, `accentTint` label — marks *the one a set leads with*, or the thing the app is doing right now: `ActionPillButton(accent:)`'s Play all beside a plain Enqueue, the now-playing row tint (the bars beside its duration stay grey, `textSecondary`, as motion needs no hue to be seen). It reads as "this one", not "pick me".

**A receipt is grey.** What a decision left behind is chrome, not signal — applied-filter chips above a listing, the Filters pill while filters are on — and it gets `surfaceElevated` fill, `borderDefault` edge, `textPrimary` label, lightening to `surfaceOverlay` / `textMuted` under the pointer. The one thing a receipt may carry in berry is a **count**: the filter pill's badge is a number, which says how many rather than merely that there are any, and a number is too small to shout. (Revised 2026-09-09: the chips and the lit pill were both outlined, and three berry-edged things in one title bar left berry meaning nothing in particular.)

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

Home shelf headings use `ShelfHeading`: uppercase `IBM Plex Mono` through `KalinkaTextStyles.sectionLabel`, weight 600, 1.5dp letter spacing and `textPrimary`. This is the shared treatment for **YOUR COLLECTIONS**, **MUSIC SOURCES** and the headings for Cards and List previews. Keep large-text wrapping. Every shelf heading, pinned ones included, runs a subtle divider from its title to its **View All** (or to the end of the row), dropped where large text needs the room. A heading's **View All** is a small neutral link, not a second title: sentence-style IBM Plex Sans at the base size, weight 500, `textSecondary` with a chevron, lifting to `textPrimary` with a hand cursor under the pointer, with a little room beside it but none above, so the heading's row keeps the title's height and the subtitle sits 4dp under it. Pinned previews follow the sources with no group heading, 24dp apart. With no pins, the group is simply absent: Home shows no customisation banner.

Home’s music sources are one line of names under the search prompts, the way into the music for a new listener: 16dp IBM Plex Sans in `textSecondary`, lit to `textPrimary` on a `surfaceOverlay` pill under the pointer, focus or press, each a 48dp target, with no icon, description or chevron. The line is centred while it fits, else it scrolls sideways out to the pane's edges and fades at them, as the prompts do. The line shows only without the rail; where the rail shows, it lists the sources and Configuration instead, and Home drops the whole line, gear included. It ends with a neutral 20dp outlined gear in Kalinka’s round 48dp icon button, labelled **Configure music sources**, which opens Configuration’s **Music sources** tab through the existing shell, using the browsing pane on wider layouts and preserving Home on return; show it when Configuration is available, using the same server capability check as the server menu. Opening a source from the line folds the hero (artwork, heading, search entry and prompts) up under the bar while its backdrop fades, so the line rises, then the source’s page opens down from the bar into the area; with reduced motion it opens at once. Customise Home keeps the source tiles under **MUSIC SOURCES**: source icon, name in `trackRowTitle` and navigation chevron, without descriptions or subtitles.

Use the shared Home spacing constants: 32dp between major sections (including after the search entry), 12dp between a shelf heading and its content, and 32dp of bottom scroll padding. Apply the same spacing to loaded and loading states. Keep each section’s internal labels and metadata close together.

Home’s bar stays clear at rest; once the page scrolls under it, it shades from opaque `background` at the top of the status area to clear at its own foot, so the page shows through. Home’s top carries no artwork for now: only a subtle crimson radial bloom (`accent` at 26% fading to nothing) centred behind the search entry, reaching about 200dp up and down so the question above it and the prompts under it sit inside it too (faint by the bar), and across past a phone's sides, never wider than 1.3 times the entry's 575dp each way. It follows the list, including when turning the phone moves it. **What shall we play?**, the search entry, the smart-search note and the curated prompts sit centred under it, without an introductory description, followed by the line of sources, 12dp under the prompts and 16dp above what follows. The note under the entry names what smart search covers as one line: **Smart search · My Library · Jamendo**. Collections follow once there is at least one, then pinned previews. Show the collections **View All** action only when the reported total exceeds the number of visible collection rows. Playback information and controls remain in the player.

Keep the search entry and composer at most 575dp wide, centred; the curated prompts under it are 40dp high, never taller than the entry, and run on one line across the pane: centred while they fit, else scrolling sideways right out to the pane's edges as Home's rails do, each side fading over 32dp as far as there is more to scroll that way. Source tile text, icons and padding grow by at most 10% with tile width; system text scaling remains independent and labels wrap.

The left navigation rail is 88dp wide from a 720dp window at least 480dp tall (none on a phone turned on its side), with each label under its icon. From a 1280dp window it widens to 200dp, growing with text up to 1.3× (it stays narrow beyond that), and sets each icon beside its full name; below that, or above 1.5× system text size, keep the existing Home, Back and server-menu navigation, without a drawer or hamburger button. Use labelled 24dp rail icons for Home, Results and the available music sources, then **Collections** 8dp below the sources where the server keeps collections, with Configuration at the bottom when supported. Collections opens the Collections screen that Home's **View All** leads to, and is the current destination on that screen and on any collection; Home then shows no **YOUR COLLECTIONS** section. Below it, after a divider, the server’s own controls: **Restart** (the streamer) and **Power off** where the streamer offers them, and **Change server** except on web. Restart and Power off are neutral commands with no selected state; Change server is a destination: while the server picker shows it is marked as current, however the picker was opened, and choosing any other destination leaves the picker as its **Cancel** does, then goes there (with no saved server the picker cannot be cancelled, and the rail stays disabled). They confirm through the same dialogs as the server menu, and stay at the rail’s foot unless the window is too short, when the whole rail scrolls. These source shortcuts and Home's source tiles open the same destinations. The current destination sits on a neutral `surfaceOverlay` rounded rectangle, its icon and label in `textPrimary` (others `textSecondary`), with no berry: the rail is chrome on screen all session (see [Fill or outline](#fill-or-outline)). The highlight fades in over 180ms, at once with reduced motion. Each item keeps 6dp in from the wide rail's sides and 4dp from the narrow rail's, with 12dp corners, 4dp from its neighbours on the wide rail and 6dp on the narrow one; hover lifts any other item to `surfaceInput` and focus or press to `surfaceOverlay` in the same shape, and the current destination takes no hover, shows no hand cursor, and choosing it again does nothing. A narrow rail's item is only as tall as its icon and label, 8dp above and below inside its highlight and never under 48dp, so the usual destinations fit a 1024×600 window without scrolling. With the rail, Configuration has no Back at its top level — another destination leaves it — while the system back returns to the destination it was opened from. Keyboard focus uses a 2dp `textPrimary` outline, and destinations retain selected semantics. Preserve stable control bounds and 48dp minimum targets.

Rail labels use 12dp IBM Plex Sans and wrap without truncating source names. Use **Config** as the compact Configuration label and **Results** for Search results; retain full names in tooltips and accessibility labels. The wide rail shows the full names in 16dp IBM Plex Sans, and keeps a tooltip only where it adds to the name, as Results’ query does. **Results** reopens the last search with its existing query and filters, without another request, and remains disabled until a search has run. Its tooltip includes the query when available. On layouts without a rail, show a 48dp **Back to search results** icon action in Home's header only after a search exists. Configuration stays in the server menu and sources stay on Home. Start new searches from Home's search entry; do not add a return-to-results banner above it.

After the last pinned preview, against the trailing edge, a quiet line offers the change: **Want Home to look different?** in `textMuted`, then a neutral **Customise Home** text button with an 18dp tune icon in `textSecondary`, a 48dp target with standard hover/press and keyboard focus. The two wrap, still right-aligned, when they do not fit. Show it only when at least one catalog is pinned; it is the single action for the whole pinned group.

Cards and List preview headings have two text levels: the title and the pinned BrowseItem's saved description. Show the source's tile (`SourceTile`, 20dp, its declared icon or letter in the source colour) to the left of the title, in place of a pin. The tile is the source attribution; the source's name is not repeated in the description line, which holds the saved filters and description only. Omit missing descriptions and descriptions identical to the title. The description lines up with the title, past the source icon before it, not with the icon. Unavailable sources show Unavailable in the description's place. List preview rows use a right-pointing chevron; both the row and chevron open the item’s page, without inline expansion. The trailing **View All** action opens the saved catalog and filters. The management action is the line after the pins; **View All** belongs to each catalog's heading.

Compact previews use the same `CatalogTile` and responsive `CatalogTileGrid` as sources: a 12dp rounded tile, source icon, catalog name in `trackRowTitle`, source/filter metadata in `trackRowSubtitle` and a trailing navigation chevron. Tint the surface with the existing `SourceDisplayInfo.color` at 14% over `surfaceRaised`, and its border at 30%; keep text in the shared neutral colours for readability. Never add plugin-specific colour rules. Compact has no separate shelf heading or content preview and opens the saved catalog/filters directly. Source and Compact tiles require at least 240dp per column before system text scaling, and a single column fills the available width. Multiple Compact columns retain the 260dp scaled width cap. Adjacent Compact pins wrap with 8dp gaps; other preview types break the group so pin order is preserved. All tiles within a source grid or contiguous Compact group use equal widths and the height of the tallest wrapped tile, including the final incomplete row. Center each tile’s content vertically and keep its full surface tappable. Recalculate the shared height when width, content or system text size changes. Disabled sources retain their tile with an Unavailable label and no navigation action.

The catalog page's Pin action uses a 20dp outlined pin in a minimum 48×48dp target. When that catalog and filter selection are already pinned, show the matching crossed-out pin with the tooltip and accessible name **Unpin catalog**; pressing it removes that pin. An unpinned selection shows **Pin catalog to Home**.

Artwork has no separate section heading or **View All** action. Place its catalog title, source icon and optional description inside the card as a vertically centered, left-aligned group in the card's left 60%, the side catalog art keeps dark. Do not add card shadows. So the caption reads where a cover in the art runs beneath it, a dark gradient holds the card's left side under it, 80% black at the edge, 70% at 35% of the width and 35% at 55%, gone by 75%, and its text carries a dark shadow, a tight edge round each glyph and a softer one under it. Use IBM Plex Sans through `trackRowTitle` for the title, the title album cards carry, preserving the catalog’s original casing. At a card width of 400dp, set the title at 22dp and the subtitle at 14dp. Scale both fonts, the source icon, padding and gaps proportionally to the actual card width above 400dp; retain the base sizes on narrower cards for readability. Respect system text scaling in addition to card scaling. Keep the description in normal IBM Plex Sans through `trackRowSubtitle`, with `textSecondary` so it stays readable over artwork. Omit missing or repeated descriptions; show Unavailable on the card when the source is unavailable. The entire available card opens the saved catalog and filters. Let the caption wrap and the card grow at large text sizes. The card is 3:1, never shorter, as wide as the panel up to 960dp, so about 320dp tall at most. The art's shape comes from its image's `aspect_ratio`, which describes the large image a card draws, never from `preview.aspect_ratio`, which describes a catalog's children. Art of the card's 3:1 shape covers it; any other shape sits whole on the right of the drawn card (see [Catalog art](#catalog-art)), inset by 12% of the card's height and taking at most 40% of its width, with corners 5.5% of its height, as the server sets album covers on its own cards. Art without a stated ratio is taken for a square.

Home loading placeholders use the shared `ShimmerPulse` and `ShimmerBlock`: `surfaceOverlay` shapes, a 1400ms ease-in/out opacity pulse from 0.55 to 1, and static placeholders when reduced motion is enabled. Match the content being loaded: collection rows, source/Compact tiles in `CatalogTileGrid`, horizontal Cards rails, vertical List rows and proportioned Artwork. Source placeholders use the number of catalog-capable modules once known and disappear when there are none. Keep saved pins in their loading state until module capabilities resolve; do not flash Unavailable. Use the same placeholders during image decoding, retaining existing image-error fallbacks; catalog art shows its drawn card instead. Home sections must not use full-width progress bars.

### Customise Home

Use the shared `SettingsTopBar` and settings typography: a single IBM Plex Sans page title, a quiet introduction, and compact catalog rows separated by subtle rules. With no pins, show brief instructions and source tiles in Customise Home so the listener can browse to a catalog and pin it. Opening a source dismisses the customisation panel and reveals that catalog. With pins, the scrolling introduction is text only: **Drag catalogs to reorder.** followed by **Search, collections and sources stay in place.** Use `settingsDescription`, 20dp vertical padding and a full-width 1dp `borderSubtle` separator beneath it. Align content to the settings gutters (20dp on phone, 25dp on tablet). Rows show the catalog name, source/filter metadata and current preview label, with a 48dp drag handle, preview icon and Unpin action. The preview icon sits immediately to the left of Unpin. Both row actions use `kalinkaIconButtonStyle`: circular 48dp targets and the shared subtle `kalinkaOverlay` hover/press highlight. The preview trigger highlights only on hover or press, with an explicitly transparent idle/focused overlay and no menu-open fill; keyboard activation remains available. Do not apply the settings header’s white focus border to these menu controls. Use a 20dp crossed-out pin in a minimum 48×48dp target, with the tooltip and accessible name **Unpin [catalog name]**. Preview content stays on Home. Host this screen in the tablet right panel, leaving playback on the left interactive; use the full screen on phones and preserve the open panel across resizing.

The preview icon opens an anchored visual layout picker: Cards, Artwork, List and Compact. Each choice shows the same locally drawn geometric layout illustration used in the Pin sheet, with its name underneath. Use four columns when the available panel width and text size allow, otherwise two; constrain the menu to its panel and allow scrolling on short screens. Mark the selected layout with a crimson `accentTint` outline, subtle accent surface and a filled crimson checkmark. This outline-and-check treatment belongs to the illustrated choices; it preserves the artwork's readability while making the choice clear without colour alone. Keep other choices neutral. Give all illustrated picker choices 16dp of vertical padding and 6dp horizontally, keeping the selected outline clear of the artwork and all four choices aligned. The trigger retains its round shape and highlights only on hover or press, including while its menu is open or it retains focus after dismissal. Choices save immediately and keep the overlay open; dismiss it after three seconds without interaction, restarting that timer on selection, scrolling, pointer activity or keyboard interaction. Outside taps, Escape and Back dismiss it; Back closes the picker before closing the screen. Every choice is a native button with its name, description and selected semantics, keyboard focus feedback and at least a 48dp target. Use the shared `homePreviewIcon` mapping for row triggers only; layout examples are decorative and need no image requests.

Initial pinning opens **Pin to Home**, a bottom sheet with the catalog name, a reminder that current filters are saved, **Choose a preview**, and four rounded outlined option rows. Each row pairs a geometric preview on the left with its name and short description on the right. Use IBM Plex Sans, semantic neutral surfaces, subtle borders and no added card shadows. Keep the title at the shared 18dp size and illustrations at most 120dp wide. The scrollable body grows to its content, capped at 560dp or the available height, so large windows do not enlarge this short decision. Compact examples use the source's declared colour. The footer says **Tap a layout to pin it.** Selecting a row pins immediately; Close or dismissing the sheet leaves Home unchanged. On tablets, anchor the sheet to Home's right panel, tracking its bounds during resizing; taps beside it dismiss it. Keep scrolling available for landscape screens and large text.

Unpin opens a centered `KalinkaDialog` confirmation (`centered: true`) with the catalog name and **Cancel** / **Unpin** actions. Remove the catalog only after confirmation; cancelling, tapping outside or going back leaves it pinned. Center the dialog within the browsing pane on wider layouts and within the screen on phones. Use a fade-in rather than a bottom-sheet slide. Reordering uses the drag handle and the list’s built-in accessibility actions. Pinning and layout changes share `HomePreviewIllustration` and the same layout names and descriptions.

### Catalog page headers

Catalog and playlist pages keep the Playfair identity compact, with Pin immediately beside the title and attribution 4dp below it. Leave 8dp between the top bar and identity, and 8dp before a control row below it. In the bar, Search, Filters and Grid/List are 40dp round pills in 48dp targets, with 12dp more before Grid/List; where the bar has room, the search is a field at most 360dp wide. Grid/List is the top bar's, last before the server chip on every catalog page however far it has scrolled. Use 16dp side gutters, with no divider between the grouped header and the content, and no separate control row below it. Filters is the top bar's from the first frame, as on results; after the identity collapses, its title appears beside Back using the standard uppercase mono top-bar style, and Pin moves with the title into the top bar. Omit that top-bar title while expanded and return Pin beside the large title on scrolling back to the top. Each Grid/List choice has a 48dp target (one round button switching to the other view under 600dp), with `surfaceOverlay`, a `textMuted` outline and `textPrimary` icon distinguishing the selected view. Use 10dp outer corners for Grid/List, Search and Filters. Pin remains a neutral 48dp icon action. Search and Filters use neutral outlined surfaces and at least 48dp targets; grow with system text size. Filters stage facet changes, while search applies on Enter. Keep existing semantic colors and native hover, focus and cursor feedback.

Applied chips beside an inline catalog search omit the duplicate query. Use quiet 13dp secondary text in a 32dp visual pill, with 48dp touch targets, keyboard activation and full-label tooltips. Place **Clear filters** immediately after the chips in the same wrapping group. It clears facets while preserving the search text. Keep long chips within the available width.

Catalog track rows show the artist, falling back to the album artist and then **Unknown artist**, without a repeated **Track** label. Align column headings and cells with shared widths and 16dp gaps; omit vertical separators. Keep existing subtle horizontal separators. Track Album columns start at 720dp of row width, with at least 200dp of cell width, Artist at 1000dp, and Source at 1200dp where relevant; scale these thresholds with text size. Below the Album threshold, catalog rows keep just the artist beneath the title and hide the album. Mixed search results retain their inline metadata.

Catalog grid cards are Home's Artwork card at grid width: 3:1 with the caption on the art and nothing under it, title and description at most two lines each. On cards narrower than 400dp the title shrinks to 80% of its 400dp size while the description keeps its size; the source badge leads the title where items need attribution. Give category cards at least 220dp of width per column before text scaling where the viewport allows it, and shimmer them as 3:1 blocks; album and playlist covers take the shape their shelf lays them out in, its `preview.aspect_ratio` (square when it declares none, as tall as the rail's other art in a Home rail), and artist portraits stay round. A cover whose own `aspect_ratio` matches covers its card; any other, a Qobuz editorial banner in a square shelf or a square cover in a banner shelf, is set inside whole, never cropped, over a soft fill of itself: the same image decoded 24px wide, stretched and darkened, with no blur pass and no backdrop filter. A shelf declaring wide covers takes the category column widths and shimmers in its shape. Rows keep the square thumbnail. In a catalog whose loaded items share the named source, omit repeated item source badges and the Source column. Mixed-source listings retain item attribution.

#### Catalog art

A catalog with no art of its own, or while its art loads or after it fails, wears a card drawn in the app (`CatalogArtPainter`) in the server's style without its album collage: a near-black wash rising to a key colour at the bottom right, soft concentric bands with a few satellites, and, under a caption, the left 38% held dark and eased out by 60%. The catalog's title picks the key from ten dark jewel tones at the server's key lightness (wine, plum, violet, indigo, petrol, teal, pine, olive, amber, rust), so a genre keeps its colour in every source; the title with the description places the bands. Wine sits well under `accent`, so a card never reads as a crimson fill. Seeds hash with 32-bit FNV-1a, so every client draws the same card. The card is gradient fills only, with no layer, blur or image, so it costs about what a row's procedural album art does. Rows and rail tiles lead with the catalog's thumbnail, which the server renders square: its card's background without the caption side, with the covers gathered to the middle. Without one, the drawn art fills the square the same way, with no side held dark. A square showing a card-shaped image, stated 2:1 or wider, crops it from 55% of the way across, past the caption's side; any other image is cropped from its middle.

### Now Playing queue preview

When the player's available content area is near-square or wider (width at least 80% of height), put the artwork on the left and the track details on the right with a 24dp gap. Left-align the title, artist, album and stream information. Put the renderer selector below the details, left-aligned and anchored to the bottom of the right column; centre the details in the space above it with at least 16dp clearance. Centre the artwork vertically when enlarged text makes this column taller than the cover. Reserve at least 200dp of text width scaled with system text size and 144dp for the cover when choosing the layout; otherwise stack the artwork and centred details, keeping the renderer selector under transport. Keep 32dp above and below the artwork/details group. Now Playing does not scroll: reserve space for progress and transport, then fit the presentation into the remaining height. The cover yields first; very short windows may scale the presentation group, including its renderer selector, while progress and transport retain their size. Base the decision on the player pane's constraints rather than the full window.

Use spare space below the playback controls for **UP NEXT** and its total upcoming count, with as many complete preview rows as fit, from one to five. Omit the section whenever its heading and one row cannot fit, on phones as well as tablets. At the end of the queue keep the heading, with **UP NEXT · 0** over **Queue is empty** in the queue’s own style when there is room. A pull down on the phone content still moves and closes the player sheet. The preview follows the neutral queue typography: uppercase mono heading, 14dp track title and 12dp artist, 40dp artwork and rows at least 56dp high, growing with system text size. Keep 16dp bottom clearance. The heading opens the full queue and each native row button plays its existing queue position. Do not add crimson fills to the preview or reduce the cover to fit it.

The preview heading and rows use neutral hover, pressed and keyboard-focus highlights with 8dp rounded corners and 12dp horizontal content padding. Keep the label, artwork and chevron inside the highlight. Clickable controls show a hand cursor on desktop as well as web; disabled controls retain the arrow. Use `WidgetStateMouseCursor.clickable` for Material controls and `clickCursor` or a `MouseRegion` for custom gestures, preserving text-entry and drag cursors.

The playback queue adds an **Album** column from 600dp of queue-pane width, increasing the threshold with system text size. Keep title and artist together, with album and time aligned across the current, upcoming and previously played rows. When the column is present, place a quiet mono legend (**TRACK / ARTIST**, **ALBUM**, **TIME**) directly below **UP NEXT** as part of its pinned header. Now Playing and Previously Played have title-only headers without column labels or space reserved for them. Keep the duration and drag-handle gutters stable. Hide the extra column and legend on narrower panes or when no queued track has album metadata; individual missing albums leave an empty cell. These labels describe the columns and do not sort the queue.

### Output picker

The renderer bottom sheet follows the kiosk panel's layout using standard Kalinka sheet surfaces and IBM Plex typography. Put **PLAYING ON**, the current output's name and details, and its volume control above a divider and **OTHER OUTPUTS**. Keep the current output plain, without a selection frame or checkmark; other outputs have no leading radio circles. Only the current output shows a settings gear. Preserve available upgrade actions and neutral row hover/focus feedback. The volume slider has a crimson active track, a percentage, 20dp clearance above and 24dp below; unavailable volume stays visible, grey and disabled. Use 20dp content gutters, let long current-output names wrap, and keep Close outside the scrolling body. Cap the content at 560dp or 75% of the viewport height, with scrolling for short screens and enlarged text.
