# AgentGarden hooks

The bridge that feeds the Mac app. Without this, the Dynamic Island and the
phone dashboard stay empty — the app only *receives*; these hooks *report*.

`agent-garden-hook.sh` is wired to several Claude Code hook events and talks to
`GardenServer` on `http://127.0.0.1:4141`.

## Event mapping

| Claude Code hook | Garden event | Effect |
|------------------|--------------|--------|
| `SessionStart`     | `start`     | new plot for the project |
| `UserPromptSubmit` | `resume`    | un-harvests the plot, sets the task label to your prompt |
| `PostToolUse`      | `tool`      | plant grows (`growth++`), shows last tool |
| `Notification`     | `attention` | 👻 needs input |
| `Stop`             | `done` / *park* | harvests 🍒, or parks for a phone prompt when armed |
| `PreToolUse`       | *approval*  | when armed, asks the phone to allow/deny |

One garden plot per **project directory** (`basename "$cwd"`), so two sessions
in the same repo share a plot.

## Install

Run the installer once — it checks deps (`curl`/`jq`/`tmux`), adds a `garden`
alias to your shell rc (idempotent), and tells you what's left:

    hooks/install.sh

Then:

1. Make sure the Mac app is running (menu-bar Pac-Man).
2. Merge `settings-snippet.json`'s `hooks` block into `~/.claude/settings.json`
   (global, so every project reports). Fix the absolute path if you moved the
   repo.
3. Start any Claude Code session — the Island should light up.

After `source ~/.zshrc` (or a new terminal) you can launch a phone-drivable
session anywhere with `garden [name]` instead of the full script path.

## Remote approval (allow/deny from the phone)

Off by default. Arm it from the app's Island toggle (📡) right before you step
away; it creates `~/.agent-garden-remote-approval`. While armed, any
non-read-only tool pauses and asks for allow/deny.

**Decide from either side, whichever answers first:** at the laptop press
`y`/`n` in the terminal (the hook prints a one-line prompt); away from it, tap
allow/deny on the phone card. So being at the desk never means opening the
phone.

- **Read-only tools never gate** — see `READONLY_TOOLS` in the script.
- **The terminal side** reads/writes `/dev/tty` directly, so it never corrupts
  the hook's JSON decision on stdout. No controlling TTY (headless) → phone-only.
- **App unreachable / timeout (~280s)** → falls straight back to the normal
  terminal prompt, so an unattended-but-unwatched session is never stuck.
- The `PreToolUse` hook's `timeout` in settings (300s) must stay above the
  script's `APPROVAL_TIMEOUT`.

## Remote prompts (steer the agent from the phone)

Type a prompt into an agent's card on the dashboard → `POST /prompt` queues it.
A queued prompt is fed back to the session through the `Stop` hook's
`block` + `reason`, which makes Claude Code continue instead of stopping.

Because `Stop` only fires when a turn ends, remote prompts rely on **park
mode**, gated by a *separate* **away** marker (`~/.agent-garden-away`), NOT the
arm marker. While away, a finished turn does not stop immediately — it polls
`GET /prompt/<agent>` for up to ~280s, so the agent *waits* for your next
instruction instead of going idle. Send a prompt and it picks up where it left
off; `rm ~/.agent-garden-away` (coming back) releases the turn at once.

Why separate from arming: while you are AT the laptop you want a finished turn
to end immediately so you can just type your reply — no park to ESC out of.
Parking is only useful once you have actually left, so it has its own toggle.
Set it (`touch ~/.agent-garden-away`) right before you step away.

**Limitation:** if the agent is already fully idle (its turn ended and it is
not away / the park window elapsed), there is no `Stop` left to fire, so a
prompt sent then will sit queued until the next turn ends. Waking a truly idle
session from the phone needs a TTY injector (`tmux send-keys`) or running the
agent under the SDK — out of scope for the hook.

## Live terminal (tmux bridge)

The real "type from the phone → it lands in the terminal → the AI responds",
including answering `Do you want to proceed? 1.Yes 2.No` menus. The `Stop`-hook
prompt above only steers a turn as it ends; this drives the actual TTY.

Start your session with the launcher instead of `claude`:

    hooks/garden-claude.sh [name]     # name defaults to the directory

It runs `claude` inside a tmux session and starts `agent-garden-tmux-bridge.sh`
alongside. On a ~1s loop the bridge:

- `tmux capture-pane` → `POST /terminal` so the phone can render the screen;
- drains `GET /keys/<agent>` → `tmux send-keys` so phone input reaches the pane.

On the dashboard, tap **⌨** on an agent's card: you see the live screen, quick
keys (1·Yes / 2·No / y / n / ↑ / ↓ / Enter / esc), and a text box that sends
what you type followed by Enter. The agent name matches the hook's agent id
(both are the directory basename), so the card and the terminal line up.

Requires `tmux` (`brew install tmux`).

## Auth (token)

Every endpoint except the dashboard shell (`GET /`, `/icon.png`) requires the
shared token the app mints at `~/.agent-garden-token` (0600). The hook reads
that file and sends `Authorization: Bearer <token>`; the phone gets it from the
`?token=…` in the link you copy from the app (Island → 🔗 copy phone link).

No token / wrong token → `401`. If the app never ran (no token file), the hook's
calls 401 and the session degrades exactly as if the app were down — approvals
fall back to the terminal prompt.

## Safety

Every network call is capped with `curl --max-time` and the script exits `0`
unless it is deliberately denying a tool. If the app is down, sessions behave
exactly as if the hook were absent.

## Config (env vars)

| Var | Default | Meaning |
|-----|---------|---------|
| `GARDEN_URL` | `http://127.0.0.1:4141` | where GardenServer listens |

## Requirements

`curl` + `jq`, both at `/usr/bin` on macOS.
