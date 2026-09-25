# Kalinka app manual

How to get from first launch to playing music. Server installation is
covered separately in the [installation guide](https://github.com/Kalinka-Player/KalinkaPlayer/blob/main/docs/installation.md).

## 1. First launch — the setup wizard

On first launch the app runs a short setup wizard. It starts by scanning
your network for Kalinka servers — after a few seconds every server it
finds appears in a list; pick yours and tap the **Connect** button at
the bottom.

| Scanning | Servers found |
|:---:|:---:|
| <img src="images/manual/discovery-scanning.png" width="260"> | <img src="images/manual/server-list.png" width="260"> |

If nothing shows up, the phone and the server are probably not on the same
network (or the router blocks multicast/mDNS) — use **Enter Address
Manually** at the bottom and type `<server-ip>:8000`.

The wizard then walks you through the first-run essentials — your music sources, the folders to scan, smart search, the audio output, an amplifier or receiver, and a sound test — and finishes by restarting the server. Each step is explained in the [first-run setup guide](first-run-setup.md). Everything it sets can be changed later in **Server settings** (sections 3–4).

## 2. The main screen

After setup you land on the play queue. On a fresh server it greets
you with *"Nothing Queued"*:

<img src="images/manual/main-screen.png" width="260">

The three things to know:

- **Search button** (bottom-right) — the floating sparkle button opens
  search and Discover; ask for music in plain language.
- **Mini player** (bottom) — the current track; tap it to open the full
  player.
- **The server chip** (top-right) — your server's name with its status
  dot, **and a button**. This is the door to everything server-related;
  it's easy to miss, so:

## 3. The server chip — server menu and settings

Tap the **server chip** to open the server sheet:

<img src="images/manual/server-sheet.png" width="260">

From here you can see the connection status, server address, version and
latency, and reach:

- **Server settings** — all configuration (see next section)
- **Connect to different server** — rescan the network and switch
- **Disconnect**

The chip's dot also tells you the connection state at a glance: green —
online, amber — connecting/reconnecting, grey — offline.

## 4. Add your music

The setup wizard configures this on first run — here is where to change
it later. From the server sheet tap **Server settings**:

<img src="images/manual/settings-general.png" width="260">

1. Switch to the **Input modules** tab.
2. Open **My Library**.
3. Add your collection under **Music sources** — a folder on the
   server such as `/srv/kalinka/music`, or a network share on a NAS
   or another computer (see the [installation
   guide](https://github.com/Kalinka-Player/KalinkaPlayer/blob/main/docs/installation.md#put-your-music-on-it)
   for where the folder should live and the permissions it needs).

The indexer picks the folder up automatically (every 15 minutes, plus a
file watcher for instant changes). While you're in settings, the
**General** tab has the other first-run essentials: the service name shown
in discovery, the ALSA **audio output** device, and **device automation**
(auto power on/off). The **EXPERT** toggle at the top reveals the advanced
tier.

## 5. Search and queue music

Tap the sparkle button to open search. It is AI-first: describe what you
want in plain language ("jazz", "melancholic evening piano"), send, and
the server curates matches from your library, grouped by source. Before
you type, the **Discover** screen offers ready-made AI prompts, catalog
cards to explore your sources, recent searches and recently favourited
tracks:

| AI suggestions | Batch selection |
|:---:|:---:|
| <img src="images/manual/search-ai.png" width="260"> | <img src="images/manual/search-ai-selected.png" width="260"> |

Use **Add All** on a section to queue every track in it — adding never
plays or replaces your queue until you say so. Long-press a track to
start a selection — or use **Select all** on a section — then choose
**Play now**, **Play next**, or **Add to queue**.

## 6. The queue and the player

Back on the main screen your queue is live: the current track on top,
**UP NEXT** below, drag handles to reorder, swipe to remove. Tap the mini
player to expand the full player with artwork, format/quality info,
transport controls and volume:

| Play queue | Player |
|:---:|:---:|
| <img src="images/manual/queue.png" width="260"> | <img src="images/manual/player.png" width="260"> |

## Troubleshooting

See the [installation guide](https://github.com/Kalinka-Player/KalinkaPlayer/blob/main/docs/installation.md#troubleshooting) — empty
library, no server found, and no-sound issues are covered there.
