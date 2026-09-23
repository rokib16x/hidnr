<p align="center">
  <img src="branding/hidnr-logo.png" width="420" alt="hidnr">
</p>

<p align="center">Hide the menu bar icons you don't need. Built for macOS 27, works on macOS 14+.</p>

## Install

### Download

Get `hidnr-<version>.dmg` from the [latest release](https://github.com/rokib16x/hidnr/releases/latest),
open it, and drag **hidnr** into **Applications**. The app is signed with a Developer ID
and notarized by Apple, so it opens without an "unidentified developer" warning.

### Homebrew

This repository is its own tap:

```sh
brew tap rokib16x/hidnr https://github.com/rokib16x/hidnr
brew trust --tap rokib16x/hidnr
brew install --cask hidnr
```

Requires macOS 14 or later, on Apple Silicon or Intel.

## Use it

1. Hold **⌘** and drag the icons you want out of the way to the **left** of the
   hidnr **h**.
2. Click the h to hide or show them. Right-click it for the quick panel.
3. On macOS 27, allow hidnr in **System Settings → Privacy & Security →
   Accessibility** the first time it asks. That lets it see where each icon sits.

hidnr can hide icons again automatically after a few seconds, and can open when
you log in. Both are in Settings.

## How it works

- **macOS 14–26:** hidnr places a thin divider next to its h and stretches
  it wide enough to push the icons on its left off screen.
- **macOS 27+:** that trick no longer works, so hidnr asks macOS to show only the
  apps on the visible side of the h. On macOS 27 hiding is per app, and
  macOS's own items (clock, Wi-Fi, Control Center) always stay visible.

## Release

Push a tag that matches `MARKETING_VERSION` in `project.yml` (for example `v0.1.0`).
The Release workflow builds a universal app, signs it with the Developer ID certificate,
notarizes and staples the DMG, publishes the GitHub release, and updates `Casks/hidnr.rb`.
Run it by hand with a tag as input for a dry run that publishes nothing.

## Build from source

```sh
brew install xcodegen
xcodegen generate
xcodebuild -project hidnr.xcodeproj -scheme hidnr -configuration Release \
  -derivedDataPath build build
open build/Build/Products/Release/hidnr.app
```

## Credits

The idea comes from [Hidden Bar](https://github.com/dwarvesf/hidden) by Dwarves
Foundation. hidnr is its own implementation.

## License

[MIT](LICENSE)
