# VBAN Deck

VBAN Deck sends device audio as VBAN PCM packets to a receiver such as Voicemeeter. It supports the platforms that have working builds:

| Target | Directory | Status |
| --- | --- | --- |
| Linux / Steam Deck Flatpak | `flatpak/` | Working release source |
| Steam Deck Game Mode (Decky Loader) | `decky/` | Working plugin source |
| Android | `android/` | Working playback-capture sender |

The protocol uses 48 kHz, stereo, signed 16-bit PCM in 256-frame UDP packets. Configure the receiver with the sender's stream name and port (default `6980`).

## Repository layout

The root intentionally contains only publishable source.

## Build

See each platform's README:

- [Flatpak / Steam Deck Desktop](flatpak/README.md)
- [Decky Loader](decky/README.md)
- [Android APK](android/README.md)
- [Release guide](docs/RELEASING.md)

## License

MIT. See [LICENSE](LICENSE).
