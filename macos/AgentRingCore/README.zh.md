# AgentRingCore

[中文](README.zh.md) · [English](README.md)

AgentRing 状态与配置模型的 Swift 版本，供 App Store 版 App 共用。第一块是每个会话的
状态机，第二块是 v3 `RingConfig`；frame 渲染、HTTP/TCP 服务和演示时钟随后补上。

```sh
swift test --package-path macos/AgentRingCore
```

状态机接受与 daemon 相同的事件词汇（`session-start`、`turn-start`、`tool-start`、
`tool-end`、`waiting`、`turn-end`、`error`、`session-end`、`control`），并实现完成停留、
静默降级、空闲 TTL、session-end 宽限和乱序保护。`RingConfig` 对齐 daemon 的 v3 范围、
默认值，以及颜色/动效/来源的回退规则。共 20 个 XCTest 用例（`swift test`）。
