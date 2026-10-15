#!/usr/bin/env bash
# vibecode-anywhere — remote.sh: sign in to / start / check phone remote control for each agent in AGENTS.
#
#   ./remote.sh login   [agent]   interactive sign-in (prints a link + code you open on the phone)
#   ./remote.sh start   [agent]   start remote control (Antigravity: OS service; Claude/Codex: tmux)
#   ./remote.sh status  [agent]
#   ./remote.sh autostart claude  optional: systemd user unit that re-creates the claude tmux session at boot
#
# How the phone connects (details: docs/AGENTS-GUIDE.md):
#   antigravity → https://antigravity.google.com  (same Google account) → pick the machine by name
#   claude      → Claude mobile app → Code, or https://claude.ai/code  (Pro/Max/Team/Enterprise; API keys NOT supported)
#   codex       → official: ChatGPT desktop app (Mac/Windows) adds this host over SSH, phone controls that app.
#                 headless `codex remote-control` is used only if your codex version has it.
#                 fallback: SSH from the phone (Termius) + `tmux attach -t codex`.
# (c) 2026 Nguyễn Việt Thành — MIT License.
set -uo pipefail
source "$(cd "$(dirname "$0")" && pwd)/scripts/lib.sh"

ACTION="${1:-status}"; ONLY="${2:-}"
targets=(); for a in ${AGENTS[@]+"${AGENTS[@]}"}; do [ -z "$ONLY" ] || [ "$ONLY" = "$a" ] && targets+=("$a"); done
[ "${#targets[@]}" -gt 0 ] || die "no agent matches '${ONLY}' (AGENTS in config: ${AGENTS[*]-none})"
WORKDIR="$HOST_ROOT"; [ -d "$WORKDIR" ] || WORKDIR="$HOME"

tmux_up() { tmux has-session -t "$1" 2>/dev/null; }
codex_has_rc() { codex remote-control --help >/dev/null 2>&1; }

antigravity() {
  have agy || { bad "agy not installed → ./bootstrap.sh"; return 1; }
  case "$ACTION" in
    login)  echo ">> Antigravity: a link is printed; open it on your phone, sign in with Google, paste the code back, then type /exit"
            ( cd "$WORKDIR" && agy ) ;;
    start)  agy remote-control start --name "$HOST_NAME" && agy remote-control status
            echo "   Phone: https://antigravity.google.com → machine '$HOST_NAME' → Add to Home Screen. Pick a PROJECT in each new chat." ;;
    status) agy remote-control status 2>&1 | head -5
            systemctl --user is-active --quiet antigravity-cli-daemon 2>/dev/null && ok "antigravity daemon active" || bad "antigravity daemon not active → RESCUE §1" ;;
  esac
}

claude_() {
  have claude || { bad "claude not installed → ./bootstrap.sh"; return 1; }
  case "$ACTION" in
    login)  echo ">> Claude Code: type /login, open the link on your phone, paste the code back."
            echo "   Then run 'claude remote-control' once here, answer y to the one-time prompt, Ctrl+C, and run ./remote.sh start claude"
            ( cd "$WORKDIR" && claude ) ;;
    start)  if tmux_up claude-rc; then ok "claude-rc already running"; else
              tmux new-session -d -s claude-rc -c "$WORKDIR" "claude remote-control --name '$HOST_NAME'"
              sleep 3; tmux_up claude-rc && ok "claude-rc started in tmux" || bad "claude remote-control exited — run it in the foreground once to see why (login? plan?)"
            fi
            echo "   Phone: Claude app → Code (or https://claude.ai/code) → session '$HOST_NAME'. Watch: tmux attach -t claude-rc" ;;
    status) tmux_up claude-rc && ok "claude-rc tmux session running" || warn "claude-rc not running → ./remote.sh start claude" ;;
    autostart)
            local unit="$HOME/.config/systemd/user/vibecode-claude-rc.service" tmuxbin claudebin
            tmuxbin="$(command -v tmux)"; claudebin="$(command -v claude)"
            mkdir -p "$(dirname "$unit")"
            cat > "$unit" <<EOF
[Unit]
Description=Claude Code remote control in tmux (vibecode-anywhere)
After=network-online.target

[Service]
Type=forking
WorkingDirectory=$WORKDIR
Environment=PATH=$HOME/.local/bin:/usr/local/bin:/usr/bin:/bin
ExecStart=$tmuxbin new-session -d -s claude-rc "$claudebin remote-control --name '$HOST_NAME'"
ExecStop=$tmuxbin kill-session -t claude-rc
RemainAfterExit=yes

[Install]
WantedBy=default.target
EOF
            systemctl --user daemon-reload && systemctl --user enable vibecode-claude-rc.service \
              && ok "claude-rc will start at boot (unofficial unit: $unit)" ;;
  esac
}

codex_() {
  have codex || { bad "codex not installed → ./bootstrap.sh"; return 1; }
  case "$ACTION" in
    login)  echo ">> Codex: device-code sign-in. Open the link on your phone and enter the code."
            codex login --device-auth ;;
    start)  if codex_has_rc; then
              echo ">> Your codex has 'remote-control' (headless pairing; not in the user docs yet — verify with: codex remote-control --help)"
              codex remote-control start && codex remote-control pair || warn "codex remote-control failed — use the SSH/tmux fallback"
            else
              echo ">> No headless remote control in this codex version. Two ways to reach it from the phone:"
              echo "   1. Official: on an always-on Mac/Windows, ChatGPT desktop app → Settings → Connections → add this host over SSH;"
              echo "      pair your phone with that desktop app (Settings → Connections → Control this Mac or PC)."
              echo "   2. Fallback: SSH from the phone (Termius) → tmux attach -t codex"
            fi
            tmux_up codex || tmux new-session -d -s codex -c "$WORKDIR" "codex"
            ok "tmux session 'codex' ready (tmux attach -t codex)" ;;
    status) codex login status 2>&1 | head -2
            tmux_up codex && ok "codex tmux session running" || warn "codex tmux session not running" ;;
  esac
}

for a in "${targets[@]}"; do
  step "$a: $ACTION"
  if [ "$ACTION" = autostart ] && [ "$a" != claude ]; then
    echo "  (only claude needs this; Antigravity registers its own OS service, codex uses its own daemon or tmux)"; continue
  fi
  case "$a" in
    antigravity) antigravity ;;
    claude) claude_ ;;
    codex) codex_ ;;
    *) warn "unknown agent '$a' (use antigravity, claude, codex)" ;;
  esac
done
