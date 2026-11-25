# AgentRingCore

[中文](README.zh.md) · [English](README.md)

AgentRing 状态模型的 Swift 版本，供 App Store 版 App 共用。第一块是每个会话的状态机；
frame 渲染、HTTP/TCP 服务和演示时钟随后补上。

```sh
swift test --package-path macos/AgentRingCore
```

状态机接受与 daemon 相同的事件词汇（`session-start`、`turn-start`、`tool-start`、
`tool-end`、`waiting`、`turn-end`、`error`、`session-end`、`control`），并实现完成停留、
静默降级、空闲 TTL、session-end 宽限和乱序保护。
