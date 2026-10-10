# VBAN Deck — Decky Loader plugin

VBAN Deck puts the native PipeWire → VBAN sender directly in Steam Deck Game Mode through Decky Loader.

## Features

- Destination IP, port, and VBAN stream name in the Decky quick-access panel.
- Captures the current default Steam Deck output through PipeWire sink-monitor capture.
- Native 48 kHz stereo 16-bit PCM.
- 256-frame paced VBAN packets (~5.33 ms cadence).
- Small ring buffer to absorb PipeWire scheduling variation.
- Persists settings.
- Stream keeps running when you merely close the Decky panel.
- Sender is terminated when the plugin unloads/uninstalls or when you press Stop.

## Build

This project follows the current Decky plugin template layout: React/TypeScript frontend, Python backend, and an optional native backend binary in `bin/`.

Requirements for building:

- Node.js 16.14+ and npm (the script uses pnpm 9 through `npx` if pnpm is not installed).
- PipeWire development headers, **or** `org.gnome.Sdk//49` installed as a Flatpak.
- `zip`, `make`, and a C compiler in the build environment.

Run:

```bash
chmod +x build-decky.sh
./build-decky.sh
```

The resulting shareable plugin is:

```text
release/VBANDeck-0.1.0.zip
```

## Install

Install the ZIP through Decky Loader's plugin installation/developer workflow. After installation, open the `...` quick-access menu → Decky → **VBAN Deck**.

Enter the receiver PC IP (for example `10.0.0.137`), leave port at `6980`, choose a stream name that matches the Voicemeeter VBAN receiver, and press **Start Streaming**.

## PipeWire note

Decky's Python backend may run outside the logged-in user's normal environment. The backend explicitly points the native sender to `/run/user/1000`, the standard Steam Deck user's PipeWire runtime directory.

## Source lineage

The native sender is the same PipeWire/VBAN engine proven in VBAN Deck Flatpak v0.2.1, repackaged behind a Decky frontend and Python process controller.
