# AgentGarden for VS Code

Turns VS Code into a **fourth approval surface** for AgentGarden — next to your
phone, Garmin, and the webapp. It's a thin client for the same HTTP server, so
it works no matter which agent you run (Claude Code, Copilot CLI, Codex, an
Aider/Ollama setup…). It does **not** hook into Copilot's internals — it mirrors
the AgentGarden server.

## What it does

- **Status bar** — `🤖 AgentGarden: N` running agents, or `⚠ N pending` when
  something needs a decision. Click → open the dashboard.
- **Sidebar** (AgentGarden activity-bar icon) — live list of agents + pending
  approvals. Click an approval to Approve / Deny.
- **Approval notifications** — when any agent asks for permission (from any
  surface), a toast pops with **Approve / Deny** buttons.
- **New Project** command — spawns a Claude session on the server (`+ New`).
- **Registers this workspace** as an agent in the fleet (so opening a folder in
  VS Code shows it), toggle with `agentgarden.registerWorkspace`.

## Settings

| Setting | Default | |
|---|---|---|
| `agentgarden.serverUrl` | `http://127.0.0.1:4141` | The macOS app or `garden.exe` |
| `agentgarden.token` | *(empty)* | Bearer token; empty ⇒ read `~/.agent-garden-token` |
| `agentgarden.registerWorkspace` | `true` | Show this workspace as an agent |

## Build & install

```bash
cd vscode-extension
npm install
npm run compile
# then either:
#  • press F5 in VS Code to launch an Extension Development Host, or
#  • package a .vsix and install it:
npx @vscode/vsce package
code --install-extension agentgarden-0.1.0.vsix
```

Requires the AgentGarden server running (macOS app, or `garden.exe` on
Windows/Linux) reachable at `serverUrl`.

## Commands

- **AgentGarden: New Project**
- **AgentGarden: Open Dashboard**
- **AgentGarden: Approve / Deny**
- **AgentGarden: Refresh**

## Note

Structured approval gating still requires the agent to *pause* for permission —
that's Claude Code's hook. For agents without a pre-tool hook (Copilot CLI,
Codex, Aider…), use this extension to watch the fleet and approve anything that
does reach the server; drive the rest through the live terminal.
