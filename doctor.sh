#!/usr/bin/env bash
# vibecode-anywhere — doctor.sh: read-only health check. Safe any time, from the phone or by the agent.
# Every WARN/FAIL line ends with the RESCUE section to follow (docs/RESCUE.md / RESCUE.en.md).
# (c) 2026 Nguyễn Việt Thành — MIT License.
set -uo pipefail
source "$(cd "$(dirname "$0")" && pwd)/scripts/lib.sh"

echo "== Agents (${AGENTS[*]-none})"
if wants_agent antigravity; then
  if have agy; then
    agy remote-control status 2>&1 | head -4 | sed 's/^/       /'
    systemctl --user is-active --quiet antigravity-cli-daemon 2>/dev/null && ok "antigravity daemon active" || bad "antigravity daemon not active → RESCUE §1"
  else bad "agy not installed → ./bootstrap.sh"; fi
fi
if wants_agent claude; then
  if have claude; then
    tmux has-session -t claude-rc 2>/dev/null && ok "claude remote-control (tmux claude-rc) running" || warn "claude-rc not running → ./remote.sh start claude (RESCUE §1)"
  else bad "claude not installed → ./bootstrap.sh"; fi
fi
if wants_agent codex; then
  if have codex; then
    codex login status >/dev/null 2>&1 && ok "codex signed in" || warn "codex not signed in → ./remote.sh login codex (RESCUE §6)"
  else bad "codex not installed → ./bootstrap.sh"; fi
fi

echo "== Machine ($PROFILE_LABEL)"
disk="$(disk_pct)"
[ "$disk" -lt "$DISK_WARN_PCT" ] && ok "disk ${disk}% used" || warn "disk ${disk}% used → RESCUE §4"
mem_avail="$(free -m | awk '/Mem:/ {print $7}')"; swap_total="$(free -m | awk '/Swap:/ {print $2}')"
[ "$mem_avail" -gt 800 ] && ok "RAM available ${mem_avail} MB (swap ${swap_total} MB)" || warn "RAM available only ${mem_avail} MB (swap ${swap_total} MB) → RESCUE §3"
ok "load $(cut -d' ' -f1-3 /proc/loadavg) on $(nproc) CPUs"
curl -fsS -o /dev/null --max-time 8 https://github.com && ok "internet reaches github.com" || bad "no internet to github.com"
if have gh; then gh auth status >/dev/null 2>&1 && ok "GitHub CLI signed in" || bad "GitHub CLI not signed in → RESCUE §6"; fi
if wants_stack docker; then
  if have docker; then docker info >/dev/null 2>&1 && ok "docker running" || warn "docker installed but not usable"
  else warn "docker not installed"; fi
fi

echo "== Repos (uncommitted / unpushed work is at risk)"
check_repo() {
  local p="$1" d="$HOST_ROOT/$1"
  [ -e "$d/.git" ] || { warn "$p missing → ./sync.sh"; return; }
  local br dirty ahead
  br="$(git -C "$d" branch --show-current)"
  dirty="$(git -C "$d" status --porcelain | wc -l | tr -d ' ')"
  if git -C "$d" rev-parse -q --verify '@{u}' >/dev/null 2>&1; then ahead="$(git -C "$d" rev-list --count '@{u}..HEAD')"
  else ahead="$(git -C "$d" rev-list --count HEAD --not --remotes)"; fi
  if [ "$dirty" = 0 ] && [ "$ahead" = 0 ]; then ok "$p [$br] clean, pushed"
  else warn "$p [$br] $dirty uncommitted, $ahead unpushed → ./save-all.sh (RESCUE §5)"; fi
}
while IFS= read -r p; do [ -n "$p" ] && check_repo "$p"; done <<EOF
$(all_paths)
EOF

echo "== Heaviest processes"
ps -eo rss,comm --sort=-rss | awk 'NR>1 && NR<=6 {printf "       %5d MB  %s\n", $1/1024, $2}'
