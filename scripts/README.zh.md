# 脚本

[中文](README.zh.md) · [English](README.md)

macOS 上的用户级安装辅助脚本。所有脚本都是幂等的，移动仓库目录后重新运行也安全。

| 脚本 | 作用 |
|---|---|
| `install-daemon.mjs` | 写入 `~/Library/LaunchAgents/com.agentring.daemon.plist`，指向 `daemon/bin/agentringd.mjs`；并执行 bootout/bootstrap |
| `install-app.mjs` | 为 `/Applications/AgentRing.app` 写入 `com.agentring.app.plist`；正常退出后保持退出，崩溃则重新拉起 |
| `install-codex-hooks.mjs` | 可选：把 7 个 Codex hook 事件合并进 `~/.codex/hooks.json`（先备份；支持 `--uninstall`/`--dry-run`） |
| `install-claude-hooks.mjs` | 可选：把 Claude hook 事件（含用于报错态的 `StopFailure`）合并进 `~/.claude/settings.json`，保留其他 hook（先备份；支持 `--uninstall`/`--dry-run`） |
| `sync-version.mjs` | 让各 package 版本与根目录 `VERSION` 保持一致（CI 用 `--check`） |

daemon 的 LaunchAgent 会优先使用 Homebrew 提供的稳定 `node` wrapper，因此
`brew upgrade node` 不会弄坏这个任务。

`install-app.mjs` 期望 App 位于 `/Applications/AgentRing.app`（可用 `AGENTRING_APP`
覆盖）；先运行 `./macos/build.sh` 并把 bundle 拷到那里。两个 launchd 辅助脚本都支持
`--uninstall`。

hook 安装器也可以从 npm 调用：

```sh
npm run install:codex     # or uninstall:codex
npm run install:claude    # or uninstall:claude
```

App 的「来源」页可以一键运行同样的安装器；daemon 只会执行 `daemon/src/sources.mjs` 中
`BRIDGE_INSTALLERS` 列出的脚本。
