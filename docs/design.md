# 设计决策记录

## 目标

让零 IT 背景用户一条命令得到 VS Code + Claude Code + DeepSeek V4 Flash 0731 的工作环境。门槛在"设置环境"，不在"用 AI"。搭好后用户能直接问 AI。

## 核心技术机制

Claude Code 通过 `~/.claude/settings.json` 的 `env` 块接任意 Anthropic 兼容后端：

```json
{
  "env": {
    "ANTHROPIC_BASE_URL": "<端点>",
    "ANTHROPIC_AUTH_TOKEN": "<api key>",
    "ANTHROPIC_MODEL": "<模型名>"
  },
  "hasCompletedOnboarding": true
}
```

三条供应商路径，base URL 与 model 名均已/将核实（不信任搜索摘要，抓官方文档全文）：

| 供应商 | 区域 | base_url | model | 鉴权 |
|---|---|---|---|---|
| 阿里云百炼 | 国内默认 | `https://dashscope.aliyuncs.com/apps/anthropic` | `deepseek-v4-flash-0731` | Bearer |
| DeepSeek 官方 | 国外主推 | `https://api.deepseek.com/anthropic` | `deepseek-v4-flash`（自动 0731） | Bearer |
| OpenRouter | 备选 | （实现期核实） | `deepseek/deepseek-v4-flash` | Bearer |

### 关键坑（百炼，来自官方文档）

- base URL **不可以 `/v1/` 结尾**，否则 Claude Code 模型发现会拼成 `/v1/v1/models` 报 404。
- 百炼端点不提供 `/v1/models`，模型发现本身 404 是正常现象；靠 `ANTHROPIC_MODEL` 指定模型跳过自动发现。

## 区域路由

脚本检测区域（locale/时区/geo IP 探测），默认中国→百炼，其余→DeepSeek 官方。用户可用 `--provider=bailian|deepseek|openrouter` 覆盖，`--api-key=xxx` 传 key。

国外用户为何不走百炼：国内百炼要中国实体/支付宝；DashScope 国际门户英文且 Visa/Mastercard，但主要托管 Qwen，DeepSeek 在国际门户是否上架需核实。DeepSeek 官方端点原生 Anthropic 兼容、直连无中间商，是国外最干净路径。

## crawl4ai MCP

随环境下发（免费无 key）：clone `gigix/crawl4ai-mcp-server`，建 venv，写进 `~/.claude/.mcp.json`。serper/oxylabs 带私钥，不下发，站上给文字指导让用户用自己的 key 加。

## Windows

PowerShell `irm | iex` 一行脚本为主推（winget 装 VS Code + Node）。WSL 路径为备选（复用 install.sh）。Windows 上跑的是 Windows 11 ARM（CI 服务器是 Apple Silicon Mac）。

## CI

CI 在一台 Apple Silicon Mac 上用 VMware Fusion Pro（个人免费，原生快照 + `vmrun` CLI）。两台模板 VM：Ubuntu 24.04 ARM、Windows 11 ARM。每次 `revertToSnapshot clean-base` → 跑安装脚本 → 自动化 verify。主机地址、VM 路径、测试 API key 等本地信息放 `.env`（gitignored，模板见 `.env.example`）。Docker 不行（无 GUI、跑不了 VS Code 扩展登录流、无 Windows）。UTM 无原生快照，CI 恢复别扭。

## 暂不推

DSH（DeepSeek Harness）：成熟度与使用体验还不够，暂不纳入 bootstrap。

## 发布架构

- GitHub Pages 从仓库 root 发布（`Settings → Pages → Source: main /root` + `.nojekyll`）。落地页 root `index.html`，站点 URL `https://bandung-circuits.github.io/bootstrap/`。
- 安装脚本也经 Pages 域名下发（`/bootstrap/install.sh`、`/bootstrap/lib/*.sh`、`/bootstrap/install.ps1`）。选 Pages 而非 `raw.githubusercontent.com`：后者国内常被墙，`github.io` 国内可达，对默认国内路径（百炼）的可达性更关键。
- `install.sh` 被管道执行时若本地无 `lib/`，就从 Pages 域名拉 `lib/*.sh` 进临时目录 source。
