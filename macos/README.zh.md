# macOS 版 AgentRing

[中文](README.zh.md) · [English](README.md)

原生 SwiftUI 菜单栏 App。它只是本地守护进程的一个视图：不直接读取 agent 内部，预览用
的 `/frame` 字节和 ESP32 完全相同。

```sh
./macos/build.sh
cp -R dist/AgentRing.app /Applications/
open /Applications/AgentRing.app
```

需要 macOS 14+、Xcode 27 / Swift 6，以及图标流水线用的 Python 3 + Pillow。App 和
`AgentRingCore` 都使用 Swift 6 语言模式。App 版本在
构建时取自根目录的 `VERSION` 文件；侧边栏和 **通用 → 关于** 分别显示 App 与守护进程
版本。App 用 Swift Package Manager（`Package.swift`）构建，由 `build.sh` 打包并做
ad-hoc 签名。

## Xcode / App Store

Xcode App Store target 以 `project.yml` 为准，生成后的 `AgentRing.xcodeproj` 也提交到仓库，
Xcode 和 CI 不需要安装 XcodeGen。修改 spec 后重新生成：

```sh
cd macos
xcodegen generate
xcodebuild -project AgentRing.xcodeproj -scheme AgentRing \
  -configuration Release CODE_SIGNING_ALLOWED=NO build
```

该 target 已带 App Sandbox + Hardened Runtime、网络 client/server 与 USB entitlement、
AppIcon asset catalog、隐私清单和两套本地化。`build.sh` 仍用于直接分发构建。App 和
`AgentRingCore` 使用 Swift 6 语言模式；测试命令为
`swift test --package-path macos/AgentRingCore`。

**还不能提交审核：** 这只是 App Store 的工程脚手架。自包含 Swift daemon 和 USB 固件
刷写还没有移植；当前 App 仍连接 Node daemon 并使用 `launchctl`，后者在 App Store 沙盒里
不可用。

| 文件 | 职责 |
|---|---|
| `Sources/AgentRing/AgentRingApp.swift` | `MenuBarExtra`、设置窗口、App delegate |
| `Sources/AgentRing/DaemonModel.swift` | `/state`（1.5 s）、`/health`（3 s）、配置推送 |
| `Sources/AgentRing/SettingsView.swift` | 侧边栏骨架、导航与窗口行为 |
| `Sources/AgentRing/DesignSystem.swift` | 卡片、标题、滑杆、选项块和灯环舞台 |
| `Sources/AgentRing/PreviewTab.swift` | 实时灯环预览、图例和集成在其中的会话列表 |
| `Sources/AgentRing/LightingTab.swift` | 灯光工作室骨架：实时预览栏、分区栏和概览卡片 |
| `Sources/AgentRing/LightingPanels.swift` | 显示 / 待机 / 布局 / 状态面板；会话配色 + 每个状态的动效/速度；预览通过 `POST /preview` 镜像 |
| `Sources/AgentRing/SourcesTab.swift` | 每个 agent 的安装/连接状态（通过 `/sources`）、一键接入 hook、上环开关和色块 |
| `Sources/AgentRing/GeneralTab.swift` | 守护进程/灯环诊断与维护 |
| `AgentRingCore/` | daemon 状态模型的 Swift 6 移植；每会话状态机 + v3 配置，带测试 |
| `Sources/AgentRing/SettingsControls.swift` | 会话行、徽标和提醒标签 |
| `Sources/AgentRing/RingLayerView.swift` | 由 `/frame` 以 30 fps 驱动的 24 个 CALayer（预览也是守护进程状态） |
| `Sources/AgentRing/AgentRingSession.swift` | 临时 URLSession；不产生 CFNetwork 休眠断言 |
| `Sources/AgentRing/Theme.swift` | 颜色、标签、SF Symbols |
| `Sources/AgentRing/Localization.swift` | 语言切换、本地化的守护进程标签和运行时字符串 |
| `Resources/en.lproj`, `Resources/zh-Hans.lproj` | 界面文案；`build.sh` 把两者都复制进 App bundle |
| `Sources/AgentRing/MenuBarIcon.swift` | 加载模板菜单栏灯环并提供 `MenuBarGlyph` |
| `Resources/Logo.png` | 用于生成 App 和菜单栏图标的品牌 logo |
| `Resources/MenuBarIcon.png`, `@2x` | 生成后的菜单栏模板图标 |
| `make-icon.py` | 把 logo 裁切/遮罩成 `build.sh` 使用的 1024 px App 图标 |
| `project.yml` | App Store target 的 XcodeGen spec |
| `AgentRing.xcodeproj` | 生成的 Xcode 工程（App Store 打包） |
| `Configuration/` | Info.plist、App Sandbox entitlements 和隐私清单 |
| `Assets.xcassets` | AppIcon asset catalog |

App 是 `LSUIElement`：没有 Dock 图标。如果菜单栏图标没出现，请在 macOS「菜单栏」设置
以及 Thaw/Bartender/Ice 里允许 AgentRing 显示。

界面默认跟随系统语言，可在 **通用 → 语言** 切换。静态文案在两个 `.lproj` 文件里以中文
源串为 key；运行时文案（计数、守护进程标签、状态）走 `L10n`。新增可见文案需要同时提供
中文 key 和英文值。
