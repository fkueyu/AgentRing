# 安全策略

[中文](SECURITY.zh.md) · [English](SECURITY.md)

## 支持版本

| 版本 | 是否支持 |
|---|---|
| 0.4.x | 是 |
| 0.3.x | 否 |
| 0.2.x | 否 |
| 0.1.x | 否 |

## 报告漏洞

安全漏洞请不要开公开 issue。请使用仓库的私有安全公告表单，或通过仓库资料页上列出的地址
联系维护者。请说明受影响的组件（daemon、App、DSH 插件或固件）、最小复现步骤和影响。

## 威胁模型

AgentRing 是本地优先的工具，不是互联网服务。

- daemon 的 HTTP 监听 `0.0.0.0:7801`，原始帧流监听 `0.0.0.0:7802`。其他主机只能访问
  `/frame`、`/health` 和只读的 7802 帧流；浏览器预览、`/state`、`/config`、`/sources`
  以及 `/preview` 的修改操作和所有写接口都只接受 loopback。没有鉴权，也没有 TLS。
- `/sources` 会向 loopback 客户端暴露本地安装路径和 profile/bundle 名称。
  `/sources/<id>/install` 只运行 AgentRing 自己的 hook 安装器
  （`scripts/install-*-hooks.mjs`），绝不会执行探针给出的任意命令。它以当前用户身份
  修改 `~/.codex/hooks.json` 或 `~/.claude/settings.json`，并在文件旁写一份带时间戳的
  备份。
- `POST /preview` / `DELETE /preview` 会临时覆盖灯环显示的内容。本机任何进程都可以调用，
  覆盖最迟会在 TTL 到期后失效。
- 不要把 `7801` 端口暴露到公网或不可信网络。如果需要远程访问，请把它放到带鉴权和 TLS 的
  VPN/反向代理后面。
- 固件配网 AP 默认开放，且只在设备没有可用 Wi-Fi 配置时存在。想要加密的配网 AP，可在
  `firmware/esp32/agentring_ring/config.h` 里设置 `AP_PASSWORD`。
- Wi-Fi 凭据以明文存放在 ESP32 NVS 中，这是 Arduino/ESP-IDF 配网的常规做法。能物理接触
  开发板的人可以读取或替换它们。
- DSH 插件只向 `127.0.0.1` 发送生命周期元数据（来源、会话 id、cwd、工具名和状态），
  不发送 prompt、文件内容或模型输出。
