---
"voxa": patch
---

First-cut app icon lands in `AppIcon.appiconset`, unblocking TestFlight uploads.

The wordmark source SVG (`ios/design/voxa-app-icon.svg`) was rendered to a single 1024×1024 PNG via `qlmanage` and dropped into `ios/Voxa/Assets.xcassets/AppIcon.appiconset/`. iOS 17+ generates the size grid from the 1024 master, so no per-size PNGs are needed. XcodeGen regenerated `project.pbxproj` to reference the new asset catalog under the `Voxa` target's `Resources` build phase; `ASSETCATALOG_COMPILER_APPICON_NAME` was already set to `AppIcon`.

To iterate the icon: edit the SVG, then regenerate the PNG with `qlmanage -t -s 1024 -o /tmp ios/design/voxa-app-icon.svg && cp /tmp/voxa-app-icon.svg.png ios/Voxa/Assets.xcassets/AppIcon.appiconset/voxa-1024.png` — no XcodeGen rerun needed for pixel-only changes.
