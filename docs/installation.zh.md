# 部署与安装

[中文](installation.zh.md) · [English](installation.md)

AgentRing 由四部分组成。只装第一部分也能用浏览器预览，但要看到灯环，四部分都得装。

| 组件 | 运行在 | 用途 |
|---|---|---|
| `agentringd` daemon | Mac | 状态机、渲染器、HTTP API 和帧流 |
| AgentRing.app | Mac | 菜单栏状态、设置和预览 |
| Agent 接入 | Mac | 向 daemon 上报 agent 活动 |
| ESP32-C3 灯环 | 局域网 | 物理的 24 颗灯珠显示 |

日常使用见[使用说明](usage.zh.md)；配置项和 HTTP 参考见[配置与 API](configuration.zh.md)。

## 环境要求

- macOS 14 或更新（daemon、App 和 hook 安装器都只支持 macOS）。
- Node.js 22+（`node --version`）。
- Xcode 命令行工具，供 `swift build` 使用。
- Python 3 + Pillow，用于生成 App 图标（`python3 -m pip install pillow`）。
- 刷固件需要 Arduino IDE 2.x，带 **esp32 by Espressif 3.x**，或使用带同一 core 的 `arduino-cli`。
- 硬件：ESP32-C3 开发板、24 × WS2812B 灯环、5 V 电源，接线见[硬件](hardware.zh.md)。

可选：DeepSeek Harness、ChatGPT/Codex 和 Claude Code，用于上报 agent 状态。

```sh
git clone <repo-url> AgentRing
cd AgentRing
node --version        # v22+
npm test              # daemon + DSH plugin tests, no dependencies to install
```

## 1. 启动 daemon

前台跑，先看一眼：

```sh
npm start             # http://127.0.0.1:7801
curl -s http://127.0.0.1:7801/health
```

后台常驻（推荐），通过用户级 LaunchAgent：

```sh
node scripts/install-daemon.mjs
# logs: ~/.agentring/daemon.log
```

`/health` 返回 daemon 版本、会话数、灯环帧流计数和当前预览（如果有）。浏览器预览在
`http://127.0.0.1:7801/`，显示的就是灯环收到的同一份字节。

daemon 和 hook 安装器共用 `~/.agentring/`：

| 路径 | 用途 |
|---|---|
| `config.json` | 显示/布局/动效/来源配置（v3） |
| `state.json` | 最近的会话，重启后恢复 |
| `daemon.log` | launchd 的 stdout/stderr，启动时截断到 10 MB |
| `hook.sh` / `hook.log` | Codex/Claude 安装器写入的共享 hook shim |

daemon 监听 `0.0.0.0:7801`（HTTP）和 `0.0.0.0:7802`（原始帧）。局域网只能访问
`/frame`、`/health` 和 7802 帧流；`/state`、`/config`、`/sources`、预览写操作和
所有写接口都只接受 loopback。既没有鉴权也没有 TLS，所以只把这些端口留在可信网络里。
见 [SECURITY.zh.md](../SECURITY.zh.md)。

## 2. 构建并安装 macOS App

```sh
./macos/build.sh
cp -R dist/AgentRing.app /Applications/
open /Applications/AgentRing.app
```

`build.sh` 编译 Swift Package、写入 `Info.plist`（版本取自 `VERSION`）、生成图标并对
bundle 做 ad-hoc 签名。App 是菜单栏工具（`LSUIElement`），没有 Dock 图标。

登录后保持运行（可选但推荐）：

```sh
node scripts/install-app.mjs
```

如果菜单栏图标被隐藏了，在 macOS **系统设置 → 菜单栏** 以及 Thaw、Bartender、Ice
这类菜单栏管理工具里允许 AgentRing 显示。用 `⌘,` 或菜单栏菜单都能打开设置窗口。

构建产物是 ad-hoc 签名。本机自建自用没问题；要把二进制分发给其他 Mac，需要
Developer ID 签名和公证。

