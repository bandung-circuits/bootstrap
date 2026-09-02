# dsh 方案设计决策记录

> 与 `design-vscode.md`（VS Code + Claude Code 方案）平行。本文件记录 DeepSeek Harness（`dsh`）方案的决策与踩坑。dsh 是 DeepSeek 官方开源 agent harness，dev preview，**schema 会破坏性变更**，所有版本务必钉死（见"版本钉死"节）。

## 目标与定位

一条命令（Linux/macOS/WSL 的 `dsh/install.sh`、Windows 的 `dsh/install.ps1`）给零 IT 背景用户搭好：

- **DeepSeek Harness（dsh）Web UI**：浏览器打开即用（`http://127.0.0.1:3080`），无需装 VS Code。
- **后端模型 DeepSeek V4 Flash 0731**：按区域路由到百炼（国内）/ 百炼国际（国外），备选 DeepSeek 官方 / OpenRouter。
- **crawl4ai MCP**：经官方 `@deepseek-ai/dsh-mcp-client` 启用（免费无 key）。
- **`~/ai-workspace` 一个文件夹即环境**：AGENTS.md（工作区约定）+ README + NEXT-STEPS + 启动器 + `.dsh/`（harness 家目录）。

**站点定位**：dsh 是**首选**（免费、开源、浏览器即用、无需先装软件、适合零基础）；vscode 方案是**后备**（给已装 VS Code、想留在 IDE 里的用户）。仓库体现上两者对称并列（`vscode/` 与 `dsh/`），站点呈现上分主次。

## 为什么 dsh 而不是只做 CLI / TUI

dsh Web UI 是浏览器界面，新手动线最短：双击启动器 → 浏览器打开 → 选工作区 → 打字问 AI。没有 IDE 安装、没有 PATH、没有窗口布局学习成本。CLI/headless/TUI/SDK 模式留给进阶，不在 bootstrap 范围内（subagent `--profile headless` 在 CI 里做冒烟可用）。

## 核心技术机制

- **安装**：Node（`^22.19.0 || >=24.0.0`，钉 LTS v24 大版本、装 `~/.local/nodejs` 免 sudo）+ `npm install -g --prefix ~/.local @deepseek-ai/dsh@0.1.1-rc.2`（钉死 rc 版）。`start-dsh` 启动器 pre-pend `~/.local/bin` 与 `~/.local/nodejs/bin` 到 PATH，避免用户终端 PATH 问题。
- **$DSH_HOME 在工作区内**（用户拍板）：`~/ai-workspace/.dsh`。动机：与 vscode 方案 `~/ai-workspace/.claude` 一致，整个环境一个文件夹、拷走即用。代价（已知 & 文档化）：agent 的工作树里躺着 harness 自己的配置，AGENTS.md 明文告诫"never edit files under `.dsh/`"，`.gitignore` 整目录忽略 `.dsh/`。换机器恢复 = 拷贝文件夹 或 重跑一条 bootstrap。
- **模型路由**：`$DSH_HOME/settings.yaml` 的 `llm-pi-ai.providers.<id>`（pi-ai 适配器）。route = `{apiKeyEnv, api, baseURL, models:[...]}`；API key 经 `apiKeyEnv: DSH_API_KEY` 引用，密钥本体写 `$DSH_HOME/.env`（dsh 官方文档明确 `$DSH_HOME/.env` 是普通启动环境层，会读取）。
- **约定文件**：workspace 根 `AGENTS.md`（dsh 官方 `@deepseek-ai/dsh-agent-instructions` 插件会注入 AGENTS.md），当前为人工草稿，后续迭代继续完善（web tooling、安全默认、打包等留 scope note）。
- **crawl4ai MCP（官方 mcp-client，不装第三方插件）**：CLI reference 原文——"The CLI also ships `@deepseek-ai/dsh-mcp-client` as a dependency for patch layers, but no MCP server is enabled by default"。所以**不需要 `dsh plugin add`**，只要在 `$DSH_HOME/cordis.patch.yml`（home 层，所有 profile 生效）写一行：

  ```yaml
  - insert:
      - id: mcp-crawl4ai
        name: '@deepseek-ai/dsh-mcp-client'
        config:
          serverName: crawl4ai
          transport: stdio
          command: uvx
          args: ['--from', 'crawl4ai-search-mcp==0.1.1', 'crawl4ai-search']
  ```

  一行实例 = 一个 server；工具注册为 `mcp__crawl4ai__*`。行文本收在 `dsh/templates/dsh-home/cordis.patch.yml`（完整模板）与 `crawl4ai-row.yml`（已有自定义 patch 时追加用），**脚本内不嵌配置**。

- **安全默认**：新会话默认 `workspace-write` 权限预设（官方默认），改动限制在会话工作区；读写与网络不受困（官方文档明言）。crawl4ai server 命令跑在 agent 沙箱外，只 enable 钉死的可信可执行（uvx + 钉版包），并在 patch 注释里写明。

## 静态模板原则（本方案 + vscode 方案共同遵循）

所有种子文件都是 `templates/` 下的真实文件，安装器只做两件事：

1. **拷贝**（目标不存在时，重跑不覆盖用户改动）；
2. **占位符替换**（`{{PROVIDER_ID}}`/`{{PROVIDER_BASE_URL}}`/`{{PROVIDER_MODEL}}`/`{{PROVIDER_API}}`/`{{COMPAT_BLOCK}}`/`{{PROVIDER_NAME}}`/`{{PROVIDER_SITE}}`/`{{DSH_API_KEY}}`）。

