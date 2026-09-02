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

本仓库结构（两个独立方案，各占一个子树，按方案各自演进）：

```
install.sh / install.ps1 / install-wsl.sh   旧入口兼容 shim -> vscode/
lib/detect.sh                               共享：OS/arch/region 检测（两方案共用）
vscode/                方案 A：VS Code + Claude Code
  install.sh / install.ps1 / install-wsl.sh
  lib/  providers/  templates/  ci/verify/  wip/
dsh-desktop/           方案 B：给 DSH Desktop 学员准备工作区（一条命令）
  prep.sh / prep.ps1   templates/  README.md
index.html / dsh-desktop.html / providers-guide.html   GitHub Pages 站点（root 发布）
ci/         CI：VMware Fusion Pro 上的 Linux ARM + Windows 11 ARM 模板机，快照恢复后按方案跑安装脚本并自动验证（见 `ci/run-test.sh`）
.env        本地私有配置（主机地址/VM 路径/API key），已 gitignore；`.env.example` 是模板
docs/       设计决策（design-vscode.md 为方案 A 记录）
```

- DSH Desktop 方案：学员先自己装 DSH Desktop（https://dshdesktop.com/en/，仅 macOS/Windows），
  再运行一条命令（`curl .../dsh-desktop/prep.sh | bash` 或 `irm .../prep.ps1 | iex`），得到
  `~/ai-workspace` + 工作区规则 + 经官方 mcp-client 启用的 crawl4ai。模型 key 在 app 内填。
  详见 `dsh-desktop/README.md`。
- 设计原则：每个方案的种子配置都是 `templates/` 里的真实静态文件，脚本只拷贝 + 占位符替换。

详见 `docs/design.md` 与 `ci/vm-setup.md`。

## 测试

CI 在一台 Apple Silicon Mac 上的 VMware Fusion Pro 里跑：一台 Linux ARM、一台 Windows 11 ARM，每次恢复干净快照后跑安装脚本，自动化验证环境是否配好。见 `ci/run-test.sh`。主机地址等本地信息放在 `.env`（不入仓库，模板见 `.env.example`）。

## 范围（暂定）

- 只推 VS Code + Claude Code。暂不推 DSH（DeepSeek Harness），成熟度与体验还不够。
- 默认模型固定 DeepSeek V4 Flash 0731（又便宜又强）。