验收：侧边栏显示“守护进程已连接”，**预览** 页能画出灯环。版本显示在侧边栏底部和
**通用 → 关于**（App 版本和 daemon 版本分开列）。

## 3. 接入 agent

![来源页](images/settings-sources.png)

打开 **来源** 页。它会检测已安装的工具及其 AgentRing 接入，并能为 Codex 和 Claude
Code 一键接入。

### DeepSeek Harness

DSH 插件就是本仓库里的一个本地 bundle：

```sh
dsh plugin --profile desktop add "$PWD/packages/dsh-plugin"
```

重启 DSH，或在 **Plugins** 里把 bundle 关/开一次。来源页应显示 DeepSeek Harness
**已接入**。可以用下面的命令确认事件是否到达：

```sh
grep -c 'ingest dsh/' ~/.agentring/daemon.log
```

请使用 DSH App 实际运行的 profile（桌面 App 是 `desktop`）；检测页会列出所有装了
该 bundle 的 profile。

### Codex

如果装了 ChatGPT/Codex 但缺少 hooks，来源页会显示 **未接入** 和 **一键接入** 按钮。
它会把 AgentRing 的七个 hook 事件合并进 `~/.codex/hooks.json`，先备份原文件，并保留
其他 hook。终端里也能执行同样的命令：

```sh
npm run install:codex       # node scripts/install-codex-hooks.mjs
npm run uninstall:codex
```

Codex 下次运行时可能会问一次是否信任 hook，同意即可。hook 只对本地执行的任务触发
——云端任务在远端运行，不会调用本地 hook。

### Claude Code

Claude Code 的 hook payload 结构相同，只是配置文件不同：

```sh
npm run install:claude      # node scripts/install-claude-hooks.mjs
npm run uninstall:claude
```

安装器会合并进 `~/.claude/settings.json`，保留已有 hook（包括 CodeIsland 等其他
接入），写入带时间戳的备份，并且可重复执行。来源页把同样的操作放在 **一键接入** 里。
Claude Code 可能会问一次是否信任新的 hook。

Claude Code 通过 `StopFailure` 上报开始、运行、等待、完成和失败的回合，所以 Claude 的
会话也能进入红色报错态。

### 其他 agent

任何能执行本地命令的工具都能上报事件：

```sh
curl -sS -X POST 'http://127.0.0.1:7801/ingest?source=myagent' \
  -H 'content-type: application/json' \
  -d '{"event":"thinking","session_id":"demo","cwd":"/tmp/demo","tool":"bash"}'
```

