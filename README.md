# bootstrap

帮几乎零 IT 背景的用户一条命令搭好智能体工作环境：Visual Studio Code + Claude Code，背后接 DeepSeek V4 Flash 0731。

面向全球南方培训场景。最难的是设置工作环境这一步；搭好后，后续问题用户可以直接问 AI。

## 最终用户体验

- **Linux / macOS**：一条 curl 命令。
  ```bash
  curl -fsSL https://bandung-circuits.github.io/bootstrap/install.sh | bash
  ```
- **Windows**：PowerShell 一行（主推）。
  ```powershell
  irm https://bandung-circuits.github.io/bootstrap/install.ps1 | iex
  ```
  或 WSL 路径（备选）：
  ```bash
  curl -fsSL https://bandung-circuits.github.io/bootstrap/install-wsl.sh | bash
  ```

脚本装好 VS Code、Claude Code 扩展与 CLI、crawl4ai MCP，并按用户所在区域把后端模型接到 DeepSeek V4 Flash 0731：
- 国内默认走阿里云百炼（Anthropic 兼容端点，model `deepseek-v4-flash-0731`）。
- 国外默认走 DeepSeek 官方（`https://api.deepseek.com/anthropic`，model `deepseek-v4-flash`，自动指向 0731）。
- 备选 OpenRouter。

API key 由用户自助申请，站上给文字指导。

## 仓库与站点

- 仓库：`git@github.com:bandung-circuits/bootstrap.git`
- 站点（GitHub Pages）：`https://bandung-circuits.github.io/bootstrap/`

## 开发

本仓库结构：

```
install.sh / install.ps1 / install-wsl.sh   入口
lib/        共享逻辑（detect / provider / vscode / claude-code / crawl4ai / workspace）
providers/  各供应商 settings.json 模板与订阅指导
index.html / providers-guide.html   GitHub Pages 站点（英文为主，从仓库 root 发布）
ci/         CI：VMware Fusion Pro 上的 Linux ARM + Windows 11 ARM 模板机，快照恢复后跑安装脚本并自动验证（见 `ci/run-test.sh`）
.env        本地私有配置（主机地址/VM 路径/API key），已 gitignore；`.env.example` 是模板
docs/       设计决策
```

详见 `docs/design.md` 与 `ci/vm-setup.md`。

## 测试

CI 在一台 Apple Silicon Mac 上的 VMware Fusion Pro 里跑：一台 Linux ARM、一台 Windows 11 ARM，每次恢复干净快照后跑安装脚本，自动化验证环境是否配好。见 `ci/run-test.sh`。主机地址等本地信息放在 `.env`（不入仓库，模板见 `.env.example`）。

## 范围（暂定）

- 只推 VS Code + Claude Code。暂不推 DSH（DeepSeek Harness），成熟度与体验还不够。
- 默认模型固定 DeepSeek V4 Flash 0731（又便宜又强）。
