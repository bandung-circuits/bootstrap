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

- settings: writes the golden 6 + extras (`disableLoginPrompt`, `hideOnboarding`,
  `chat.commandCenter.enabled=false`, `chat.disableAIFeatures=true`,
  `github.copilot.enable={"*":false}`) and switches `preferredLocation` to
  `sidebar` (right by default; #16484 sidebar-blank bug is Closed in v2.1.247,
  so sidebar should now work without the manual drag). Deliberately does NOT
  set `workbench.secondarySideBar.defaultVisibility`: its default
  `visibleInWorkspace` + a folder open shows the right sidebar on first launch
  (earlier scheme C set it to `hidden`, which collapsed the right sidebar —
  that's the bug this fixes).
- state.vscdb: seeds `welcomeOnboarding.state` + `newDefaultThemeNotification`
  (the 2 booleans settings can't suppress) via the crawl4ai venv python
  (`lib/vscode.sh:vscode_seed_state`, `install.ps1:Seed-VSCodeState`). Since
  2026-08-28 it also seeds the Claude-in-the-right keys from this golden
  capture:
  - `workbench.auxiliarybar.pinnedPanels` (portable, verified) — Claude Code
    pinned in the secondary (right) sidebar;
  - `workbench.view.extension.claude-sidebar-secondary.state.hidden` with
    `isHidden:false` — the right-sidebar Claude view visible;
  - `workbench.auxiliaryBar.empty=false` — the right sidebar is NOT empty, so
    VS Code's layout state (workbench.desktop.main.js:
    `AUXILIARYBAR_HIDDEN.defaultValue`) does not auto-collapse it; with the
    default `visibleInWorkspace` the bar OPENS ON FIRST LAUNCH with Claude in it;
  - `Anthropic.claude-code` flags (INSERT OR IGNORE, fresh installs only):
    `lastClaudeLocationMigrated:true` stops the first-activation walkthrough
    (it would auto-open in the CENTER editor tab), `tengu_vscode_onboarding:false`
    keeps the onboarding checklist off.
- NO auto-open of the plugin: the installer used to fire
  `vscode://anthropic.claude-code/open` (xdg-open/open / Start-Process) a few
  seconds after first launch to "pop the chat panel". That was wrong — the
  URI handler resolves to the extension's `primaryEditor.open` command
  (verified in anthropic.claude-code v2.1.247 extension.js), which opens a NEW
  TAB in the CENTER editor area and IGNORES `claudeCode.preferredLocation`
  (official docs call it "open a new Claude Code tab"; upstream feature request
  anthropics/claude-code#89511 asks to make the route honor preferredLocation).
  So the open location now comes purely from the seeded UI state + the
  `preferredLocation:sidebar` setting: first launch shows the right sidebar
  with Claude Code already in it.

## To re-capture

```
scp yuan@172.16.97.129:.config/Code/User/globalStorage/state.vscdb wip/golden-state.vscdb
sqlite3 wip/golden-state.vscdb "SELECT key,value FROM ItemTable WHERE key LIKE '%claude%' OR key LIKE '%onboard%' OR key LIKE '%welcome%' OR key LIKE '%chat%' OR key LIKE '%auxiliary%' OR key LIKE '%theme%';"
```
