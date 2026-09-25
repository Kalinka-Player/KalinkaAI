# Changelog

Curated, user-facing notes per release. Add a `## <version>` section (matching
the `pubspec.yaml` semver, no build suffix) before tagging — the release
pipeline pulls the matching section into the GitHub Release body.

Do not hard-wrap the notes: GitHub renders a newline inside a release body as
a line break, so a wrapped sentence arrives broken. One line per bullet or
paragraph, however long; blank lines separate paragraphs.

## 0.11.0

Works with Kalinka server 5.0.0 or newer. Network shares, suggestions and checks while editing settings, downloading the server's logs and source icons need server 5.1.0; against an older server the app keeps the music-folders list it had before.

### Added
- Music sources as cards. My Library's settings list each source as a card, and each opens a sheet of its own: a folder on the server, or a network share on a NAS or another computer, signed in to with an account or as a guest. ADD, KEEP CHANGES and REMOVE say what happens to it, and closing the sheet leaves the source as it was.
- While you fill a source in, the server suggests the drives attached to it and the SMB servers it can see on the network, and what it finds wrong appears under the field it is about.
- The setup wizard asks for music sources instead of music folders. A source the server refuses reads NEEDS SETUP, and Start listening stays off until it is put right. Turning a source off takes back what was typed for it.
- Settings the server can suggest values for get a browse button, and every change is checked as you make it: red means the server will refuse to save it, amber is a warning it will save anyway. Apply stays off while anything is refused, and checks everything once more before the server restarts.
- A saved password shows as set without the server sending it: a mask stands in for it, typing starts a new one, and clearing it removes the saved one on save.
- Download the server's recent logs from Settings → General → Support, to attach to a bug report: the last hour, day or week, with the renderer's logs from the same machine if you want them. The app says how big the file is, how long it stays available and what the server left out, then saves or shares it.
- Sources draw their own icon on their badges and tiles, and it grows with the text size.

### Changed
- Your own library is called My Library throughout: in setup, on the empty modules page and on the indexing card.
- A staged setting is marked by its amber tint alone, without a pill that pushed the row around.
- A folder you type is committed when you leave the field or press Enter, rather than on every keystroke.

### Fixed
- Resizing the window across the phone and tablet layouts with Settings open no longer crashes, and no longer reloads the settings, which used to drop staged changes, reset the tab and close anything open.

## 0.10.0

Requires Kalinka server 5.0.0 or newer: the app has retired the merged search endpoint the old server offered, and asks each source on its own instead.

### Added
- Your own collections, kept by the server. The Discover root leads with YOUR COLLECTIONS — the first few as rows, with VIEW ALL into the rest — and offers to make the first one when there are none. A collection unrolls in place like an album, and plays or enqueues as a whole.
- Save the queue as it stands into a collection, from the queue's own overflow. A multi-select can go to one too, as can an album or a single track.
- Adding to a collection asks the question outright: APPEND or REPLACE, with a Keep duplicates switch, and a replace onto a collection that holds something confirms by name first.
- Edit collections in place. Drag rows by the handle to reorder, mark rows to go, and nothing is written until Done — which names what it would remove before removing it. Rename and delete live behind each row's overflow.
- Search results are laid out per source. Every source is asked for its name matches and its recommendations separately and each answer appears as it lands, so a slow source no longer holds up the page and a failed one says so and can be retried on its own.
- Matches from every source merge into one MATCHES BY NAME list, ranked by the server, with a row of source pills to read them one source at a time.
- A refine card narrows what search loaded — by result kind, type, source, genre and A-Z — and its search field starts a new search.
- Catalogs can be narrowed. The title bar's filter button unfolds into a card of the facets that source actually declared, with removable chips above the rows so a filtered list never reads as unfiltered.
- A catalog made of shelves shows one row per kind, each arriving on its own, with VIEW ALL opening that kind in full.
- The playing track is marked with three bars beside its duration — moving while it plays, still while it is paused. Reduced motion stops them.
- A renderer's settings page now shows its host and version, and greys out values that cannot be edited.
- When the server declines to play a track it now says why — "Music folder /mnt/nas is not available", rather than the generic warning.
- The indexer status card shows the audio-analysis stage on its own.

### Changed
- Your own library is named and lettered like every other source, instead of being the unmarked default under three different hardcoded names.
- The Inspired block reads in its own voice: the name in the display face over a quiet eyebrow, a neutral wash behind the heading, and a tally on each source so three rows read as a preview of twenty.
- A shelf that cannot honour an active filter is left off the page rather than shown unfiltered beneath a filter chip.
- Search asks a source only for what it can answer, so a source with no recommendations of its own no longer holds an empty block open.
- Every list of rows now draws dividers, and the hairline starts where the row's words start so the artwork reads as one column.
- Placeholders take the shape of the rows they stand in for, so a list no longer shifts when its rows land.
- Every clickable control now shows the hand cursor on desktop and web, and sheet rows answer the pointer with a lift.
- Counts read "1 album" rather than "1 albums", and an unrolled container counts the whole collection rather than the page on screen.

### Fixed
- A multi-select no longer outlives the listing it was gathered from and acts on rows that are no longer on screen.
- Selecting a track no longer nudges its artwork sideways.
- An artist's subtitle trails off at the end of the row instead of running past it on a narrow screen.
- The crimson bloom behind Discover no longer ends in a visible line.
- A collection saved from the queue shows its tracks immediately instead of staying empty until the page is reopened, and its cover appears once the server has composed it.
- The collections invitation stays one row down to phone widths instead of growing tall enough to push the catalogs off screen.

