# VBAN Deck 0.2.1

VBAN Deck streams Steam Deck/Linux desktop audio to a VBAN receiver such as Voicemeeter using native PipeWire capture.

## Architecture

PipeWire sink-monitor capture → ring buffer → paced VBAN PCM packets → UDP receiver.

Audio format is fixed at 48 kHz, stereo, signed 16-bit PCM, with 256 audio frames per VBAN packet.

## 0.2.1 fixes

- Native PipeWire socket permission is included in the Flatpak manifest.
- The sender is stopped when the GUI closes.
- Libadwaita compatibility fix for `Adw.EntryRow`.
- Build manifest creates `/app/bin` before compiling the sender.
- Added `build-release.sh` to produce a shareable `.flatpak` bundle.

## Build and install for development

```sh
./build-flatpak.sh
```

Launch from the application menu as **VBAN Deck**, or with:

```sh
flatpak run com.tee215.VBANDeck
```

## Build a shareable installer

```sh
./build-release.sh
```

The resulting file is:

```text
dist/VBANDeck-0.2.1.flatpak
```

Share that file. On a Flatpak-enabled Linux desktop, it can be installed using the graphical software installer when supported, or from a terminal with:

```sh
flatpak install --user VBANDeck-0.2.1.flatpak
```

After installation, the exported desktop entry makes **VBAN Deck** available in the application launcher; no command line is required to run it.

### Steam Deck build prerequisites

The project currently targets GNOME Platform/SDK 49. If needed:

```sh
flatpak install --user flathub org.gnome.Platform//49 org.gnome.Sdk//49 org.flatpak.Builder
```

## Receiver

Configure a VBAN receiver for the same stream name and UDP port used in VBAN Deck. The default values are stream name `SteamDeck` and port `6980`.

## License

MIT
