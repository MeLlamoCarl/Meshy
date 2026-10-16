# Meshy

Live mesh-gradient and video wallpapers for macOS.

Meshy brings [Acrylic](https://github.com/EthanLipnik/Acrylic), Ethan Lipnik's fluid wallpaper
engine, back to life. Acrylic's last supported release was macOS Ventura; Meshy keeps the same
idea (living, color-shifting mesh gradients and video wallpapers right on your desktop) working on
newer versions of macOS, with a few small tweaks and improvements along the way:

- Each display can have its own theme, and your choice is remembered across restarts
- A Fluid Editor to design and save your own gradients
- Video wallpapers from Pixabay (with your own free API key) or from your own files
- Pauses automatically while an app is fullscreen
- The menu bar tint follows the current wallpaper
- Mouse-friendly preset rows

Meshy is not affiliated with or endorsed by the original author. See [NOTICE.md](NOTICE.md) for
attributions and third-party licenses.

AI tools were used to help develop this app.

## Download

Grab `Meshy-x.y.z.dmg` from the [latest release](https://github.com/MeLlamoCarl/Meshy/releases/latest),
open it and drag **Meshy** to **Applications**. Requires macOS 13 Ventura or later, on Apple silicon or
Intel.

Meshy is free and open source. It is signed ad hoc rather than with a paid Apple Developer ID, so the
first time you open it macOS says it can't verify the developer:

1. Open Meshy once and dismiss the warning.
2. Go to **System Settings › Privacy & Security**, find "Meshy was blocked…" and click **Open Anyway**.

You only need to do this once. To check your download, compare `shasum -a 256 Meshy-x.y.z.dmg` with
the checksum in the release notes.

## Building

```bash
git clone --recurse-submodules https://github.com/MeLlamoCarl/Meshy.git
cd Meshy
xcodebuild -scheme Meshy -configuration Release -derivedDataPath build \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
```

Then copy `build/Build/Products/Release/Meshy.app` to `/Applications/`. You may need
`xcodebuild -downloadComponent MetalToolchain` first. `scripts/build-release.sh` builds the universal,
ad hoc signed app and the DMG into `dist/`.

Searching videos on Pixabay needs your own free API key, which the app asks for in Manage Videos
(also under Settings › Video and the ⚙️ menu).

## License

MIT — Copyright (c) 2023 Ethan Lipnik, Copyright (c) 2026 MeLlamoCarl. See [LICENSE.txt](LICENSE.txt).
