# AgentRing DSH 插件

[中文](README.zh.md) · [English](README.md)

一个 DeepSeek Harness Host 插件，把 agent 的生命周期、工具调用、审批和用户提问上报给
本机 AgentRing daemon。

```sh
dsh plugin --profile desktop add "$PWD/packages/dsh-plugin"
```

profile 里保存的是指向这份代码的链接。Host 插件没有 HMR：改完 `index.js` 后要重启 DSH，
或者在 Plugins 里把 bundle 关/开一次。

事件映射与对账逻辑见 [`docs/DETAIL.zh.md`](docs/DETAIL.zh.md)。daemon 必须监听
`127.0.0.1:7801`（可在 Harness 进程里用 `AGENTRING_PORT` 覆盖）。
