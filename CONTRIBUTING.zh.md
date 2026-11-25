# 为 AgentRing 做贡献

[中文](CONTRIBUTING.zh.md) · [English](CONTRIBUTING.md)

感谢你花时间改进 AgentRing。这个项目有四个相互关联的部分；请把改动限制在局部，方便
审查和测试。

## 仓库结构

| 路径 | 内容 |
|---|---|
| `daemon/` | Node.js 状态机、帧渲染器、HTTP API 与测试 |
| `macos/` | 原生 SwiftUI 菜单栏 App（Swift Package Manager） |
| `packages/dsh-plugin/` | DeepSeek Harness Host 插件 |
| `firmware/esp32/agentring_ring/` | ESP32-C3 Arduino sketch |
| `scripts/` | launchd 与 Codex/Claude hook 安装辅助脚本 |
| `docs/` | 部署、使用、架构、配置、硬件、开发与决策 |
| `tools/` | 本地小工具（ASCII 灯环预览、PNG 渲染） |

## 环境要求

- App 与 daemon 需要 macOS 14 或更新版本。
- daemon 与脚本需要 Node.js 22+（无需 `npm install`；daemon 无第三方依赖）。
- `swift build` 需要 Xcode 命令行工具；App 图标生成流程还需要 Python 3 + Pillow
  （`python3 -m pip install pillow`）。
- 固件开发需要 Arduino IDE 2.x 与 **esp32 by Espressif 3.x**。
- 只有开发 DSH 插件时才需要 DeepSeek Harness CLI（`dsh`）。

## 初始设置

```sh
git clone <repo-url> AgentRing
cd AgentRing
npm test                        # daemon + DSH plugin tests
npm start                       # run the daemon on 127.0.0.1:7801
./macos/build.sh                # build dist/AgentRing.app
```

App 通过 `http://127.0.0.1:7801` 读取 daemon。只有在希望它们后台常驻时才安装用户级
LaunchAgent：

```sh
node scripts/install-daemon.mjs
node scripts/install-app.mjs
```

## 代码风格

- **JavaScript**：ES module，两空格缩进，可以不加分号，但同一文件内保持既有风格。尽量把
  小而纯的函数放进 `daemon/src/`，让状态机和渲染器不依赖 HTTP 或定时器也能测试。
- **Swift**：四空格缩进，对不直观的公开行为写 `///` 文档注释，长文件用 `// MARK:` 分段。
  保持 App 原生：不用 web view，不引入第三方 UI 依赖。
- **固件**：两空格缩进，注释解释硬件行为，而不是复述代码。除官方 esp32 core 外，sketch
  不引入其他依赖。
- **Markdown**：正文按合理宽度换行；使用相对链接。
- 绝不提交 Wi-Fi 凭据、API key、token 或签名材料。Wi-Fi 在运行时配网并存放在 NVS。

## 测试

- daemon + 插件：`npm test`（运行 `daemon/test/` 和 `packages/dsh-plugin/test/`）。每个
  状态机、配置、渲染器、来源检测或安装器修复都要补一个回归测试。
- App：`swift build -c release --package-path macos`，并手动过一遍
  **预览 / 灯光 / 来源 / 通用**。
- 固件：`arduino-cli compile --fqbn "esp32:esp32:esp32c3:CDCOnBoot=cdc,PartitionScheme=huge_app" firmware/esp32/agentring_ring`，
  有硬件时再做烧录 + 串口检查。CI 使用 ESP32 core 3.3.12 编译。

## DSH 插件改动

插件从这份代码安装进 DSH profile：

```sh
dsh plugin --profile desktop add "$PWD/packages/dsh-plugin"
```

Host 插件在进程内加载。改完 `index.js` 后，重启 DSH 或在 Plugins 里把 bundle 关/开一次
即可重载。用下面的命令确认：

```sh
grep -c 'ingest dsh/tool-start' ~/.agentring/daemon.log
```

## Hook 安装器改动

Codex 与 Claude Code 共用同一个 hook shim（`daemon/bin/agentring-hook.sh`），但安装器是
分开的：

- `scripts/install-codex-hooks.mjs` → `~/.codex/hooks.json`
- `scripts/install-claude-hooks.mjs` → `~/.claude/settings.json`

两个安装器都要保持幂等、保留其他集成写入的 hook、在改动文件前写带时间戳的备份，并支持
`--uninstall` 和 `--dry-run`。`daemon/test/installers.test.mjs` 覆盖合并、幂等和卸载
路径；安装路由由 `daemon/test/server-api.test.mjs` 覆盖。来源页只能运行
`daemon/src/sources.mjs` 中 `BRIDGE_INSTALLERS` 列出的脚本。

## 文档

- 用户可见的改动要同步更新 [README.md](README.md)、`docs/` 和 `CHANGELOG.md`。
- 新的配置项或 HTTP 路由应写进[配置与 API](docs/configuration.zh.md)；否则会被反复争论的
  设计决策应写进[决策](docs/decisions.zh.md)。
- 部署、升级和安装排错写进[部署指南](docs/installation.zh.md)；界面和日常行为写进
  [使用说明](docs/usage.zh.md)。
- 界面文案放在 `macos/Resources/{en,zh-Hans}.lproj/Localizable.strings`；每个新字符串都要
  补中文 key 和英文值。运行时字符串（计数、daemon 标签）统一走 `Localization.swift` 里的
  `L10n`。
- 截图放在 `docs/images/`。先重新构建 App，保证侧栏里的版本号是最新的；`AGENTRING_TAB`、
  `AGENTRING_BASE`、`AGENTRING_LANGUAGE` 和 `AGENTRING_WINDOW_HEIGHT` 这几个截图钩子见
  [开发](docs/development.zh.md)。
- 所有说明文档都有中英文两版：`README.md` / `README.en.md`、`docs/*.md` / `docs/*.zh.md`、
  各组件 README、`CONTRIBUTING`、`SECURITY` 和 `CODE_OF_CONDUCT`。改文案时两版要一起更新；
  `CHANGELOG.md` 仍是英文发布记录。

## 固件改动

- `LED_GPIO`/`LED_COUNT` 和配网流程要在[硬件](docs/hardware.zh.md)中有记录。
- 提交前先编译。不要提交生成的 `.bin` 文件。
- 如果改动影响串口协议或 NVS key，要在 PR 里说明并更新 `CHANGELOG.md`。

## 发布

1. 更新 `VERSION`，把 `CHANGELOG.md` 里的 `[Unreleased]` 改成带日期的 `[x.y.z]` 段落，
   更新 [SECURITY.zh.md](SECURITY.zh.md) 里的支持版本表，然后运行 `npm run version:sync`。
2. `npm test`、`npm run version:check`，再对 App 做一次 release 构建。
3. 安装 App，确认 **通用 → 关于** 显示新的 App 和 daemon 版本；如果固件协议有变化，重新
   刷写固件。
4. 更新截图，以及所有提到版本号或界面的文档。
5. 打发布 tag（`vX.Y.Z`）；只有在分发签名构建时才附带构建产物。

## 提交与 Pull Request

- 每个提交只包含一个逻辑改动。
- 标题用祈使句，例如 `fix(daemon): keep error state until the next turn`。
- 正文解释**为什么**，而不只是改了什么。
- 用户可见的改动要更新 `CHANGELOG.md`。
- 在 PR 描述里写清你跑过的命令和结果。

## 许可证

提交贡献即表示你同意你的贡献按 `LICENSE` 中的 MIT 许可证授权。
