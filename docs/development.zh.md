# 开发

[中文](development.zh.md) · [English](development.md)

## 前置条件

- macOS 14+（App 和 LaunchAgent 辅助脚本都是 macOS 专用的）。
- Node.js 22+。
- Xcode 命令行工具（`swift`、`swiftc`、`iconutil`、`sips`）。
- Python 3 + Pillow，用于 `macos/make-icon.py`。
- 固件开发需要 Arduino IDE 2.x + esp32 core 3.x。
- 插件开发需要 DeepSeek Harness CLI（`dsh`）。

## 本地准备

```sh
git clone <repo-url> AgentRing
cd AgentRing
npm test
npm start
```

守护进程没有第三方依赖：Node 内置的 `http`、`fs` 和 `node:test` 就够了。App 是 `macos/` 下的一个 Swift Package。

## 本地化

App 内置简体中文和英文。静态文案放在 `macos/Resources/{en,zh-Hans}.lproj/Localizable.strings`，以中文源字符串作为键；`build.sh` 会把两个 `.lproj` 目录一起拷进 App bundle。运行时拼接的字符串（计数、状态、守护进程提供的动效名称）走 `Sources/AgentRing/Localization.swift` 里的 `L10n`。新增文案时要同时更新两个 `.strings` 文件，并用 `AGENTRING_LANGUAGE=en` 运行 App 检查英文布局。

## 测试

```sh
npm test                  # daemon + DSH plugin suites
```

测试覆盖状态机、事件映射、配置清洗、v2 → v3 配色迁移、等分（split）布局、配色/动效取值范围、agent 安装检测、接入安装器以及 HTTP API（包括仅 loopback 的读接口、预览覆盖和配置重置）。修复 `daemon/src/` 里的 bug 前，先补一个回归测试。

App 方面：

```sh
swift build -c release --package-path macos
swift test --package-path macos/AgentRingCore
./macos/build.sh
```

构建脚本会编译 SPM 可执行文件、打包 `Info.plist`、生成图标，并对 `dist/AgentRing.app` 做 ad-hoc 签名。

## 守护进程开发

- `daemon/src/state.mjs` — 事件词汇、状态机、TTL。
- `daemon/src/frame.mjs` — 纯渲染器：布局、会话配色、动效、伽马、功耗预算。
- `daemon/src/config.mjs` — v3 schema、默认值、v1/v2 迁移、清洗。
- `daemon/src/server.mjs` — HTTP 路由、鉴权边界、持久化触发点。
- `daemon/src/persist.mjs` — 原子写入 `state.json`。
- `daemon/src/host.mjs` — Codex 桌面端存活探测。
- `daemon/src/sources.mjs` — 为 `/sources` 提供各 agent 的安装/接入检测。
- `daemon/src/protocol.mjs` — 共享常量。

编辑时可以在前台运行守护进程：

```sh
node daemon/bin/agentringd.mjs --port 7801
```

## macOS App 开发

Swift 文件位于 `macos/Sources/AgentRing/`：

- `AgentRingApp.swift` — 菜单栏场景、设置窗口、App 代理。
- `DaemonModel.swift` — `/state`（1.5 秒）、`/health`（3 秒）、配置防抖。
- `SettingsView.swift` — 四页侧边栏外壳；`PreviewTab`（灯环 + 会话列表）、`LightingTab`、`SourcesTab` 和 `GeneralTab` 承载各页。
- `DesignSystem.swift` — 卡片、页头、滑杆、选项磁贴，以及各页共享的灯环舞台；`SettingsControls.swift` 保留会话行和徽标。
- `LightingTab.swift` — 灯光工作室外壳：常驻实时预览栏、分区栏和四张随分区变化的概览卡片；`LightingPanels.swift` 包含显示 / 待机 / 布局 / 状态面板以及配色磁贴。
- `SourcesTab.swift` — 各 agent 的安装/接入状态、来源开关与颜色，以及一键 hook 安装器（带复制回退）。
- `RingLayerView.swift` — 24 个 CALayer，由 `/frame` 以 30 fps 驱动。预览覆盖（`POST /preview`）会让 `/frame` 输出试听中的动效，因此预览栏和物理灯环保持一致。
- `Theme.swift` — 颜色、标签、SF Symbols。

