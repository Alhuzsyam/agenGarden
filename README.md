# 🌱 AgentGarden

Monitor and remote-control your **Claude Code** agents from your phone, your
laptop, and your **Garmin watch** — over your own [Tailscale](https://tailscale.com)
network. AgentGarden is a macOS menu-bar / Dynamic-Island app that shows what
every agent is doing as a little arcade garden, and lets you **approve tool
calls, steer prompts, and watch the live terminal** from anywhere.

> **Platform:** macOS (Apple Silicon) today.
> **Windows & Linux versions: coming soon.**

---

## What it does

- **Live monitoring** — a Dynamic-Island-style panel on the Mac + a phone web
  dashboard, one "plot" per project. Pac-Man grows as the agent works; a 👻
  ghost means it needs you.
- **Approve from anywhere** — when a tool needs approval you can allow/deny from
  the **terminal**, the **phone**, the **Mac Island**, or the **Garmin watch** —
  whichever answers first wins.
- **Steer from your phone** — type a prompt into an agent's card and it's fed
  back into the session; a live **tmux terminal mirror** lets you type and answer
  `1.Yes / 2.No` menus remotely.
- **Garmin wrist app** — a pixel-art arcade mirror (Connect IQ) that buzzes when
  an agent needs you, lets you Allow/Deny from the wrist, and shows your daily
  **AI model spend**.
- **Model-spend graph + budget warning** — reads your Claude Code transcripts,
  computes today's **$ cost per model**, and warns at 80% ("tinggal dikit") and
  100% ("OVER BUDGET") of a daily budget — on the Island, the webapp, and the
  watch.
- **Private by default** — binds only loopback + your Tailscale address (never
  the whole LAN). Every endpoint is protected by a token the app mints.

---

## Requirements

- macOS on Apple Silicon
- [Tailscale](https://tailscale.com) (for phone/watch access)
- `tmux`, `curl`, `jq` — `brew install tmux jq`
- [Claude Code](https://claude.com/claude-code)
- For the watch app: the [Connect IQ SDK](https://developer.garmin.com/connect-iq/sdk/)
  + a Garmin device (Forerunner 165 and up)

---

## Quick start

### 1. Build & run the Mac app

```bash
./build-dev.sh          # compiles with swiftc into build/AgentGarden.app
open build/AgentGarden.app
```

The Pac-Man appears in the menu bar / at the top-center notch.

### 2. Wire the Claude Code hooks

```bash
hooks/install.sh        # checks deps + adds a `garden` shell alias
```

Then merge `hooks/settings-snippet.json`'s `hooks` block into
`~/.claude/settings.json` (global, so every project reports). Start any Claude
Code session — the Island lights up. Details in [`hooks/README.md`](hooks/README.md).

### 3. Drive it from your phone

- In the app's Island: **🔗 copy phone link** (or **📱 QR**) — it's a
  `https://<your-machine>.<tailnet>.ts.net/?token=…` link over Tailscale.
- Open it on your phone (Tailscale ON), "Add to Home Screen".
- Tap **⌨** on a card for the live terminal; type prompts into the card to steer.

### 4. Remote approval

Arm it from the Island (📡). While armed, non-read-only tools ask for allow/deny.
Answer from the terminal (`y`/`n`), the phone, the Island, or the watch.

### 5. The Garmin watch app (optional)

See [`garmin/GardenWatch/README.md`](garmin/GardenWatch/README.md). In short:
`tailscale serve` fronts GardenServer with HTTPS, you copy `Config.mc.example`
→ `Config.mc` and fill in your MagicDNS URL + token, then build with the Connect
IQ SDK and sideload the `.prg`.

---

## How the pieces fit

```
Claude Code hook ──POST──▶ GardenServer (:4141, macOS app)
                              │  ├─ Dynamic Island (SwiftUI)
                              │  ├─ GET /  phone dashboard (HTML)
                              │  └─ GET /usage  model-spend
     phone / watch ──HTTPS (Tailscale) ──▶ approve · prompt · terminal · usage
```

- `App/`, `Core/`, `UI/` — the macOS app + `GardenServer` + `UsageMonitor`.
- `hooks/` — the Claude Code hook bridge, tmux bridge, `garden` launcher, installer.
- `garmin/GardenWatch/` — the Connect IQ (Monkey C) watch app.

---

## Roadmap

- [ ] **Windows version** — *coming soon*
- [ ] **Linux version** — *coming soon*
- [ ] Away-mode toggle in the Island (currently a `~/.agent-garden-away` marker)
- [ ] ntfy/Pushover push relay as a hands-free wrist alternative

---

## License

Personal project — use at your own risk. Not affiliated with Anthropic or Garmin.
