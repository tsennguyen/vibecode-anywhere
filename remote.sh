#!/usr/bin/env bash
# vibecode-anywhere — remote.sh: sign in to / start / check phone remote control for each agent in AGENTS.
# Works on Linux, macOS and Windows (Git Bash, or .\vibe.ps1 remote ...).
#
#   ./remote.sh login   [agent]   interactive sign-in (prints a link + code you open on the phone)
#   ./remote.sh start   [agent]   start remote control
#   ./remote.sh status  [agent]
#   ./remote.sh autostart claude  bring Claude remote control back after a reboot
#                                 (Linux: systemd user unit · macOS: LaunchAgent · Windows: Scheduled Task at logon)
#
# How each agent stays online (details: docs/AGENTS-GUIDE.md):
#   antigravity → `agy remote-control start` registers its own OS service (systemd / launchd / Windows). Phone: antigravity.google.com
#   claude      → `claude remote-control` must keep running: tmux on Linux/macOS, a minimized window on Windows.
#                 Phone: Claude app → Code. Needs a Pro/Max/Team/Enterprise login (API keys do NOT work).
#   codex       → macOS/Windows: the ChatGPT desktop app is the official remote host (pair the phone in its settings).
#                 Linux: a desktop elsewhere adds this machine as an SSH host; headless `codex remote-control` if your
#                 version has it; otherwise SSH + tmux.
# (c) 2026 Nguyễn Việt Thành — MIT License.
set -uo pipefail
source "$(cd "$(dirname "$0")" && pwd)/scripts/lib.sh"

ACTION="${1:-status}"; ONLY="${2:-}"
targets=(); for a in ${AGENTS[@]+"${AGENTS[@]}"}; do [ -z "$ONLY" ] || [ "$ONLY" = "$a" ] && targets+=("$a"); done
[ "${#targets[@]}" -gt 0 ] || die "no agent matches '${ONLY}' (AGENTS in config: ${AGENTS[*]-none})"
WORKDIR="$HOST_ROOT"; [ -d "$WORKDIR" ] || WORKDIR="$HOME"

tmux_up() { have tmux && tmux has-session -t "$1" 2>/dev/null; }
winpath() { cygpath -w "$1" 2>/dev/null || printf '%s' "$1"; }
exe_win() { local p; p="$(command -v "$1")" || return 1; [ -f "$p.exe" ] && p="$p.exe"; winpath "$p"; }
codex_has_rc() { codex remote-control --help >/dev/null 2>&1; }

# ── Antigravity ──────────────────────────────────────────────────────────────
agy_daemon_ok() {
  case "$VA_OS" in
    linux) systemctl --user is-active --quiet antigravity-cli-daemon 2>/dev/null ;;
    *)     proc_running "remote-control serve" ;;
  esac
}
antigravity() {
  have agy || { bad "agy not installed → bootstrap"; return 1; }
  case "$ACTION" in
    login)  echo ">> Antigravity: a link is printed; open it on your phone, sign in with Google, paste the code back, then type /exit"
            ( cd "$WORKDIR" && agy ) ;;
    start)  agy remote-control start --name "$HOST_NAME" && agy remote-control status
            echo "   Phone: https://antigravity.google.com → machine '$HOST_NAME' → Add to Home Screen. Pick a PROJECT in each new chat."
            [ "$VA_OS" = linux ] || echo "   macOS/Windows: the daemon lives in your user session → enable automatic sign-in (docs/HOSTS.md)." ;;
    status) agy remote-control status 2>&1 | head -5
            agy_daemon_ok && ok "antigravity daemon running" || bad "antigravity daemon not running → RESCUE §1" ;;
  esac
}

# ── Claude Code ──────────────────────────────────────────────────────────────
claude_up() {
  if [ "$VA_OS" = windows ]; then proc_running "claude*remote-control"; else tmux_up claude-rc; fi
}
claude_() {
  have claude || { bad "claude not installed → bootstrap"; return 1; }
  case "$ACTION" in
    login)  echo ">> Claude Code: type /login, open the link on your phone, paste the code back."
            echo "   Then run 'claude remote-control' once here, answer y to the one-time prompt, Ctrl+C, and run: remote start claude"
            ( cd "$WORKDIR" && claude ) ;;
    start)
      if claude_up; then ok "claude remote control already running"
      elif [ "$VA_OS" = windows ]; then
        ps1 "Start-Process -WindowStyle Minimized -WorkingDirectory '$(winpath "$WORKDIR")' -FilePath '$(exe_win claude)' -ArgumentList 'remote-control','--name','$HOST_NAME'"
        sleep 5; claude_up && ok "claude remote control started (minimized window)" || bad "claude exited — run 'claude remote-control' in a terminal to see why"
      else
        have tmux || { bad "tmux missing → bootstrap"; return 1; }
        tmux new-session -d -s claude-rc -c "$WORKDIR" "claude remote-control --name '$HOST_NAME'"
        sleep 3; claude_up && ok "claude-rc started in tmux (watch: tmux attach -t claude-rc)" || bad "claude remote-control exited — run it in the foreground once to see why (login? plan?)"
      fi
      echo "   Phone: Claude app → Code (or https://claude.ai/code) → session '$HOST_NAME'." ;;
    status) claude_up && ok "claude remote control running" || warn "claude remote control not running → remote start claude (RESCUE §1)" ;;
    autostart)
      case "$VA_OS" in
        linux)
          local unit="$HOME/.config/systemd/user/vibecode-claude-rc.service"
          mkdir -p "$(dirname "$unit")"
          cat > "$unit" <<EOF
