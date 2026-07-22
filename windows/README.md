# AgentGarden — Windows / Linux server

A single-binary, dependency-free port of the macOS GardenServer. Same HTTP
endpoints, same agent store, same model-spend scanner, and it serves the **same
dashboard** — so the existing webapp and the Garmin app work unchanged.

## What's here

| File | What |
|------|------|
| `main.go` | The whole server (endpoints, store, usage scan, `/new-project` spawn) |
| `dashboard.html` | The webapp UI, embedded into the binary at build time |
| `hooks/agent-garden-hook.ps1` | PowerShell hook so Claude Code on Windows reports to the server |
| `go.mod` | Module file (Go 1.25, stdlib only) |

## Build

```powershell
# from this folder, with Go installed:
go build -o garden.exe .
```

Cross-compile from any OS:

```bash
GOOS=windows GOARCH=amd64 go build -o garden.exe .   # Windows
GOOS=linux   GOARCH=amd64 go build -o garden      .   # Linux
```

Or grab a prebuilt `garden.exe` from the GitHub **Releases**.

## Run

```powershell
.\garden.exe
```

On first run it creates `%USERPROFILE%\.agent-garden-token` and prints the
dashboard URL with the token. Open it in a browser or on your phone (over
Tailscale). Set `GARDEN_PORT` to use a port other than 4141, and
`GARDEN_BUDGET` (or `%USERPROFILE%\.agent-garden-budget`) for the daily model
budget (default `$6`).

## Wire up Claude Code

Copy `hooks\agent-garden-hook.ps1` somewhere stable (e.g.
`%USERPROFILE%\agentgarden\`) and register it in
`%USERPROFILE%\.claude\settings.json` under `SessionStart`, `PreToolUse`, and
`Stop` — see the header comment in the script for the exact JSON. Once wired,
running `claude` in any folder makes that folder show up as an agent, and risky
tools (Bash / Write / Edit …) pause for approval from your phone or Garmin.

## Phone + Garmin over Tailscale

Same as macOS: put the machine on your tailnet and `tailscale serve --bg
http://127.0.0.1:4141` so the phone/watch reach it over HTTPS. Point the Garmin
app's `Config.mc` `GARDEN_URL` + token at it.

## Notes / limits (v1)

- **Terminal mirroring** (the live in-webapp terminal) needs a PTY bridge; on
  Windows `/new-project` opens a real console running `claude` instead, and the
  in-app terminal panel stays empty. The rest (approvals, fleet, usage, new
  project) works fully.
- The hook is a starting point — adjust the `permissionDecision` output shape to
  your Claude Code version if needed.
- The server binds `0.0.0.0:<port>` and is protected by the bearer token; keep
  the token private and prefer exposing it only through Tailscale.
