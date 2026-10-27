<h1 align="center">Meshy</h1>

<p align="center">
  <img src="Design/Meshy%20Icon%20256.png" alt="Meshy app icon" width="128" height="128">
</p>

<p align="center">Live mesh-gradient and video wallpapers for macOS.</p>

Meshy brings [Acrylic](https://github.com/EthanLipnik/Acrylic), Ethan Lipnik's fluid wallpaper
engine, back to life. Meshy keeps the same idea (living, color-shifting mesh gradients and video
wallpapers right on your desktop) working on newer versions of macOS, with a few small tweaks and
improvements along the way:

- Each display can have its own theme, and your choice is remembered across restarts
- A Fluid Editor to design and save your own gradients
- Video wallpapers from Pixabay (with your own free API key) or from your own files
- Pauses automatically while an app is fullscreen

Meshy is not affiliated with or endorsed by the original author. See [NOTICE.md](NOTICE.md) for
attributions and third-party licenses.

AI tools were used to help develop this app.

## Download

Grab `Meshy-x.y.z.dmg` from the [latest release](https://github.com/MeLlamoCarl/Meshy/releases/latest),
open it and drag **Meshy** to **Applications**. Requires macOS 13 Ventura or later, on Apple silicon or
Intel. So far Meshy has only been tested on Apple silicon with macOS 27, but it should work on any
supported Mac and macOS version.

Meshy is free and open source. It is signed ad hoc rather than with a paid Apple Developer ID, so the
first time you open it macOS says it can't verify the developer:

1. Open Meshy once and dismiss the warning.
2. Go to **System Settings › Privacy & Security**, find "Meshy was blocked…" and click **Open Anyway**.

You only need to do this once. To check your download, compare `shasum -a 256 Meshy-x.y.z.dmg` with
the checksum in the release notes.

### Wallpaper cache

Meshy sets a still picture of the current wallpaper as your desktop picture, which macOS uses for
the menu bar, the lock screen and Mission Control. macOS keeps a cached copy of every desktop
picture it is given and doesn't seem to clean them up. Versions before 1.0.1 set a new full-size
picture on every color change, which could add up to many gigabytes. Meshy now uses small pictures
for Fluid wallpapers and reuses one picture per video, so the cache grows much more slowly.

Apps can't clean this cache, but it is safe to delete. In Finder, choose **Go › Go to Folder…**,
paste the path below and delete the `.bmp` files inside. macOS recreates the ones it needs.

```
~/Library/Containers/com.apple.wallpaper.agent/Data/Library/Caches/com.apple.wallpaper.caches/extension-com.apple.wallpaper.extension.image
```

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