`event` 取值为 `session-start`、`turn-start`、`tool-start`、`tool-end`、`waiting`、
`turn-end`、`error`、`session-end` 或 `control`（存活检测）。`source` 用配置里
`sources` 下已有的名字，就能拿到它的颜色并在来源页出现开关；未知来源仍会以默认颜色
渲染。事件只接受 loopback，因此适配器必须跑在同一台 Mac 上。见
[配置与 API](configuration.zh.md#配置分组)。

## 4. 构建并配网灯环

按[硬件](hardware.zh.md)说明接好开发板和灯环：灯环 DIN 接 **GPIO10**，共地，灯环用
5 V 供电，数据线串 330 Ω，必要时加电平转换。

编译并烧录（Arduino IDE 2.x 或其内置 CLI）：

```sh
CLI="/Applications/Arduino IDE.app/Contents/Resources/app/lib/backend/resources/arduino-cli"
FQBN="esp32:esp32:esp32c3:CDCOnBoot=cdc,PartitionScheme=huge_app"

"$CLI" compile --fqbn "$FQBN" firmware/esp32/agentring_ring
"$CLI" upload  -p /dev/cu.usbmodemXXXX --fqbn "$FQBN" firmware/esp32/agentring_ring
```

首次启动时开发板会开一个配网热点 `AgentRing-XXXX`（信道 6），门户地址
`http://192.168.4.1/`。选 2.4 GHz 网络、保存，门户就会关闭。串口 115200 的兜底命令：

```text
wifi            serial provisioning
wifi portal     start the setup AP again
wifi status     show SSID / IP / RSSI / MAC
wifi clear      erase saved Wi-Fi
info            LED pin/count, frame interval, Wi-Fi state, portal URL
reboot
```

灯环通过 mDNS（`_agentring._tcp`）发现 daemon，并选择同网段的 IPv4。如果发现不稳定，
可以写死地址：

```c
// firmware/esp32/agentring_ring/config.h
#define AGENTRING_HOST "192.168.1.20"
```

灯环和 Mac 必须在同一网段，Mac 防火墙需要放行灯环访问 TCP `7802` 和 mDNS。验收：

```sh
curl -s http://127.0.0.1:7801/health | python3 -m json.tool
# streamClients: 1, streamFrames grows ~30/s, streamLastFrameFrom = ring IP
```

App 的 **通用 → 连接** 卡片会显示灯环 IP 和 fps。

## 5. 验收清单

- [ ] `curl /health` 返回 `ok: true`、版本号，且 `streamFrames` 持续增长。
- [ ] 侧边栏显示“守护进程已连接”和“灯环在线”。
- [ ] **来源** 页里所用工具至少有一个显示 **已接入**。
- [ ] **预览** 页列出会话，灯环显示对应的颜色/动效。
- [ ] **灯光 → 状态** 的动效能同时在屏幕和物理灯环上预览。
- [ ] 菜单栏项目显示活跃会话数和注意图标。

## 6. 升级

```sh
git pull
npm run version:check
npm test
./macos/build.sh
cp -R dist/AgentRing.app /Applications/       # quit the app first
node scripts/install-app.mjs                  # restart the LaunchAgent
launchctl kickstart -k gui/$(id -u)/com.agentring.daemon
```

配置 v2（AgentRing 0.2.x）会在 daemon 下次启动时自动迁移到 v3 并原地改写；旧的
theme/colour-mode 字段会被丢弃，可见效果保持不变。如果你自定义过颜色，跨 minor
升级前先备份 `~/.agentring/config.json`。hook 安装和 DSH 插件与 daemon 版本无关；
更新插件后重启 DSH。

## 7. 卸载

```sh
node scripts/install-claude-hooks.mjs --uninstall    # if installed
node scripts/install-codex-hooks.mjs --uninstall     # if installed
node scripts/install-app.mjs --uninstall
node scripts/install-daemon.mjs --uninstall
rm -rf /Applications/AgentRing.app
rm -rf ~/.agentring                                  # config, state, logs, hook shim
```

在 **Plugins** 里移除 DSH bundle（或执行
`dsh plugin --profile desktop remove @local/agentring-dsh`）。要让灯环退役，串口执行
`wifi clear`，然后重新烧写或擦除开发板。

## 8. 排错

| 现象 | 检查 |
|---|---|
| daemon 没在运行 | `launchctl print gui/$(id -u)/com.agentring.daemon` 和 `tail -50 ~/.agentring/daemon.log` |
| App 显示“守护进程未连接” | `curl http://127.0.0.1:7801/health`；可能是其他进程占用了 7801 |
| 灯环不亮 | 5 V 供电、共地、GPIO10、330 Ω，串口执行 `info` |
| 灯环显示蓝色离线图案 | `/health` 的 `streamClients` 应为 1；在 Mac 防火墙放行 TCP 7802 和 mDNS；灯环和 Mac 在同一网段 |
| 安装后 Codex/Claude 仍显示未接入 | 重新检测；确认 hooks 文件里含 `.agentring/hook.sh`；检查工具的 hook 信任提示 |
| hook 触发了但灯环还是空闲 | `tail ~/.agentring/hook.log` 看 shim 日志和 HTTP 状态；确认 daemon 在监听 7801 |
| Gatekeeper 拦截 App | 右键 → 打开，或 `xattr -dr com.apple.quarantine /Applications/AgentRing.app` |
| 灯环卡在预览 | 关闭设置窗口或等 45 秒；`curl -X DELETE http://127.0.0.1:7801/preview` |
