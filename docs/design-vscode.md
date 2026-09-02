# 设计决策记录（vscode 方案）

> 本记录对应 **VS Code + Claude Code** 方案。该方案在仓库 `vscode/` 子树内（安装入口 `vscode/install.sh` / `install.ps1` / `install-wsl.sh`，lib 在 `vscode/lib/`，静态种子模板在 `vscode/templates/workspace/`，provider 指南与 golden state 在 `vscode/providers/`、`vscode/wip/`，CI 断言在 `vscode/ci/verify/`）。根目录的三个 install 脚本是兼容 shim（旧 URL 不 404）。共享区域检测在根 `lib/detect.sh`（另一方案 dsh-desktop 复用）。
>
> 仓库另一条路径：DSH Desktop 方案，见 `dsh-desktop/README.md` 与站点 `dsh-desktop.html`。

## 目标

让零 IT 背景用户一条命令得到 VS Code + Claude Code + DeepSeek V4 Flash 0731 的工作环境。门槛在"设置环境"，不在"用 AI"。搭好后用户能直接问 AI。

## 核心技术机制

只装 **VS Code + "Claude Code for VS Code" 扩展**（marketplace ID `anthropic.claude-code`）。扩展自带聊天面板用的 CLI（官方文档原文："The extension bundles its own copy of the CLI for the chat panel"），**不装 Node.js、不装独立 claude CLI**。模型后端通过 `settings.local.json` 的 `env` 块接任意 Anthropic 兼容端点。

### 面板位置：不自动打开插件，靠 UI 状态指定（2026-08-28）

早期版本在安装后延时调 `vscode://anthropic.claude-code/open` "弹出聊天面板"。该 URI 在扩展内解析为 `primaryEditor.open`（v2.1.247 extension.js 实证），固定把 Claude Code 开在中间编辑区新标签，且无视 `claudeCode.preferredLocation`（官方文档称其为 "open a new Claude Code tab"，上游 feature request anthropics/claude-code#89511 正在要求该路由尊重 preferredLocation）。这违背"Claude 在右侧 sidebar"的目标，已去掉。

现在位置完全由 UI 状态指定：`vscode_seed_state` 把 golden 状态（`wip/golden-state.vscdb`）里的可移植键种进 `state.vscdb`：`workbench.auxiliarybar.pinnedPanels` 加 `workbench.view.extension.claude-sidebar-secondary.state.hidden` 把 Claude 视图停靠在右侧次侧边栏，`workbench.auxiliaryBar.empty=false` 标记右侧栏非空，`Anthropic.claude-code` 标志（仅新装时 INSERT OR IGNORE）关掉首启 walkthrough（它也会在中间区自动开）。配合 `claudeCode.preferredLocation: sidebar` 设置，首次启动右侧栏直接展开、里面就是 Claude Code。

明确不写 `workbench.secondarySideBar.defaultVisibility`：该设置默认值 `visibleInWorkspace`，打开文件夹时右侧栏可见。曾写入 `hidden` 反而把右侧栏压没（这是"首启右侧栏不展开"的根因，已去掉）。右侧栏可见性机制实证自 workbench.desktop.main.js 的 `AUXILIARYBAR_HIDDEN.defaultValue`：仅在设置显式 `hidden`、或默认设置加右侧栏为空时隐藏。

配置写进**工作区**（`~/ai-workspace/.claude/settings.local.json`，项目域、自包含），不是全局 `~/.claude/`。这样工作区换机器复制即用；`settings.local.json` 含 API key，工作区 `.gitignore` 忽略它。crawl4ai 注册进工作区 `.mcp.json`（无密钥，可提交）。

```json
// ~/ai-workspace/.claude/settings.local.json
{
  "env": {
    "ANTHROPIC_BASE_URL": "<端点>",
    "ANTHROPIC_AUTH_TOKEN": "<api key>",
    "ANTHROPIC_MODEL": "<模型名>",
    "ANTHROPIC_DEFAULT_SONNET_MODEL": "<模型名>",
    "ANTHROPIC_DEFAULT_OPUS_MODEL": "<模型名>",
    "API_TIMEOUT_MS": "3000000"
  },
  "permissions": {
    "allow": ["Bash(*)","Read","Write","Edit","Glob","Grep","Task","mcp__crawl4ai__search","mcp__crawl4ai__read_url"],
    "deny": ["WebSearch","WebFetch"],
    "ask": []
  },
  "enabledMcpjsonServers": ["crawl4ai"],
  "hasCompletedOnboarding": true
}
```

三条供应商路径，base URL 与 model 名均抓官方文档全文核实：

