# Golden VS Code state — captured from the Linux VM (the user's desired state)

Captured 2026-08-27 from `yuan@172.16.97.129` (the Linux VM the user set up by
hand). This documents what makes the desired first-run UX. Two parts:

## 1. settings.json (6 keys — see golden-vscode-settings.json)

Just 6 settings. NOTE: `claudeCode.preferredLocation` is `"panel"` here (center
editor tab) — the "Claude on the right" comes from the UI state (part 2), NOT
from this setting. The user dragged Claude to the secondary sidebar by hand.

## 2. state.vscdb (UI state — see golden-state.vscdb, the binary copy)

SQLite at `~/.config/Code/User/globalStorage/state.vscdb`, table `ItemTable(key TEXT UNIQUE ON CONFLICT REPLACE, value BLOB)`. The portable keys (no machine paths — verified):

| key | value | what it does |
|---|---|---|
| `welcomeOnboarding.state` | `true` | first-run onboarding done (suppresses the "choose interface style" walkthrough) |
| `workbench.newDefaultThemeNotification` | `true` | theme-change notification dismissed |
| `workbench.auxiliarybar.pinnedPanels` | `[{"id":"workbench.panel.chat","pinned":true,"visible":false,"order":1},{"id":"workbench.view.extension.claude-sidebar-secondary","pinned":true,"visible":false,"order":101}]` | Claude Code docked in the RIGHT (secondary/auxiliary) sidebar |
| `workbench.view.extension.claude-sidebar-secondary.state.hidden` | `[{"id":"claudeVSCodeSidebarSecondary","isHidden":false}]` | the right-sidebar Claude view is visible |
| `chat.setupContext` | `{"entitlement":1,"installed":true,"disabled":true,"untrusted":false,"disabledInWorkspace":false}` | Copilot Chat installed-but-DISABLED |
| `colorThemeData` | `{"id":"vs-dark vscode-theme-defaults-themes-2026-dark-json","label":"Dark 2026",...}` | theme = Dark 2026 (picker won't show) |
| `Anthropic.claude-code` | `{"settingsMigrated20251024":true,"lastClaudeLocationMigrated":true,"experimentGates":{...,"tengu_vscode_onboarding":false,...}}` | Claude Code extension state (onboarding off) |

Keys WITH machine paths (do NOT copy wholesale — only the portable keys above):
`workbench.activity.placeholderViewlets`, `workbench.auxiliarybar.placeholderPanels`.

## How the installer reproduces this (scheme C)

- settings: writes the 6 + extras (`disableLoginPrompt`, `hideOnboarding`,
  `chat.commandCenter.enabled=false`, `github.copilot.enable={"*":false}`) and
  switches `preferredLocation` to `sidebar` (right by default; #16484
  sidebar-blank bug is Closed in v2.1.247, so sidebar should now work without
  the manual drag).
- state.vscdb: seeds `welcomeOnboarding.state` + `newDefaultThemeNotification`
  (the 2 booleans settings can't suppress) via the crawl4ai venv python
  (`lib/vscode.sh:vscode_seed_state`, `install.ps1:Seed-VSCodeState`).
- The Claude-on-the-right + Copilot-disabled keys above are NOT yet seeded
  (would need the fragile `auxiliarybar.pinnedPanels` etc.) — scheme C relies on
  `preferredLocation:sidebar` (setting) for the right position instead. If that
  turns out insufficient on a real launch, seed the keys above.

## To re-capture

```
scp yuan@172.16.97.129:.config/Code/User/globalStorage/state.vscdb wip/golden-state.vscdb
sqlite3 wip/golden-state.vscdb "SELECT key,value FROM ItemTable WHERE key LIKE '%claude%' OR key LIKE '%onboard%' OR key LIKE '%welcome%' OR key LIKE '%chat%' OR key LIKE '%auxiliary%' OR key LIKE '%theme%';"
```
