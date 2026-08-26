# 设计决策记录

## 目标

让零 IT 背景用户一条命令得到 VS Code + Claude Code + DeepSeek V4 Flash 0731 的工作环境。门槛在"设置环境"，不在"用 AI"。搭好后用户能直接问 AI。

## 核心技术机制

只装 **VS Code + "Claude Code for VS Code" 扩展**（marketplace ID `anthropic.claude-code`）。扩展自带聊天面板用的 CLI（官方文档原文："The extension bundles its own copy of the CLI for the chat panel"），**不装 Node.js、不装独立 claude CLI**。模型后端通过 `settings.local.json` 的 `env` 块接任意 Anthropic 兼容端点。

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

随环境下发（免费无 key）：clone `gigix/crawl4ai-mcp-server` 的 `fix/migrate-to-ddgs-library` 分支（main 用已废弃的 duckduckgo_search，是坏的），用 **uv** 钉 Python 3.10 建 venv（依赖 lxml/pillow/pydantic-core 在 3.10 有预编译 wheel；系统 Python 太新如 3.14 会逼源码编译，pydantic-core 还要 Rust，死路），注册进工作区 `.mcp.json`。serper/oxylabs 带私钥，不下发，站上给文字指导让用户用自己的 key 加。

## Windows

PowerShell `irm | iex` 一行脚本为主推（winget 装 VS Code + Git + uv）。WSL 路径为备选（复用 install.sh）。Windows 上跑的是 Windows 11 ARM（CI 服务器是 Apple Silicon Mac）。设计同 Linux：只装扩展，配置进工作区，crawl4ai 用 uv。

## CI

CI 在一台 Apple Silicon Mac 上用 VMware Fusion Pro（个人免费，原生快照 + `vmrun` CLI）。Linux 模板 VM：Ubuntu 26.04 ARM（手动装 + openssh + open-vm-tools + CI 公钥 + 免密 sudo）。每次 `revertToSnapshot clean-base` → 主机 rsync 仓库进 VM → 从 clone 跑 `install.sh`（用本地 lib，测最新提交，不依赖 Pages CDN 缓存）→ 自动化 verify。Windows 11 ARM 模板 VM 暂缓（Fusion 在 macOS 26.1 上跑 Windows VM 有坑）。主机地址、VM 路径、测试 API key 等本地信息放 `.env`（gitignored，模板见 `.env.example`）。

注意：CI 的 clean-base 模板里给 `yuan` 用户开了免密 sudo（真用户是交互式自己输密码；CI 无人值守得免密）。clean-base 不含 bootstrap 仓库（CI 每次 rsync 进去），只含 OS + openssh + open-vm-tools + CI 公钥 + 免密 sudo。

## 暂不推

DSH（DeepSeek Harness）：成熟度与使用体验还不够，暂不纳入 bootstrap。

## 发布架构

- GitHub Pages 从仓库 root 发布（`Settings → Pages → Source: main /root` + `.nojekyll`）。落地页 root `index.html`，站点 URL `https://bandung-circuits.github.io/bootstrap/`。
- 安装脚本也经 Pages 域名下发（`/bootstrap/install.sh`、`/bootstrap/lib/*.sh`、`/bootstrap/install.ps1`）。选 Pages 而非 `raw.githubusercontent.com`：后者国内常被墙，`github.io` 国内可达，对默认国内路径（百炼）的可达性更关键。
- `install.sh` 被管道执行时若本地无 `lib/`，就从 Pages 域名拉 `lib/*.sh` 进临时目录 source。