截图和特定页面诊断时，可以用 `AGENTRING_TAB=options`（或 `sources`）、`AGENTRING_LIGHTING_SECTION=states` 以及（可选的）`AGENTRING_MOTION_PREVIEW=thinking:breathe` 启动 App。`AGENTRING_LANGUAGE=en` 可以预览英文界面而不改变已保存的偏好，`AGENTRING_WINDOW_HEIGHT=1150` 能让长页面放进一张截图。`AGENTRING_BASE=http://127.0.0.1:7803` 可以让 App 指向实验用的守护进程，以免影响真实灯环。

App 是菜单栏工具（`LSUIElement`），没有 Dock 图标。如果菜单栏图标被隐藏，请在 macOS 的“菜单栏”设置以及任何菜单栏管理工具（Thaw、Bartender、Ice）中允许 AgentRing 显示。

## DSH 插件开发

```sh
dsh plugin --profile desktop add "$PWD/packages/dsh-plugin"
```

profile 里存的是指向当前检出目录的符号链接。改完 `index.js` 后重启 DSH，或在 Plugins 里把 bundle 关/开一次。验证工具级事件：

```sh
grep -c 'ingest dsh/tool-start' ~/.agentring/daemon.log
```

插件只与 `127.0.0.1:7801` 通信，不涉及任何凭据。

## 固件开发

接线和烧录见[硬件](hardware.zh.md)。提交前先编译：

```sh
arduino-cli compile --fqbn "esp32:esp32:esp32c3:CDCOnBoot=cdc,PartitionScheme=huge_app" \
  firmware/esp32/agentring_ring
```

不要提交 `.bin` 产物。如果串口命令集或 NVS 键发生变化，请同步更新 `docs/hardware.zh.md` 和 `CHANGELOG.md`。

## 代码风格与提交

- JavaScript 两空格，Swift 四空格，C++ 两空格。
- 把纯逻辑放在 `daemon/src/`，以便脱离 HTTP 和定时器测试。
- 提交标题用 `fix(area): …` / `feat(area): …`，正文里说明*为什么*。
- CI 会运行 `npm test`（daemon + DSH 插件）、Swift 构建和 ESP32 固件编译；提 PR 前在本地跑同样的检查。
- 不要提交 Wi-Fi 凭据、token 或签名材料。

## 文档

- `README.md`（中文）和 `README.en.md`（英文）是入口和快速开始，要与界面保持同步。
- `docs/installation.zh.md` / `docs/installation.md` 负责部署、升级、卸载和安装排错；
  `docs/usage.zh.md` / `docs/usage.md` 负责界面和日常行为。
- 所有说明文档都有中英文两版，改动时两版一起更新；`CHANGELOG.md` 仍是英文发布记录。
- 任何配置字段、路由或渲染规则变化，都要同步修改 `docs/configuration.zh.md` /
  `docs/configuration.md` 和对应的 ADR。
- 截图放在 `docs/images/`。先重新构建 App，让侧边栏里的版本号是最新的，再用下面的环境变量钩子做确定性截图。

## 发布清单

1. 设置 `VERSION`，把 `CHANGELOG.md` 的 `[Unreleased]` 移到带日期的 `[x.y.z]` 段，更新 `SECURITY.md` 的支持版本表，然后运行 `npm run version:sync`。
2. 运行 `npm test` 和 `npm run version:check`。
3. 运行 `swift build -c release --package-path macos && ./macos/build.sh`，安装 App，确认侧边栏/关于页显示新的 App 与守护进程版本（`/health.version`）。
4. 编译固件；烧录并确认 `/health` 的 `streamFrames ≈ 30/s`。
5. 更新截图，以及任何提到版本号或界面的文档。
6. 打发布 tag；如果需要分发，附上压缩后的 `AgentRing.app`。
