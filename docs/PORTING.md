# macOS platform notes

The existing Flatpak and Decky code depends on PipeWire, while Android uses Android's MediaProjection playback-capture API. Neither capture stack can be compiled into a macOS app. The shared Apple implementation lives in `apple/` as a Swift package containing the VBAN packet encoder and UDP sender.

## Repository layout

- `apple/`: shared Swift package with packet/header validation tests.
- `VBANDeckMac/`: native macOS SwiftUI Xcode project.

## macOS

A native macOS app uses SwiftUI, `ScreenCaptureKit` to capture system audio, and `Network.framework` to send VBAN packets. The Xcode project keeps protocol logic in the shared package.

## Distribution

Apple platform artifacts must be built and signed on macOS with Xcode. Public distribution requires an Apple Developer account and the usual Apple distribution channels:

- macOS: signed and notarized `.app`, `.zip`, or `.dmg`.

## Shared validation

Use the same receiver, IP/port, stream name, 48 kHz sample rate, two channels, signed 16-bit samples, and 256 frames per packet on every platform. Add packet-level tests before creating the Swift targets so headers stay compatible.
