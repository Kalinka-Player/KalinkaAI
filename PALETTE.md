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
