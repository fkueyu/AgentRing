# AgentRing 守护进程

[中文](README.zh.md) · [English](README.md)

本地接入守护进程：接收 agent 事件、为每个会话保留一条记录、渲染灯环，并在
`127.0.0.1:7801` 提供 HTTP API。

```sh
npm start                 # from this directory
# or from the repository root:
node daemon/bin/agentringd.mjs --port 7801
```

| 路径 | 用途 |
|---|---|
| `bin/agentringd.mjs` | 入口：监听 `0.0.0.0:7801`，广播 mDNS |
| `bin/agentring-hook.sh` | Codex hook 的可选 curl 转发脚本 |
| `src/state.mjs` | 事件词汇、状态机、TTL |
| `src/frame.mjs` | 纯函数 24×RGB 渲染器 |
| `src/config.mjs` | v2 配置、主题、清洗 |
| `src/server.mjs` | HTTP 路由与持久化触发 |
| `src/stream.mjs` | 端口 7802 上的持久 72 字节 TCP 帧流 |
| `src/persist.mjs` | 原子写入 `state.json` |
| `src/host.mjs` | Codex Desktop 存活探测 |
| `src/protocol.mjs` | 共享常量 |
| `test/` | `node --test` 测试套件 |
| `preview/index.html` | 在 `/` 提供的浏览器预览 |

配置与 API 细节：[docs/configuration.zh.md](../docs/configuration.zh.md)。
