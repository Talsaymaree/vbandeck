# Apple shared VBAN core

`apple/` contains the shared Swift package used by the macOS application.

## What is here

- `Package.swift`: Swift Package manifest.
- `Sources/VBANAppleShared`: VBAN constants, packet encoder, sender configuration, and UDP sender.
- `Tests/VBANAppleSharedTests`: packet/header compatibility tests based on the Android sender format.

## Validate the shared core

```sh
cd apple
swift test
```

Add this package to the `VBANDeckMac` Xcode project as a local package dependency when needed.
