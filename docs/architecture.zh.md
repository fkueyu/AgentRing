# 架构

[中文](architecture.zh.md) · [English](architecture.md)

AgentRing 只做一件事：把本机 agent 的活动变成一个简短、可读的灯光信号。所有设计都在为这条链路足够短、可观测、可测试而优化。

## 组件

| 组件 | 路径 | 职责 |
|---|---|---|
| 守护进程 | `daemon/` | 接收事件、维护每个会话的状态、渲染 24 颗 RGB 灯珠、提供 HTTP 服务 |
| DSH 插件 | `packages/dsh-plugin/` | 把 DeepSeek Harness 的生命周期与工具事件转换为守护进程事件 |
| Codex hooks | `daemon/bin/agentring-hook.sh` + `scripts/install-codex-hooks.mjs` | 可选的 curl 适配层（默认不安装） |
| macOS App | `macos/` | 菜单栏入口、预览、会话列表、显示设置、灯环健康状态 |
| 固件 | `firmware/esp32/agentring_ring/` | Wi-Fi 配网、mDNS 发现、持久 TCP 帧流、WS2812 输出 |
| 预览 | `daemon/preview/index.html` | 不装 App 也能调试的浏览器回退页面 |

## 数据流

```text
DSH plugin ── HTTP POST /ingest ──┐
Codex hooks ── curl ──────────────┤
                                  ▼
                          daemon/src/state.mjs
                                  │ snapshot
                                  ▼
                          daemon/src/frame.mjs
                                  │ 72 bytes
              ┌───────────────────┼───────────────────┐
              ▼                   ▼                   ▼
        macos app preview     browser preview      ESP32 TCP stream
        (URLSession 30 fps)   (canvas 20 fps)      (72B @30 fps)
```

守护进程是唯一的渲染器。App 和固件读取的是同一份 `renderFrame` 字节（App 走 HTTP `/frame`，ESP32 走 TCP 帧流），因此固件改动不会在算法层面与预览产生偏差。App 为屏幕额外加了一层光晕/透明度表现；物理灯带显示的是原始 8 位 RGB。

## 状态模型

`daemon/src/state.mjs` 只暴露一套很小的词汇：

```text
session-start | turn-start | thinking | tool-start | tool-end
waiting | turn-end | error | session-end | control
```

每条记录以 `source:sessionId` 为键（取不到时回退到 cwd），包含 `source`、`sessionId`、`cwd`、`label`、`tool`、`state`、`since`、`updated` 和 `ended`。`snapshot()` 负责应用基于时间的状态迁移：

- `done` 在 `doneHoldSeconds` 之后变为 `idle`。
- 处于工作状态的会话（`thinking` / `tool` / `editing`）若在 `staleMinutes` 内没有任何事件，会静默降级为 `idle`；`waiting` 不在此列，因为权限提示可能合法地等待数小时。
- `session-end` 会让已结束的记录多保留一小段宽限期，这样桌面 agent 每轮都关闭 hook 会话时，灯环不会闪烁。
- 心跳（`control`）只刷新 `updated`，不会创建或复活会话。

灯环的优先级为 `waiting > error > editing > tool > thinking > done > idle`。

## 渲染

`daemon/src/frame.mjs` 是纯函数：输入快照 + 配置 + `now`，输出 `Uint8Array(72)`。

- **布局**：`split`（等分）把灯环分给最紧急的 N 个会话，`focus`（聚焦）只显示最紧急的一个，`rotate`（轮播）一次只显示一个会话并循环切换。
- **动效**：`pulse`、`breathe`、`solid`、`comet`（巡游）、`blink`、`flash` 和 `patches`（雨滴）。comet 使用亚灯珠的高斯头部和 smoothstep 尾部，峰值会在灯珠之间平滑滑动，而不是逐颗跳变。
- **颜色**：一套会话配色决定运行中的外观——身份配色（`state`、`source`）、环绕灯环铺开的精选渐变，或彩虹色轮。等待审批/完成/报错始终保留各自的语义状态色。
- **功耗**：当估算的 WS2812 电流超过预算时，`currentLimitMa` 会把整帧按比例压暗。
- **待机**：动效（`dot`、`orbit`、`breathe`）与颜色（`mono` 以及共享的精选渐变和 `rainbow`）是两个独立的维度。orbit 的头部位置带小数偏移，尾部很短；breathe 让相邻的呼吸重叠。只有 mono 会显示取色器。旧的 `rainbow` 模式会迁移为 `orbit` + 彩虹配色。
- **夜间模式**：在本地时间窗口内按比例降低整帧亮度。
- **效果预览**：`GET /preview?state=&effect=` 用同一条管线渲染一帧合成的 agent 画面。`POST /preview` 把该 state/effect 安装为临时覆盖（带 TTL，由 App 续期），`/frame` 和 7802 帧流都会输出它，因此物理灯环会同步显示试听效果；`DELETE /preview` 恢复实时快照。预览栏始终读取 `/frame`，所以不会与灯环不一致。