## 0.7.0

### Changed
- The output list now follows the server live: outputs joining or leaving the network appear and disappear immediately, even while the picker sheet is open, so the picker's refresh button is gone. Against an older server the list still loads on connect and when the picker opens, exactly as before.
- When no output is available the cast icon stays on screen with a crossed badge and the picker says so outright, instead of the switcher silently disappearing while playback fails.

## 0.6.1

### Added
- The web player now runs the same first-run setup wizard as the app, minus the server-discovery step the browser doesn't need.

### Changed
- A server on several networks now shows up once in discovery, under its own name instead of once per network interface, and the app connects over the fastest reachable route. Older servers list exactly as before.
- Playback through the browser output now rides out brief connection drops and server address changes: the server picks its session back up when it returns, and playback left without a server stops on its own after a minute instead of running unattended.

### Fixed
- Skipping tracks quickly in the browser no longer marks the interrupted track as failed.
- The guided tour no longer starts in the web player.
- The "This browser" output no longer disappears while the setup wizard is running.
- Setup wizard steps share the same half-width column on tablets instead of each picking its own width.

## 0.6.0

### Added
- Choose where the music plays. The cast icon in the mini player and in Now Playing lists the outputs on your network — a machine wired to your DAC, another room, this device — and moves playback to the one you pick. Each output has its own settings behind a gear, applied without a restart.
- Play through the browser. Open the web player and it offers itself as an output, listed as "This browser".
- Test the sound from the output's own settings, and from the setup wizard, without restarting anything.
- Hand volume and power to an amplifier or receiver, per output, so the hardware you actually listen through takes the volume commands.
- Rescan for servers from the discovery screen instead of restarting the app when one doesn't show up.

Outputs appear once the server supports them; against an older server the app behaves exactly as it did before.

### Changed
- First-run setup is rebuilt around outputs and asks less: the questions come from the server, so each source and device asks only for what it needs. The server-name step is gone.
- The phone Now Playing header puts minimise on the left and the output on the right, and the output reads as one control — icon, state and name.
- The guided tour now runs on tablets too, and points out the output switcher.
- A search that never answers now gives up after ten seconds and says so, instead of spinning.

### Fixed
- An intermittent crash on startup and when reconnecting.
- The restart progress screen no longer stretches across a wide window.

## 0.5.2

### Added
- Retry a track that failed to play: the play button now sends play again
  instead of turning into a dead warning icon.
- Tracks the player couldn't play stay marked in the queue for the rest of the
  session, and the now-playing header says so — the mark clears once the track
  plays.

### Changed
- Every confirmation dialog now shares one presentation: bottom-anchored, and
  on tablets it stays inside the panel it belongs to and follows window
  resizes.

### Fixed
- Server discovery on Windows: a virtual network adapter refusing to join the
  multicast group aborted the whole scan, so the app jumped straight to manual
  address entry.
- The server update banner now re-checks after connecting to a different
  server instead of describing the one connected first.
- The playback error dialog now goes away when the error does — for example
  when another client skips the failing track.

## 0.5.1

### Changed
- Find Music: the search entry now stands out on the Discover screen, and the
  suggestion overlay reads more clearly — icons on every row and less prompt
  text while you type.
- Android now ships a single universal APK instead of per-ABI builds.

### Fixed
- Crash when clearing the playback queue.
- Duplicate entries when scanning for servers on the local network.

## 0.5.0

### Added
- Find Music: hybrid browse/search replacing the tabbed flow — explore source
  catalogs through art-backed category pages with breadcrumb navigation and
  infinite scrolling, or ask the AI and return to your results at any time.
- Redesigned AI search entry with an animated overlay, curated history and
  suggestion slots.
- Server updates from the app: an update banner in Settings → Server with a
  confirm dialog and install progress overlay.
- Windows x64 desktop build with an Inno Setup installer.
- Permanent latest-download links: every release also publishes version-less
  alias assets.

### Changed
- Catalog cards redesigned as 3:1 banners with framed art and source
  attribution.
- Faster catalog browsing: banner blur pre-baked, flatter banner heights on
  wide screens, brighter loading shimmer.
- Initial setup wizard now only runs when the server requests it.
- Haptic feedback disabled on desktop and web.
- Upgraded to Flutter 3.44 and Riverpod 3.4.

### Fixed
- Now-playing highlight for singles and loose tracks in the artist expansion.
- Spurious connection banner while browsing Find Music; catalog cards refresh
  once per session.

## 0.3.0

### Added
- AI-first Discover screen replacing the old top-bar search.
- Source attribution across the app: AI sections tinted by their source badge
  colour, and a "My Files" badge on local now-playing tracks.
- AI search on by default, with curated query history in the suggestion slots
  and expanded completion stubs (moods, genres, instruments).

### Changed
- Polished search result rows, Discover cards, the mini-player and navigation.
- Settings field descriptions now render inline markdown (links, italic, bold).
- Tablet: bottom sheets anchor to their panel and the discovery overlay
  survives window resizes.

### Fixed
- Mini-player play/pause button no longer dead; reuses the shared transport button.
- Now-playing prev/next disabled at the queue ends.
- Long full-width button labels truncate with an ellipsis.
- Loading shimmer matches the AI results layout.
