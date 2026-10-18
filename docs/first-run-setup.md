# First-run setup

The first time you open Kalinka it runs a short setup wizard. It has eight steps and takes a few minutes. This guide explains what each step asks for and why.

The wizard is the same in the **app** (Android, Linux, Windows) and in the **web player** in your browser, with one difference: the web player already knows which server it belongs to, so it skips step 1 and starts at **Network** (step 2 of 8). Network setup is always shown, including when the box already uses Wi-Fi or Ethernet.

Before you start, the Kalinka server should already be installed — see [installing the server](https://github.com/Kalinka-Player/KalinkaPlayer#installation). If it is not on your network yet, use the connection steps below.

Network changes apply when you connect. At the end the wizard saves the remaining settings and restarts the server, which takes about half a minute.

## Connect an offline box

**Save these instructions before changing Wi-Fi.** They are available here before you can reach the box's own web page.

<img src="https://raw.githubusercontent.com/Kalinka-Player/KalinkaPlayer/main/docs/images/install/hotspot-setup.svg" width="640" alt="Join Kalinka-Setup-XXXX in Wi-Fi settings, use password kalinka-setup, stay connected without internet, then open http://192.168.4.1 and choose your home Wi-Fi.">

1. Power on the box and wait a couple of minutes. In your laptop or phone's Wi-Fi settings, join **`Kalinka-Setup-XXXX`**. The last four characters identify your box.
2. Enter **`kalinka-setup`** — all lowercase, with a hyphen. This is the hotspot password, separate from your home Wi-Fi password.
3. Stay connected if your device says **No internet**. Open the network sign-in page, or enter **`http://192.168.4.1`** in your browser.
4. Choose your home Wi-Fi and enter its password. The hotspot disconnects during joining; reconnect your laptop or phone to your home network, then open the player. If joining fails, reconnect to the restored hotspot to retry.

The native app also offers **Set up a box → Search using Bluetooth**, so you can send Wi-Fi settings without changing your phone's Wi-Fi connection. Its **Use the temporary Wi-Fi hotspot** option shows illustrated steps and a **Copy password** button. A laptop browser needs no app and uses the steps above. You can instead connect the box to your router by Ethernet and keep that connection in the Network step.

A box that already has a working network connection does not open the hotspot. After a previously connected box loses its network, allow about five minutes for setup to return. See the [image installation guide](https://github.com/Kalinka-Player/KalinkaPlayer/blob/main/docs/installation.md#connect-your-box-to-the-network) for hardware requirements and a saveable copy of the illustration.

## Step 1 — Find your server (app only)

<img src="images/setup/1-find-server.png" width="320">

The app looks for Kalinka servers on your network and lists what it finds, with each server's address, response time and version. Tap the one you want, then tap **Connect**.

- **Rescan** — searches again. Use it if your server is missing; servers that just started up sometimes need a second look.
- **Enter Address Manually** — type `<server-ip>:8000` yourself. Use this when your network blocks discovery (mDNS), for example on guest or isolated Wi-Fi.

## Step 2 — Network

Review the current Wi-Fi name or Ethernet connection and choose **Keep this connection**, or select another Wi-Fi network. Available networks are discovered automatically; **Can’t find your network? Enter SSID manually** allows manual entry. Choosing a new network applies immediately, even before the rest of the wizard is finished.

Below the network, **Time zone** shows the zone the box is on. A new box runs on UTC, so the clock on its now-playing display and its night-time updates follow UTC until you set it. When your phone, computer or browser is on another zone, the step offers it: **Use** followed by the zone asks once, then sets it straight away. Tap **Time zone** to choose any other. The box still sets its clock over the network; only the zone changes, and nothing is looked up online to find it. A server without the Kalinka box supervisor, such as one installed on a computer of your own, keeps that computer's zone, and the row says so.

## Step 3 — Music sources

<img src="images/setup/2-music-sources.png" width="320">

Choose what fills your library. You need at least one source.

- **My Library** — your own music, on the server or on a network share. This is always on and cannot be turned off.
- **Jamendo** — a free streaming catalogue of independent artists. Turn it on if you want it.

Other sources appear here too if their plugins are installed on the server. You can always add or remove sources later in Settings.

## Step 4 — Set up your sources

<img src="images/setup/3-source-setup.png" width="320">

Each source you enabled asks only for what it needs.

### My Library

- **Music sources** — where your music is. This is the important one: if it points at the wrong place, your library stays empty. A source is either:
  - a **Folder on the server** — a folder or disk on the server itself, or a share already mounted there; or
  - a **Network share** — a shared folder on a NAS or another computer. The server connects to it by itself, with the user name and password of an account on it, or as a guest for a share that is open to guests.

  The server installer creates `/srv/kalinka/music`, and a folder source pointing at it is there by default. Copy your music there and you do not need to change anything. If your collection lives somewhere else — a NAS, a USB drive, a folder in your home directory — add it as a source instead.

  One rule for folders: the server runs as the user `kalusr`, so it must be allowed to read them. If the library stays empty afterwards, permissions are the usual reason — see [Put your music on it](https://github.com/Kalinka-Player/KalinkaPlayer/blob/main/docs/installation.md#put-your-music-on-it).

- **Enable AI search** — turn this **on** to search your own music by mood, genre and how it sounds, instead of only by name. This is what makes "something calm for the evening" work on your own library.

  It costs about 500 MB of memory while the server runs, and about 750 MB while it is indexing. The first indexing pass takes hours on a large library and a slow machine, such as a Raspberry Pi. It runs in the background — you can use Kalinka normally while it works, and results get better as more tracks are indexed.

### Jamendo

- **Client ID** — required, Jamendo does not work without it. Create a free account and an application at the [Jamendo Dev Portal](https://devportal.jamendo.com), then paste the application's Client ID here.
- **Mood / AI search** — turn this **on** to search Jamendo by mood or description as well. The data it needs is downloaded automatically the first time.
- **Audio quality** — the streaming format. FLAC is only available for tracks whose artist allowed lossless download, and falls back to MP3 for the rest.

> **To get smart search everywhere, turn AI search on for both My Library and Jamendo.** The two settings are separate: switching it off for one source does not affect the other. If you leave both off, search still works, but only by matching names.

## Step 5 — Audio output

<img src="images/setup/4-audio-output.png" width="320">

Pick where the music comes out. Each entry is a Kalinka renderer — the part that actually plays sound — named after the machine it runs on, for example *Kalinka Renderer on raspberrypi*.

The **gear** next to an output opens that output's own settings: which sound device it uses, the audio format, how it handles volume. These apply immediately and do not need a restart.

If the list is empty, nothing can play yet. Install the Kalinka renderer on the machine connected to your speakers or DAC, or open the web player in a browser to use that browser as an output, then press **Check again**.

You can switch outputs at any time later from the cast icon in the player.

## Step 6 — Amplifier or receiver

<img src="images/setup/5-amplifier.png" width="320">

This decides what handles volume and power.

- **Default volume control** — the output sets its own volume. Choose this if the music goes straight to a DAC, sound card or powered speakers.
- **A device from the list** (for example **MusicCast**) — choose this when the music plays into an amplifier or receiver that Kalinka can control. Volume and power then go to that device, and it may ask for a couple of details, such as which zone and which input the server is wired into.

Only devices whose plugins are installed on the server appear here. If yours is missing, install its plugin on the server later — it shows up in Settings afterwards.

## Step 7 — Test sound

**Do not skip this one.** It is the quickest way to find out whether your audio settings actually work, before you finish setup.

| The step | Playing the tones |
|:---:|:---:|
| <img src="images/setup/6-test-sound.png" width="300"> | <img src="images/setup/6-test-sound-tones.png" width="300"> |

Press **Play test sound**. A small window opens with **LEFT** and **RIGHT** buttons. Press each one: you should hear a short tone from that speaker only.

What it tells you:

- You hear both tones, on the correct sides — the output works and the channels are the right way round.
- You hear nothing — the wrong sound device is probably selected. HDMI, analog and USB DAC are separate devices.
- Left and right are swapped — your cables or your speaker wiring are crossed.

If something is wrong, the test offers that output's settings — device, format, volume mode — right there. Change them and test again immediately; no restart needed.

If you would rather not test now, the button at the bottom says **Skip for now**, and you can run the same test later from the output picker.

## Step 8 — Almost there

<img src="images/setup/7-finish.png" width="320">

The last step lists everything you chose: server, music sources, audio output, volume and power, and whether the sound test played. Each row has a **Change** link that takes you back to that step.

When it looks right, press **Start listening**. Kalinka saves the settings and restarts the server so they take effect, which takes about half a minute.

Two things carry on in the background afterwards: scanning your music folders, and — if you enabled AI search — building the data smart search needs. Your library and your search results keep improving for a while after setup finishes. This is normal.

## Changing things later

Nothing here is permanent.

- **Server settings** — tap the server chip at the top of the screen, then **Server settings**. Music sources and AI search live under **Input modules → My Library**.
- **Audio output** — the cast icon in the player switches outputs, and the gear next to each one opens its settings and its sound test.
- **Time zone** — **Server settings → General → Streamer → Time zone**.

## Updates

Kalinka keeps itself up to date; you only decide when.

- **The server** checks for a new release every hour. When there is one, **Server settings → General** shows *A new version … is available*. Tap it, then **Restart & Update**. Playback stops while the server installs the update and restarts, which takes a minute or two.
- **Automatic updates** — turn on **Auto upgrade** in the same place, and the server installs updates by itself between 3 and 6 in the morning, when nothing is playing.
- **Outputs** are upgraded along with the server, and before it, so the two always match. An output that needs an upgrade shows an upgrade button in the output list under the cast icon.
- **The web player** is updated together with the server.
- **The app** — if you installed it with Obtainium, Obtainium keeps it updated. Otherwise, download the new version from the [releases page](https://github.com/Kalinka-Player/KalinkaAI/releases/latest) when you want it.

## If something goes wrong

- **No servers found** — the app and the server must be on the same network, and some routers block discovery between devices. Use **Enter Address Manually** with `<server-ip>:8000`.
- **No outputs listed** — the renderer is not running on the machine connected to your audio gear, or it cannot reach the server.
- **No sound in the test** — the wrong device is selected. Open the output's settings from the gear and try another one.
- **Library is empty** — a music source points at the wrong place, the files are not readable by the `kalusr` user, or a network share's user name or password is wrong.
- **Smart search finds nothing yet** — indexing has not caught up. Give it time; on a large library the first pass takes hours.
