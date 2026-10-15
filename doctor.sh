#!/usr/bin/env bash
# vibecode-anywhere — doctor.sh: read-only health check. Safe any time, from the phone or by the agent.
# Linux, macOS, Windows (Git Bash / .\vibe.ps1 doctor).
# Every WARN/FAIL line ends with the RESCUE section to follow (docs/RESCUE.md / RESCUE.en.md).
# (c) 2026 Nguyễn Việt Thành — MIT License.
set -uo pipefail
source "$(cd "$(dirname "$0")" && pwd)/scripts/lib.sh"

echo "vibecode-anywhere $VA_VERSION — $HOST_NAME: $HOST_KIND_LABEL, $(va_os_label)"

echo "== Agents (${AGENTS[*]-none})"
if wants_agent antigravity; then
  if have agy; then
    agy remote-control status 2>&1 | head -4 | sed 's/^/       /'
    if [ "$VA_OS" = linux ]; then
      systemctl --user is-active --quiet antigravity-cli-daemon 2>/dev/null && ok "antigravity daemon active" || bad "antigravity daemon not active → RESCUE §1"
    else
      proc_running "remote-control serve" && ok "antigravity daemon running" || bad "antigravity daemon not running → RESCUE §1"
    fi
  else bad "agy not installed → bootstrap"; fi
fi
if wants_agent claude; then
  if have claude; then
    if [ "$VA_OS" = windows ]; then up=0; proc_running "claude*remote-control" && up=1
    else up=0; have tmux && tmux has-session -t claude-rc 2>/dev/null && up=1; fi
    [ "$up" = 1 ] && ok "claude remote control running" || warn "claude remote control not running → remote.sh start claude (RESCUE §1)"
  else bad "claude not installed → bootstrap"; fi
fi
if wants_agent codex; then
  if have codex; then
    codex login status >/dev/null 2>&1 && ok "codex signed in" || warn "codex not signed in → remote.sh login codex (RESCUE §6)"
    case "$VA_OS" in
      macos)   pgrep -x ChatGPT >/dev/null 2>&1 && ok "ChatGPT desktop app running (Codex remote host)" || warn "ChatGPT desktop app not running → open it (RESCUE §1)" ;;
      windows) proc_running "ChatGPT.exe" && ok "ChatGPT desktop app running (Codex remote host)" || warn "ChatGPT desktop app not running → open it (RESCUE §1)" ;;
    esac
  else bad "codex not installed → bootstrap"; fi
fi

echo "== Machine ($PROFILE_LABEL)"
disk="$(disk_pct)"
[ "${disk:-0}" -lt "$DISK_WARN_PCT" ] && ok "disk ${disk}% used" || warn "disk ${disk}% used → RESCUE §4"
mem_avail="$(va_mem_avail_mb)"; swap_total="$(va_swap_mb)"
[ "${mem_avail:-0}" -gt 800 ] && ok "RAM available ${mem_avail} MB of $(va_ram_mb) MB (swap ${swap_total} MB)" \
  || warn "RAM available only ${mem_avail} MB (swap ${swap_total} MB) → RESCUE §3"
ok "load $(va_load) on $(va_cpus) CPUs"
curl -fsS -o /dev/null --max-time 8 https://github.com && ok "internet reaches github.com" || bad "no internet to github.com"
if { git config --global user.name >/dev/null 2>&1 && git config --global user.email >/dev/null 2>&1; } \
   || { [ -n "$GIT_NAME" ] && [ -n "$GIT_EMAIL" ]; }; then
  ok "git identity set"
else
  warn "git has no user.name/email → commits will fail; set GIT_NAME/GIT_EMAIL in hub.conf and re-run sync"
fi
if have gh; then gh auth status >/dev/null 2>&1 && ok "GitHub CLI signed in" || bad "GitHub CLI not signed in → RESCUE §6"; fi
if wants_stack docker; then
  if have docker; then docker info >/dev/null 2>&1 && ok "docker running" || warn "docker installed but not running (Docker Desktop / colima not started?)"
  else warn "docker not installed"; fi
fi
if [ "$WANT_SSH" = 1 ]; then
  case "$VA_OS" in
    linux)   { systemctl is-active --quiet ssh 2>/dev/null || systemctl is-active --quiet sshd 2>/dev/null; } && ok "SSH server running" || warn "SSH server not running (your phone rescue line) → bootstrap" ;;
    macos)   pgrep -x sshd >/dev/null 2>&1 || nc -z localhost 22 2>/dev/null && ok "SSH (Remote Login) reachable" || warn "Remote Login off → System Settings → General → Sharing" ;;
    windows) [ "$(ps1 "(Get-Service sshd -ErrorAction SilentlyContinue).Status")" = Running ] && ok "OpenSSH server running" || warn "OpenSSH server not running → bootstrap.ps1" ;;
  esac
fi
if wants_tool tailscale && have tailscale; then
  tailscale status >/dev/null 2>&1 && ok "Tailscale connected" || warn "Tailscale not connected → tailscale up"
fi

echo "== Repos (uncommitted / unpushed work is at risk)"
check_repo() {
  local p="$1" d="$HOST_ROOT/$1"
  [ -e "$d/.git" ] || { warn "$p missing → sync.sh"; return; }
  local br dirty ahead
  br="$(git -C "$d" branch --show-current)"; [ -n "$br" ] || br="detached"
  dirty="$(git -C "$d" status --porcelain | wc -l | tr -d ' ')"
  if git -C "$d" rev-parse -q --verify '@{u}' >/dev/null 2>&1; then ahead="$(git -C "$d" rev-list --count '@{u}..HEAD')"
  else ahead="$(git -C "$d" rev-list --count HEAD --not --remotes)"; fi
  if [ "$dirty" = 0 ] && [ "$ahead" = 0 ]; then ok "$p [$br] clean, pushed"
  else warn "$p [$br] $dirty uncommitted, $ahead unpushed → save-all.sh (RESCUE §5)"; fi
}
while IFS= read -r p; do [ -n "$p" ] && check_repo "$p" </dev/null; done <<EOF
$(all_paths)
EOF

echo "== Heaviest processes"
va_top_procs
