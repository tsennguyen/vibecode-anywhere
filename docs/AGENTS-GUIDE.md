# Agent guide: driving Antigravity, Claude Code and Codex from a phone

Checked against official docs in **October 2026**. These products change fast: if a command differs, trust `<tool> --help` and the linked docs. Contributions welcome.

| | **Antigravity CLI** (`agy`) | **Claude Code** (`claude`) | **OpenAI Codex CLI** (`codex`) |
|---|---|---|---|
| Phone side | https://antigravity.google.com (web app, *Add to Home Screen*) | **Claude** app → *Code*, or https://claude.ai/code | **ChatGPT** app → *Codex* |
| Account | Google account | **Pro / Max / Team / Enterprise** subscription. API keys do **not** work for remote control | ChatGPT account (plan with Codex) |
| How it stays online on the host | Official **OS service** (`agy remote-control start`, systemd user unit `antigravity-cli-daemon`). Survives logout and reboot | The `claude remote-control` process has to keep running → `./remote.sh start claude` runs it in tmux `claude-rc`. Optional: `./remote.sh autostart claude` (unofficial systemd unit) | Official mobile path needs the **ChatGPT desktop app (Mac/Windows)** as the host; that app can open this Linux machine as an **SSH host**. Without a desktop: SSH + tmux fallback |
| Global rules file (linked by `render-rules.sh`) | `~/.gemini/GEMINI.md` | `~/.claude/CLAUDE.md` | `~/.codex/AGENTS.md` |
| Sign in on a headless host | `agy` → opens a link → paste the code back → `/exit` | `claude` → `/login` → open the link → paste the code | `codex login --device-auth` → open the link → enter the code |
| Best for | Main agent: the only one of the three with a real background service | Primary or backup; push notifications to the phone | Users who already have a Mac/Windows desktop always on, or who live in ChatGPT |

`./remote.sh login|start|status [agent]` wraps everything below.

---

## 1. Antigravity CLI (`agy`)
Docs: https://antigravity.google/docs · CLI help: `agy remote-control --help`

```bash
curl -fsSL https://antigravity.google/cli/install.sh | bash   # bootstrap.sh does this → ~/.local/bin/agy
agy                                                           # first run: sign in with Google (link + code), then /exit
agy remote-control start --name my-vps                        # registers the OS service (systemd user unit)
agy remote-control status
```
- Phone: open https://antigravity.google.com, same Google account, pick `my-vps`, *Add to Home Screen*.
- **Pick a project for every new chat.** Otherwise it starts in the default "CLI Project" (`~/.gemini/antigravity-cli/scratch`) and the agent does not know where your code is. The generated rules tell it to `cd` to the right repo anyway.
- Projects you created on the main computer live in `~/.gemini/config/projects/*.json`. Add them to `HOME_EXTRAS` to carry them over. They hold absolute paths, so set `MIRROR_PATH` if the paths differ.
- Needs `loginctl enable-linger` (bootstrap does it) so the service runs with nobody logged in.
- Per-session alternative (when the service is broken): `tmux new -As agy` → `agy --remote-control` → it prints a link to open on the phone.
- **Do not** let the agent run `agy remote-control stop` or restart `antigravity-cli-daemon`: it would cut its own line to you.

## 2. Claude Code (`claude`)
Docs: https://code.claude.com/docs/en/remote-control · memory files: https://code.claude.com/docs/en/memory

