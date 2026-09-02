# bootstrap

帮几乎零 IT 背景的用户一条命令搭好智能体工作环境。两种路径共用同一个工作区 `~/ai-workspace`：

- **推荐（首选）：DeepSeek Harness（dsh）** —— 免费开源的 agent harness，浏览器打开即用，无需装任何软件。
- **后备：Visual Studio Code + Claude Code 扩展** —— 给已装 VS Code、想留在 IDE 里的用户。

后端都接 DeepSeek V4 Flash 0731（便宜又强）。面向全球南方培训场景。最难的是设置环境这一步；搭好后，后续问题用户可以直接问 AI。

## 最终用户体验

**首选：DeepSeek Harness（dsh）**

- **Linux / macOS**（WSL 同命令）：
  ```bash
  curl -fsSL https://bandung-circuits.github.io/bootstrap/dsh/install.sh | bash
  ```
- **Windows**：
  ```powershell
  irm https://bandung-circuits.github.io/bootstrap/dsh/install.ps1 | iex
  ```

装好后运行 `~/ai-workspace/start-dsh.sh`（或双击 `start-dsh.cmd`），浏览器打开 `http://127.0.0.1:3080`。安装器自动装好 Node（钉版 LTS v24）与 `dsh` CLI（钉版），按区域把后端接到 DeepSeek V4 Flash 0731，启用 crawl4ai MCP，并把 API key 写进 `~/ai-workspace/.dsh/secrets.env`（或 UI 里粘贴）。dsh 是 dev preview，版本已钉死且脚本幂等，重跑即恢复。

**后备：VS Code + Claude Code**

- **Linux / macOS**：
  ```bash
  curl -fsSL https://bandung-circuits.github.io/bootstrap/vscode/install.sh | bash
  ```
- **Windows**：
  ```powershell
  irm https://bandung-circuits.github.io/bootstrap/vscode/install.ps1 | iex
  ```

旧入口 `https://bandung-circuits.github.io/bootstrap/install.sh` 等仍可用（兼容 shim 转发到 vscode 方案）。

API key 由用户自助申请，站上给文字指导：`bootstrap/providers-guide.html`。

## 仓库结构

```
bootstrap/
├── index.html / providers-guide.html   GitHub Pages 站点：dsh 首选入口，vscode 后备
├── lib/detect.sh                        共享：OS/arch/region 检测（两方案共用）
├── install.sh / ps1 / install-wsl.sh    旧入口兼容 shim -> vscode/
├── vscode/                              后备方案：VS Code + Claude Code
│   ├── install.sh / install.ps1 / install-wsl.sh
│   ├── lib/  providers/  templates/workspace/  ci/verify/  wip/
├── dsh/                                 首选方案：DeepSeek Harness
│   ├── install.sh / install.ps1
│   ├── lib/  providers/  templates/  ci/verify/
├── ci/run-test.sh                       共享 CI：VMware 上按方案逐个整机验证
├── docs/design-vscode.md  docs/design-dsh.md   设计决策记录
└── .env.example                         CI 本地配置模板（gitignored）
```

设计要点：每个方案的种子配置都是 `templates/` 下的真实静态文件，安装器只做拷贝 + 占位符替换，脚本内不嵌配置文本（改配置就是改模板，一行 diff）。dsh 的 `$DSH_HOME` 在工作区内（`~/ai-workspace/.dsh`），整个环境一个文件夹、拷走即用。

## 开发与测试

CI 在一台 Apple Silicon Mac 上的 VMware Fusion Pro 里跑：Linux（+Windows）模板机，每次恢复干净快照后跑安装脚本并自动化验证。`ci/run-test.sh` 会为每个方案独立还原快照再安装（两方案共用 `~/ai-workspace`，不能同机并发测，必须快照间隔开）。主机地址等本地信息放 `.env`（不入仓库，模板见 `.env.example`）。dsh Windows 脚本已备，Windows VM 恢复后纳入 CI。

详见 `docs/design-dsh.md`、`docs/design-vscode.md` 与 `ci/vm-setup.md`。

## 范围

- 默认模型固定 DeepSeek V4 Flash 0731。
- dsh 为 dev preview：钉版本、脚本幂等、`--dump-config` 冒烟；schema 变更以 `dsh/templates/` 与 `dsh/lib/providers.sh` 为准更新。
- 暂不纳入其它 harness / CLI 模式（headless、SDK、TUI 留作进阶）。