不做的事：不在 shell/PS 代码里嵌 heredoc/内联配置。改配置 = 改模板文件，一行 diff，可 review、可复用。piped（curl|bash）场景由 install 脚本按清单从 Pages 域名拉模板文件。

## 平台矩阵

| 平台 | 安装路径 | Node | dsh | 状态 |
|---|---|---|---|---|
| Linux x64/arm64 | `dsh/install.sh` | `~/.local/nodejs`（钉 v24 LTS） | `npm -g --prefix ~/.local` 钉版 | CI（VMware Linux）兜底 |
| macOS arm64/x64 | 同上 | 同上 | 同上 | 本机验证（作者机） |
| Windows (+WSL) | `dsh/install.ps1`；WSL 直接跑 install.sh | winget `OpenJS.NodeJS.LTS` | `npm -g` 钉版 | **Windows VM 暂缓**（Fusion macOS 26.1 跑 Windows VM 有坑，同 design-vscode），脚本已备、待 VM 恢复后 CI |
| WSL | `dsh/install.sh`（detect 已识别 wsl，无 IDE 依赖，不需独立 install-wsl） | 同上（Linux 侧） | 同上 | 同上 |

## 版本钉死（dev preview 纪律）

| 组件 | 钉 | 备注 |
|---|---|---|
| `@deepseek-ai/dsh` | `0.1.1-rc.2` | npm 最新 rc；源码 0.1.0-rc.5 被第三方在 macOS 验证；npm 安装路径由本机 CLI 冒烟验证 |
| Node | LTS v24 大版本，安装时解析最新 patch（`nodejs.org/dist/index.json`） | 引擎要求 `^22.19.0 || >=24.0.0` |
| `crawl4ai-search-mcp` | `==0.1.1` | 与 vscode 方案同包同版本 |
| `uv/uvx` | 随 astral 官方安装器 | 首次调用云端拉预构建环境 |

回滚 = 重跑 bootstrap（幂等、保留已改文件）或 `npm install -g @deepseek-ai/dsh@<旧版>`。

## 关键坑 / 待核实（实施时已/需实测）

- **pi-ai 的 `api:` 协议名**：Anthropic 兼容端点（百炼 `/apps/anthropic`、DeepSeek `/anthropic`）用 `api: anthropic`；OpenRouter 用 `api: openai-completions`。provers.md 的官方逃生路线：OpenAI 兼容网关拒 developer role / 只认 `max_tokens` 时加 `compat: {supportsDeveloperRole: false, maxTokensField: max_tokens}`（openrouter 已预置）。
  - **实测方法**：`DSH_HOME=~/ai-workspace/.dsh dsh web --dump-config` 看 `llm-pi-ai` 段 + 真实 key 首条消息。**若 `anthropic` 协议名不存在**，generated `dsh-llm-pi-ai` 配置目录是最新权威，改 `dsh/lib/providers.sh` 一处 + 重测。
- **预播种 `$DSH_HOME` 与 web profile 自动初始化**：首次 `dsh web` 会按 shipped 模板初始化 `$DSH_HOME/profiles/web`。预播种只写 home 层（settings.yaml / cordis.patch.yml / .env），不与 profile 目录冲突；`--dump-config` 已作为安装器最后一步冒烟。若某版本 profile 初始化与预播种文件互踩，改 seed 顺序（先 `dsh web --dump-config` 触发初始化，再写配置）。
- **凭据注入**：走 `$DSH_HOME/.env` + `apiKeyEnv` 引用（官方文档确认 dsh 读 `$DSH_HOME/.env`）。若未来版本不再读，逃生：改让启动器 source .env 或走 UI Settings → Models 由 dsh 写 `.credentials.yaml`。
- **Windows**：winget Node + `npm -g`（Windows 默认用户前缀可写）。未实测，见平台矩阵。
- **首次启动时间**：`dsh web` 首次要建 profile + 拉 crawl4ai（uvx 首调），NEXT-STEPS 有提示。

## 复用关系（与 vscode 方案）

- **共享**：根 `lib/detect.sh`（os/arch/region/pkg-mgr）；provider 路由认知（百炼/百炼国际/DeepSeek/OpenRouter 的 baseURL+model，写进各自 lib/providers.sh，url/model 与 vscode 一致，另加 `api`/`compat` 列）；crawl4ai `==0.1.1` 包与 uvx 用法；CI 的 VMware 宿主骨架与 `.env`；Pages 发布管道（install 脚本经 `github.io` 下发，国内可达）。
- **各自独立**：安装逻辑（Node/npm vs VS Code 扩展）、配置形态（settings.yaml+cordis.patch.yml vs settings.local.json+.mcp.json）、约定文件（AGENTS.md vs CLAUDE.md）、各方案的 lib/ 与 templates/、CI verify 脚本（`vscode/ci/verify` 与 `dsh/ci/verify`）。
- **站点**：dsh 首选、vscode 后备（见根 `index.html`），两条路径共用 `~/ai-workspace`，README 与 NEXT-STEPS 引导。

## 实施记录

- 2026-09-02 目录结构、静态模板、官方 mcp-client 启用、$DSH_HOME 工作区内、平台与版本矩阵落地（Phase A/B 已提交）。待办：Windows VM CI 恢复、pi-ai `api:` 协议名实测（见"待核实"）。