```bash
curl -fsSL https://claude.ai/install.sh | bash      # bootstrap.sh does this
claude                                             # type /login → open the link on the phone → paste the code → /exit
cd ~/code && claude remote-control --name my-vps   # once in the foreground: answer y to the one-time prompt, then Ctrl+C
./remote.sh start claude                           # keeps it running in tmux session claude-rc
```
- Phone: **Claude app → Code** (or claude.ai/code). The session shows a computer icon with a green dot. In server mode you can start several sessions from the phone.
- Requires a **claude.ai subscription login**. If `ANTHROPIC_API_KEY`, `ANTHROPIC_AUTH_TOKEN` or an `apiKeyHelper` is set, remote control refuses to start. Unset them on the host.
- No official background service: the process must stay alive. tmux survives a dropped SSH session but **not a reboot**. `./remote.sh autostart claude` installs a small systemd user unit that recreates the tmux session at boot (unofficial, use it at your own risk).
- If the server stops, `claude remote-control` brings its sessions back (within about 4 hours).
- Push notifications: run `/config` in Claude Code and enable push. The Claude app must be installed and signed in on the phone.
- Security: anyone with the session URL controls the session. Turn on **Trusted Devices** (claude.ai → Settings → Account) if your plan has it.
- Rules: Claude reads `~/.claude/CLAUDE.md` (global) and `CLAUDE.md` in repos. For repos that only have `AGENTS.md`, add a `CLAUDE.md` containing `@AGENTS.md`.
- No-VPS alternative: **Claude Code on the web** (cloud sessions on GitHub repos): https://code.claude.com/docs/en/claude-code-on-the-web

## 3. OpenAI Codex CLI (`codex`)
Docs: https://developers.openai.com/codex/cli · remote: https://developers.openai.com/codex/remote-connections · AGENTS.md: https://developers.openai.com/codex/guides/agents-md

```bash
sudo npm install -g @openai/codex     # bootstrap.sh does this (Node is installed automatically)
codex login --device-auth             # open the link on the phone, enter the code
./remote.sh start codex               # see below
```
Three ways to reach Codex on the host from your phone:
1. **Official, needs a desktop:** an always-on **Mac or Windows** running the **ChatGPT desktop app**. Add the host to that computer's `~/.ssh/config`, then in the app go to *Settings → Connections* and add the SSH host and a project folder (the app starts `codex app-server` on the host over SSH, so `codex` must be on the login shell's PATH). Then pair your phone with the desktop: *Settings → Connections → Control this Mac or PC* and scan the QR code. From the phone you work in the ChatGPT app → Codex.
2. **Headless (not in the user docs yet):** newer Codex builds have `codex remote-control` (`start`, `pair`). `remote.sh` uses it **only if** `codex remote-control --help` works on your version. Treat it as experimental.
3. **Always works:** SSH from the phone (Termius / Blink / JuiceSSH) → `tmux attach -t codex`. A full terminal UI on a small screen is cramped. For one-shot tasks, `codex exec "…"` is easier.
- Unattended settings in `~/.codex/config.toml`: `approval_policy` (`untrusted` / `on-request` / `never`) and `sandbox_mode` (`read-only` / `workspace-write` / `danger-full-access`). `--full-auto` = workspace-write + on-request. Avoid `--yolo` on a machine that holds your secrets.
- No-VPS alternative: **Codex cloud** (chatgpt.com/codex, ChatGPT app) runs tasks in OpenAI containers against GitHub repos.

---

## Fallback for every agent: SSH + tmux
```bash
tmux new -As work        # on the host, from Termius
<agent>                  # agy / claude / codex
# leave without killing it: Ctrl+b, then d   ·   come back: tmux attach -t work
```
Use SSH keys only. If the host is a PC at home behind NAT, use **Tailscale** (`TOOLS=(tailscale)`) instead of opening ports. Remote control for all three agents uses outbound HTTPS only, so no port forwarding is needed for it.

## Windows / WSL2 as the host (experimental)
The scripts target Ubuntu/Debian. On a Windows PC that stays on, install **WSL2 + Ubuntu**, enable systemd (`/etc/wsl.conf` → `[boot]` `systemd=true`, then `wsl --shutdown`), and run everything inside Ubuntu. Keep Windows from sleeping, and keep WSL running (it stops when idle unless something holds it open). Antigravity and Claude Code also run natively on Windows, but `bootstrap.sh` does not set that up.