| 供应商 | 区域 | base_url | model | 鉴权 |
|---|---|---|---|---|
| 阿里云百炼（国内） | 中国默认 | `https://dashscope.aliyuncs.com/apps/anthropic` | `deepseek-v4-flash-0731` | Bearer |
| 阿里云 Model Studio（国际） | 国外默认 | `https://dashscope-intl.aliyuncs.com/apps/anthropic` | `deepseek-v4-flash` | Bearer |
| DeepSeek 官方 | 备选 | `https://api.deepseek.com/anthropic` | `deepseek-v4-flash`（自动 0731） | Bearer |
| OpenRouter | 备选（接法待确认） | `https://openrouter.ai/api/v1` | `deepseek/deepseek-v4-flash` | Bearer |

百炼/Model Studio（国内与国际）路径额外加 `ANTHROPIC_CUSTOM_HEADERS: X-DashScope-DataInspection: {"input":"disable","output":"disable"}` 关闭服务端数据审查。

### 关键坑（百炼，来自官方文档）

- base URL **不可以 `/v1/` 结尾**，否则 Claude Code 模型发现会拼成 `/v1/v1/models` 报 404。
- 百炼端点不提供 `/v1/models`，模型发现本身 404 是正常现象；靠 `ANTHROPIC_MODEL` 指定模型跳过自动发现。

## 区域路由

脚本检测区域（locale/时区/geo IP 探测），默认中国→百炼（国内），其余→百炼国际（Model Studio 国际端点，alibabacloud.com 文档核实托管 deepseek-v4-flash）。用户可用 `--provider=bailian|bailian-intl|deepseek|openrouter` 覆盖。

国外用户为何也默认走百炼国际：DeepSeek 官方虽便宜直连，但百炼国际是同一套 Anthropic 兼容端点、同一模型，且统一在阿里平台（用户偏好）。DeepSeek 官方降为备选。

## crawl4ai MCP

随环境下发（免费无 key）：在维护者本人使用的调用方式下，注册进工作区 `.mcp.json` 的命令是 `uvx --from crawl4ai-search-mcp==0.1.1 crawl4ai-search`。该包是 `gigix/crawl4ai-mcp-server` 的打包版（PyPI 发布，ddgs 迁移已修好，版本钉 0.1.1）。uvx 随 uv 自带（安装器本就要装 uv），首次调用时 uv 自动拉镜像环境，本地不 clone、不建 venv。serper/oxylabs 带私钥，不下发，站上给文字指导让用户用自己的 key 加。

## Windows

PowerShell `irm | iex` 一行脚本为主推（winget 装 VS Code + Git + uv）。WSL 路径为备选（复用 install.sh）。Windows 上跑的是 Windows 11 ARM（CI 服务器是 Apple Silicon Mac）。设计同 Linux：只装扩展，配置进工作区，crawl4ai 同样注册 uvx 条目（uv 自带 uvx）。

## CI

CI 在一台 Apple Silicon Mac 上用 VMware Fusion Pro（个人免费，原生快照 + `vmrun` CLI）。Linux 模板 VM：Ubuntu 26.04 ARM（手动装 + openssh + open-vm-tools + CI 公钥 + 免密 sudo）。每次 `revertToSnapshot clean-base` → 主机 rsync 仓库进 VM → 从 clone 跑 `install.sh`（用本地 lib，测最新提交，不依赖 Pages CDN 缓存）→ 自动化 verify。Windows 11 ARM 模板 VM 暂缓（Fusion 在 macOS 26.1 上跑 Windows VM 有坑）。主机地址、VM 路径、测试 API key 等本地信息放 `.env`（gitignored，模板见 `.env.example`）。

注意：CI 的 clean-base 模板里给 `yuan` 用户开了免密 sudo（真用户是交互式自己输密码；CI 无人值守得免密）。clean-base 不含 bootstrap 仓库（CI 每次 rsync 进去），只含 OS + openssh + open-vm-tools + CI 公钥 + 免密 sudo。

## 暂不推

DSH（DeepSeek Harness）：成熟度与使用体验还不够，暂不纳入 bootstrap。

## 发布架构

- GitHub Pages 经 `ci/deploy-pages` workflow 部署（`Settings → Pages → Source: GitHub Actions` + `.nojekyll`）。落地页 root `index.html`，站点 URL `https://bandung-circuits.github.io/bootstrap/`。每次 push 到 main，workflow 在内存里把部署提交的 SHA8 + 北京时间注入到 install.ps1 头注释和 index.html 页脚（不 commit），再 upload + deploy——线上文件自己声明对应提交，Pages CDN 若 serve 旧版一眼能看出。
- 安装脚本也经 Pages 域名下发（`/bootstrap/install.sh`、`/bootstrap/lib/*.sh`、`/bootstrap/install.ps1`）。选 Pages 而非 `raw.githubusercontent.com`：后者国内常被墙，`github.io` 国内可达，对默认国内路径（百炼）的可达性更关键。
- `install.sh` 被管道执行时若本地无 `lib/`，就从 Pages 域名拉 `lib/*.sh` 进临时目录 source。
