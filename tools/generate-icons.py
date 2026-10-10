"""Resize the canonical VBAN Deck PNG into platform-specific raster icons."""

from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "assets" / "vban-deck-logo-1024.png"


def render(destination: Path, size: int) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    with Image.open(SOURCE) as source:
        source.resize((size, size), Image.Resampling.LANCZOS).save(destination)


for density, size in {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}.items():
    for name in ("ic_launcher.png", "ic_launcher_round.png"):
        render(ROOT / "android" / "app" / "src" / "main" / "res" / f"mipmap-{density}" / name, size)

mac_icons = {
    "icon_16x16.png": 16,
    "icon_16x16@2x.png": 32,
    "icon_32x32.png": 32,
    "icon_32x32@2x.png": 64,
    "icon_128x128.png": 128,
    "icon_128x128@2x.png": 256,
    "icon_256x256.png": 256,
    "icon_256x256@2x.png": 512,
    "icon_512x512.png": 512,
    "icon_512x512@2x.png": 1024,
}
for name, size in mac_icons.items():
    render(ROOT / "VBANDeckMac" / "VBANDeckMac" / "Assets.xcassets" / "AppIcon.appiconset" / name, size)
