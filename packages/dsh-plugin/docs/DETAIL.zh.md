# AgentRing 状态桥

[中文](DETAIL.zh.md) · [English](DETAIL.md)

把每个存活的 DeepSeek Harness agent 的生命周期上报给 AgentRing 守护进程，让 24 颗
WS2812B 灯珠的灯环一眼显示这台机器正在做什么。

## 上报内容

| Harness 事件 | 灯环状态 | 含义 |
|---|---|---|
| `agent/created` | idle | 会话已打开，但没有轮次在运行 |
| `agent/status` → `running` | thinking | agent 正在生成输出或调用工具 |
| `tools/pre-execute` | tool / editing + 工具名 | 一次工具调用开始；写文件的工具会变成 editing |
| `tools/post-execute` | thinking | 调用结束，工具名被清除 |
| `approval/request` | waiting | agent 卡在权限询问上 |
| `user-questions/request` | waiting | agent 卡在 `ask_user_question` 上 |
| `agent/status` → `idle` | done | 轮次结束（绿色闪烁，然后变暗） |
| `agent/error` | error | 轮次或步骤失败；保持红色直到下一个轮次 |
| `agent/disposed` | — | 会话关闭，它的弧段被释放 |

对存活 agent 每 30 秒发送一次心跳（`control`），这样长时间安静的轮次不会被误判为过期，
守护进程也能在重启后完成对账。所有事件共用一个 keep-alive HTTP 连接，这也保证了它们的
顺序。

### Waterfall 交互

`approval/request` 和 `user-questions/request` 是 Cordis waterfall 事件：第一个返回处理
结果的监听者会认领该请求，并短路它后面的所有监听者。桌面窗口的转发应答器在基础 bundle
阶段就已注册，早于这个 profile 插件，所以这里的普通监听者永远看不到 prompt。因此两个观察
者都用 `prepend` 注册，并立即调用 `next()`：界面仍掌握实际决定权，灯环同时显示
`waiting`；答案到达后，再在 `finally` 块里恢复为 `thinking`。

## 环境要求

守护进程必须监听 `127.0.0.1:7801`（可在 Harness 进程里用 `AGENTRING_PORT` 环境变量覆盖）。
从仓库启动它：

```sh
node daemon/bin/agentringd.mjs
```

## 对账

只靠状态变更还不够：插件（或守护进程）启动时已经存在的会话，要等到下一次状态变化才会出现。
因此插件每 30 秒把 `ctx.agents.list()` 与守护进程的 `/state` 对比一次：

- 守护进程不认识的会话，用它的真实状态（`thinking` 或 `idle`）上报；
- 守护进程已认识的会话只会收到一次心跳，这样它不会因为空闲被清理，灯环显示的内容也不会
  改变；
- 守护进程重启后（状态为空），每个存活会话都会重新上报。

## 限制

- 不发送工具参数和 token 流；只发送工具名和生命周期状态。
- 事件是即发即忘的，超时 400 毫秒且不重试，所以守护进程宕机期间发出的事件会丢失（对账能
  恢复会话，但恢复不了漏掉的细节）。
- 守护进程绑定 `0.0.0.0`，让 ESP32 能轮询 `/frame`；修改类接口只接受 loopback 连接。
