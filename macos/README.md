# AgentRing for macOS

A native SwiftUI menu-bar app. It is a view over the local daemon: no agent
internals are read directly, and the preview uses the same `/frame` bytes as the
ESP32.

```sh
./macos/build.sh
cp -R dist/AgentRing.app /Applications/
open /Applications/AgentRing.app
```

Requires macOS 14+, the Xcode command line tools, and Python 3 + Pillow for
the icon pipeline. The app version comes from the root `VERSION` file at build
time; the sidebar and **通用 → 关于** show the app and daemon versions separately. The app is built with
Swift Package Manager (`Package.swift`) and packaged/ad-hoc signed by
`build.sh`.

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
| `Sources/AgentRing/SettingsControls.swift` | Session rows, badges and attention chips |
| `Sources/AgentRing/RingLayerView.swift` | 24 CALayers driven by `/frame` at 30 fps (previews are daemon state) |
| `Sources/AgentRing/AgentRingSession.swift` | Ephemeral URLSession; no CFNetwork sleep assertions |
| `Sources/AgentRing/Theme.swift` | Colours, labels, SF Symbols |
| `Sources/AgentRing/MenuBarIcon.swift` | Loads the template menu-bar ring and provides `MenuBarGlyph` |
| `Resources/Logo.png` | Brand logo used to generate the app and menu-bar icons |
| `make-icon.py` | Crops/masks the logo into the 1024 px app icon used by `build.sh` |

The app is `LSUIElement`: no Dock icon. If no menu-bar icon appears, allow
AgentRing in macOS “Menu Bar” settings and in Thaw/Bartender/Ice.