[Unit]
Description=Claude Code remote control in tmux (vibecode-anywhere)
After=network-online.target

[Service]
Type=forking
WorkingDirectory=$WORKDIR
Environment=PATH=$HOME/.local/bin:/usr/local/bin:/usr/bin:/bin
ExecStart=$(command -v tmux) new-session -d -s claude-rc "$(command -v claude) remote-control --name '$HOST_NAME'"
ExecStop=$(command -v tmux) kill-session -t claude-rc
RemainAfterExit=yes

[Install]
WantedBy=default.target
EOF
          systemctl --user daemon-reload && systemctl --user enable vibecode-claude-rc.service && ok "enabled at boot (unofficial unit: $unit)" ;;
        macos)
          local plist="$HOME/Library/LaunchAgents/com.vibecode.claude-rc.plist"
          mkdir -p "$(dirname "$plist")"
          cat > "$plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>com.vibecode.claude-rc</string>
  <key>ProgramArguments</key><array>
    <string>$(command -v tmux)</string><string>new-session</string><string>-d</string><string>-s</string><string>claude-rc</string>
    <string>$(command -v claude) remote-control --name '$HOST_NAME'</string>
  </array>
  <key>WorkingDirectory</key><string>$WORKDIR</string>
  <key>EnvironmentVariables</key><dict><key>PATH</key><string>$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin</string></dict>
  <key>RunAtLoad</key><true/>
</dict></plist>
EOF
          launchctl unload "$plist" 2>/dev/null; launchctl load "$plist" && ok "starts at login (LaunchAgent: $plist)" ;;
        windows)
          ps1 "\$a = New-ScheduledTaskAction -Execute '$(exe_win claude)' -Argument 'remote-control --name $HOST_NAME' -WorkingDirectory '$(winpath "$WORKDIR")'; \$t = New-ScheduledTaskTrigger -AtLogOn -User \$env:USERNAME; \$s = New-ScheduledTaskSettingsSet -ExecutionTimeLimit 0 -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1); Register-ScheduledTask -TaskName 'vibecode-claude-rc' -Action \$a -Trigger \$t -Settings \$s -Force | Out-Null" \
            && ok "starts at sign-in (Scheduled Task 'vibecode-claude-rc')" ;;
      esac ;;
  esac
}

# ── Codex ────────────────────────────────────────────────────────────────────
codex_() {
  have codex || { bad "codex not installed → bootstrap"; return 1; }
  case "$ACTION" in
    login)  echo ">> Codex: device-code sign-in. Open the link on your phone and enter the code."
            codex login --device-auth ;;
    start)
      if [ "$VA_OS" = macos ] || [ "$VA_OS" = windows ]; then
        echo ">> Official path on this OS: the ChatGPT desktop app hosts Codex for your phone."
        echo "   Open ChatGPT (signed in) → Settings → Connections → Control this Mac or PC → scan the QR with your phone."
        echo "   Keep the app running (enable 'open at login'). Phone: ChatGPT app → Codex → this computer."
      elif codex_has_rc; then
        echo ">> Your codex has 'remote-control' (headless pairing; not in the user docs yet — verify with: codex remote-control --help)"
        codex remote-control start && codex remote-control pair || warn "codex remote-control failed — use the SSH/tmux fallback"
      else
        echo ">> No headless remote control in this codex version. From the phone you can:"
        echo "   1. Official: an always-on Mac/Windows with the ChatGPT desktop app adds this host over SSH (Settings → Connections)."
        echo "   2. Fallback: SSH from the phone (Termius) → tmux attach -t codex"
      fi
      if have tmux; then tmux_up codex || tmux new-session -d -s codex -c "$WORKDIR" "codex"; ok "tmux session 'codex' ready (SSH fallback: tmux attach -t codex)"; fi ;;
    status) codex login status 2>&1 | head -2
            if have tmux; then tmux_up codex && ok "codex tmux session running" || warn "codex tmux session not running"; fi ;;
  esac
}

for a in "${targets[@]}"; do
  step "$a: $ACTION"
  if [ "$ACTION" = autostart ] && [ "$a" != claude ]; then
    echo "  (only claude needs this: Antigravity registers its own OS service; Codex uses the ChatGPT app or tmux)"; continue
  fi
  case "$a" in
    antigravity) antigravity ;;
    claude) claude_ ;;
    codex) codex_ ;;
    *) warn "unknown agent '$a' (use antigravity, claude, codex)" ;;
  esac
done
