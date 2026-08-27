# 修复 vscode.sh：关闭内置 Copilot Chat 面板

## 背景

右侧 sidebar 里 "Build with Agent" 那个 AI 聊天窗是 VS Code 内置的 GitHub Copilot Chat（已并入核心发行版，物理删不掉，`code --uninstall-extension GitHub.copilot-chat` 无效）。

官方 FAQ（<https://code.visualstudio.com/docs/agents/agent-troubleshooting/faq>，条目 "How can I remove Copilot from VS Code?"）给出的正解是设置项 `chat.disableAIFeatures`：它会 disable and hide 内置 AI 功能（chat、inline suggestions）并禁用 Copilot 扩展，官方承诺升级后该选择会被尊重。

## 现状

`lib/vscode.sh` 的 `vscode_write_user_settings()`（约 85-116 行）里 python3 脚本已写入：

- `chat.commandCenter.enabled = False` —— 仅隐藏标题栏 Chat 菜单
- `github.copilot.enable = {"*": False}` —— 仅关闭补全

这两项都**不会**移除右侧 sidebar 的 Chat 面板本身。

## 需要追加的两行

在 `vscode_write_user_settings()` 的 python3 脚本里、`data["github.copilot.enable"] = {"*": False}` 这一行之后追加：

```python
data["chat.disableAIFeatures"] = True
data["workbench.secondarySideBar.defaultVisibility"] = "hidden"
```

说明：

- `chat.disableAIFeatures = True` —— 官方推荐方式，一次性 disable + hide 内置 AI 功能并禁用 Copilot 扩展。
- `workbench.secondarySideBar.defaultVisibility = "hidden"` —— 阻止 Chat 视图首次启动自动弹出（官方 FAQ 条目 "How do I prevent the Chat view from opening automatically?"）。

## 不要做的

- 不要用 `code --uninstall-extension GitHub.copilot-chat` / `GitHub.copilot`：内置扩展删不掉，命令无效。
- 不要只靠 `chat.commandCenter.enabled` / `github.copilot.enable`：它们压不掉 sidebar 那个面板。

## 验证

改完后首启 VS Code：右侧 sidebar 不应再出现 "Build with Agent" 面板，标题栏也无 Chat 菜单，无 Copilot 补全弹窗。
