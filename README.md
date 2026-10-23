# VBAN Deck

VBAN Deck sends Steam Deck / Linux audio as VBAN PCM packets to a receiver such as Voicemeeter. This repository contains the two released versions:

| Target | Directory | Status |
| --- | --- | --- |
| Linux / Steam Deck Flatpak | `flatpak/` | Working release source |
| Steam Deck Game Mode (Decky Loader) | `decky/` | Working plugin source |

The protocol uses 48 kHz, stereo, signed 16-bit PCM in 256-frame UDP packets. Configure the receiver with the sender's stream name and port (default `6980`).

## Repository layout

`flatpak/` and `decky/` contain the application source and their required assets. `docs/` contains release instructions and patch notes; `.github/` contains the release workflow. Generated builds, archives, and editor settings are ignored.

## Build

See each platform's README:

- [Flatpak / Steam Deck Desktop](flatpak/README.md)
- [Decky Loader](decky/README.md)
- [Release guide](docs/RELEASING.md)

## License

MIT. See [LICENSE](LICENSE).
