# AgentRing for macOS

[中文](README.zh.md) · [English](README.md)

A native SwiftUI menu-bar app. It is a view over the local daemon: no agent
internals are read directly, and the preview uses the same `/frame` bytes as the
ESP32.

```sh
./macos/build.sh
cp -R dist/AgentRing.app /Applications/
open /Applications/AgentRing.app
```

Requires macOS 14+, Xcode 27 / Swift 6, and Python 3 + Pillow for the icon
pipeline. The app and `AgentRingCore` use the Swift 6 language mode. The app version comes from the root `VERSION` file at build
time; the sidebar and **General → About** show the app and daemon versions separately. The app is built with
Swift Package Manager (`Package.swift`) and packaged/ad-hoc signed by
`build.sh`.

## Xcode / App Store

`project.yml` is the source of truth for the Xcode App Store target; the
generated `AgentRing.xcodeproj` is committed so Xcode and CI do not need
XcodeGen. Regenerate it after editing the spec:

```sh
cd macos
xcodegen generate
xcodebuild -project AgentRing.xcodeproj -scheme AgentRing \
  -configuration Release CODE_SIGNING_ALLOWED=NO build
```

The target adds App Sandbox + Hardened Runtime, network/client-server and USB
entitlements, the app icon asset catalog, the privacy manifest and both
localizations. `build.sh` remains the direct-download build. The app and
`AgentRingCore` are Swift 6 language mode; run its tests with
`swift test --package-path macos/AgentRingCore`.

**Not submission-ready yet:** this target is scaffolding for the App Store. The
self-contained Swift daemon and the USB firmware flasher still need to be
ported; the current app talks to the Node daemon and uses `launchctl`, which the
App Store sandbox does not allow.

| File | Responsibility |
|---|---|
| `Sources/AgentRing/AgentRingApp.swift` | `MenuBarExtra`, settings window, app delegate |
| `Sources/AgentRing/DaemonModel.swift` | `/state` (1.5 s), `/health` (3 s), config push |
| `Sources/AgentRing/SettingsView.swift` | Sidebar shell, navigation and window behaviour |
| `Sources/AgentRing/DesignSystem.swift` | Cards, headers, sliders, choice tiles and the ring stage |
| `Sources/AgentRing/PreviewTab.swift` | Live ring preview, legend and the integrated session list |
| `Sources/AgentRing/LightingTab.swift` | Lighting studio shell: live rail, section bar and overview cards |
| `Sources/AgentRing/LightingPanels.swift` | Display / standby / layout / states panels; accent palette + per-state effect/speed; previews are mirrored through `POST /preview` |
| `Sources/AgentRing/SourcesTab.swift` | Install/connection status per agent (via `/sources`), one-click hook installers, on-ring toggles and colour wells |
| `Sources/AgentRing/GeneralTab.swift` | Daemon/ring diagnostics and maintenance |
| `AgentRingCore/` | Swift 6 port of the daemon state model; per-session state machine + v3 config with tests |
| `Sources/AgentRing/SettingsControls.swift` | Session rows, badges and attention chips |
| `Sources/AgentRing/RingLayerView.swift` | 24 CALayers driven by `/frame` at 30 fps (previews are daemon state) |
| `Sources/AgentRing/AgentRingSession.swift` | Ephemeral URLSession; no CFNetwork sleep assertions |
| `Sources/AgentRing/Theme.swift` | Colours, labels, SF Symbols |
| `Sources/AgentRing/Localization.swift` | Language switch, localized daemon labels and runtime strings |
| `Resources/en.lproj`, `Resources/zh-Hans.lproj` | Interface strings; `build.sh` copies both into the app bundle |
| `Sources/AgentRing/MenuBarIcon.swift` | Loads the template menu-bar ring and provides `MenuBarGlyph` |
| `Resources/Logo.png` | Brand logo used to generate the app and menu-bar icons |
| `Resources/MenuBarIcon.png`, `@2x` | Generated template menu-bar icons |
| `make-icon.py` | Crops/masks the logo into the 1024 px app icon used by `build.sh` |
| `project.yml` | XcodeGen spec for the App Store target |
| `AgentRing.xcodeproj` | Generated Xcode project (App Store packaging) |
| `Configuration/` | Info.plist, App Sandbox entitlements and privacy manifest |
| `Assets.xcassets` | AppIcon asset catalog |

The app is `LSUIElement`: no Dock icon. If no menu-bar icon appears, allow
AgentRing in macOS “Menu Bar” settings and in Thaw/Bartender/Ice.

The interface follows the system language by default and can be switched in
**General → Language**. Static copy is keyed by the Chinese source string in the two
`.lproj` files; runtime copy (counts, daemon labels, statuses) goes through
`L10n`. New visible strings need both the Chinese key and the English value.
