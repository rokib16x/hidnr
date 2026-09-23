# Changelog

## 0.1.1

- **The real h now stays in the menu bar while icons are hidden.** macOS 27
  keeps hidnr's own icon only when hidnr is installed in **/Applications**
  (as the DMG and Homebrew do). Installed that way, hidnr no longer needs its
  stand-in h, so it can't end up beside the notch or on top of other icons.
- Run from anywhere else, hidnr falls back to the stand-in h and suggests
  moving it to Applications.
- The stand-in is placed from a snapshot taken just before hiding, since macOS
  keeps reporting hidden icons at their old positions.

## 0.1.0

First release.

- Click the **h** in the menu bar to hide or show icons; right-click it for the quick panel.
- **Icons** page in Settings: pick which apps stay visible and which hide.
- Built for macOS 27: hides apps through macOS's own menu bar allow-list.
  On macOS 14–26, drag icons past the divider next to the h.
- Hide again automatically after 5 s to 1 min, hide on launch, open at login.
- Re-open hidnr from Spotlight or Finder to bring every icon back.
