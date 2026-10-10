# VBAN Deck for macOS

Open `VBANDeckMac.xcodeproj` in Xcode on macOS, select the `VBANDeckMac` scheme, and build or archive the app. For a public GitHub release, archive with a Developer ID certificate, notarize the exported application, then attach a signed ZIP or DMG to the draft release.

The app icon is generated from `../assets/vban-deck-logo-1024.png`. Run `python ../tools/generate-icons.py` after changing the canonical logo.