所有输出都是 8 位 RGB。固件会转换为 GRB，并把缓冲区交给 ESP32 的 RMT 外设。

## 来源检测

`daemon/src/sources.mjs` 是一个很小的探针注册表，每个 agent 工具对应一个探针。探针回答两个相互独立的问题：工具是否已安装（应用包、数据目录或 CLI），以及接入是否已安装（DSH profile bundle 及其 `node_modules` 链接、Codex / Claude hooks 文件及 hook 转发脚本）。它只读文件。缺失的 hook 可以从页面安装：守护进程运行 AgentRing 自己的安装脚本（按来源注册）并重新探测；而探针的展示命令（例如 DSH 的包管理器命令）始终只能复制。

运行中的 DSH 桌面 profile 从宿主进程参数解析得到，因此装在非当前 profile 里的插件会被报告为不匹配，而不是误报成功。`GET /sources` 仅限 loopback，因为返回内容包含本机路径；来源页会把它与 `/state` 合并来显示当前会话。以后新增 agent 只需要一个探针加一个标签；`/ingest` 始终是通用、与工具无关的事件契约。

## DSH 插件

插件是 Host 插件，运行在 DSH 进程内，向 `127.0.0.1:7801` 发送即发即忘的 HTTP 事件：

- `agent/created` → `session-start`
- `agent/status` → 运行中发 `thinking`，空闲时发 `turn-end`
- `tools/pre-execute` / `tools/post-execute` → `tool-start` / `thinking`
- `approval/request` → `waiting`，决策后发 `thinking`
- `user-questions/request` → `waiting`，回答后发 `thinking`
- `agent/error` → `error`
- `agent/disposed` → `session-end`

它每 30 秒用 `ctx.agents.list()` 与 `/state` 对账一次，并为已知会话发送心跳。单个 keep-alive socket 保证事件顺序，并避免每次状态切换都做一次 TCP 握手。Host 插件没有 HMR：改完 `index.js` 后需要重启 DSH，或在 Plugins 里把 bundle 关/开一次。

## macOS App

`macos/Sources/AgentRing/` 是一个原生 SwiftUI 菜单栏 App：

- `AgentRingApp.swift` — `MenuBarExtra`、设置窗口、App 代理。
- `DaemonModel.swift` — 每 1.5 秒轮询 `/state`，每 3 秒轮询 `/health`，连接时获取 `/capabilities`，配置变更以 350 毫秒防抖推送，并计算活跃/等待/报错计数。
- `AgentRingSession.swift` — 无缓存、无 Cookie 的 ephemeral URLSession。共享的 CFNetwork session 会让 macOS 在每次请求时短暂持有 `PreventUserIdleSystemSleep` 断言；一个状态类 App 不应该让 Mac 保持唤醒。
- `SettingsView.swift` — 四页侧边栏外壳（预览、灯光、来源、通用）。预览页把灯环主视图放在顶部，实时会话列表放在下方；灯光页保留常驻灯环栏，并把控件拆成显示、待机、布局和状态（会话配色 + 各状态动效/速度 + 时序）；来源页包含各 agent 的安装/接入状态、灯环开关和取色器。
- `RingLayerView.swift` — 使用 `/frame` 和 24 个 CALayer 的预览渲染器。
- `Theme.swift` — 状态标签/符号/颜色，以及菜单栏图标。
- `MenuBarIcon.swift` — 加载构建时生成、供菜单栏使用的模板灯环图标。

App 从不直接读取 agent 内部状态；它只是守护进程 API 之上的一层视图。`ringConnected` 由 `/health` 的局域网帧计数推导，所以“守护进程在线”和“物理灯环正在收帧”是两个独立状态。

## 固件

`firmware/esp32/agentring_ring/` 是面向 ESP32-C3 的 Arduino sketch，拆分为 `leds`、`portal_ui` 和 `ring_client` 三个模块：

- 从 NVS 读取 Wi-Fi 凭据；如果没有凭据或连接失败，就在 `192.168.4.1` 启动 SoftAP 强制门户（captive portal）。
- 用 mDNS 解析 `_agentring._tcp`，并选择**同一网段的 IPv4** 地址（Mac 也可能暴露网桥/Tailscale 地址）。
- 只连接一次守护进程 7802 端口上的原始 TCP 帧流，然后持续读取 72 字节帧；不会每帧发一次 HTTP 请求。
- 短读时重连；守护进程重启或网络中断都不会让灯环卡死。
- 把 RGB 转换为 GRB，通过 ESP-IDF 的 RMT 外设驱动灯带。
- Wi-Fi 或守护进程不可用时，回退到暗淡的离线图案。

轮询、固件 HTTP 与 OTA 的取舍见[架构决策](decisions.zh.md)。
