#!/usr/bin/env bash
# vibecode-anywhere — render the agent rules from templates/AGENTS.md.tpl + config, then put them where
# each agent looks for global instructions:
#   Antigravity → ~/.gemini/GEMINI.md     Claude Code → ~/.claude/CLAUDE.md     Codex → ~/.codex/AGENTS.md
# plus ~/AGENTS.md (for sessions started in the home folder). On Windows "~" is %USERPROFILE%.
# Linux/macOS get symlinks; Windows gets copies (symlinks need Developer Mode there). Re-run after config changes.
# Existing real files are backed up, never overwritten.
# (c) 2026 Nguyễn Việt Thành — MIT License.
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"
shopt -u patsub_replacement 2>/dev/null || true   # bash ≥5.2: keep '&' literal in replacements

OUT_DIR="$VA_HOME/.rendered"; OUT="$OUT_DIR/AGENTS.md"
mkdir -p "$OUT_DIR"
tpl="$(cat "$VA_HOME/templates/AGENTS.md.tpl")"
sub() { tpl="${tpl//\{\{$1\}\}/"$2"}"; }

# ── workspace table ──
rows=""
for e in ${REPOS[@]+"${REPOS[@]}"}; do
  d="$(f3 "$e")"; [ -n "$d" ] || d="(no description)"
  in_list "$(f1 "$e")" ${PUBLIC_REPOS[@]+"${PUBLIC_REPOS[@]}"} && d="**PUBLIC repo.** $d"
  rows="$rows| \`$(native_path "$HOST_ROOT/$(f1 "$e")")\` | $d |"$'\n'
done
for e in ${WORKTREES[@]+"${WORKTREES[@]}"}; do
  rows="$rows| \`$(native_path "$HOST_ROOT/$(f1 "$e")")\` | git worktree of \`$(f2 "$e")\` |"$'\n'
done
[ -n "$rows" ] || rows="| (none yet) | add REPOS to config/hub.conf |"$'\n'
rows="${rows%$'\n'}"

# ── per-OS wording ──
case "$VA_OS" in
  linux)
    never='`reboot`, `shutdown`, `poweroff`, `systemctl suspend`, `ufw`/`iptables`, editing `/etc/ssh/*`, `apt full-upgrade`/`dist-upgrade`'
    bg='Run long commands inside `tmux` so they survive a dropped session.'
    doctor="$VA_HOME/doctor.sh"; saveall="$VA_HOME/save-all.sh" ;;
  macos)
    never='`sudo shutdown`, `sudo reboot`, `pmset sleepnow`, changing `pmset`/Energy settings, `softwareupdate -i -a --restart`, toggling Remote Login'
    bg='Run long commands inside `tmux` so they survive a dropped session.'
    doctor="$VA_HOME/doctor.sh"; saveall="$VA_HOME/save-all.sh" ;;
  windows)
    never='`shutdown`, `Restart-Computer`, `Stop-Computer`, logging off / locking the session, `powercfg` changes, `netsh advfirewall` / `Set-NetFirewallProfile`, Windows Update install-and-restart, stopping the `sshd` service'
    bg='tmux does not exist here: start long jobs as their own process writing to a log file (e.g. `powershell Start-Process -WindowStyle Minimized ...` or `cmd /c start "" /min ...`) and check the log.'
    doctor="$(native_path "$VA_HOME")\\vibe.ps1 doctor   (Git Bash: $VA_HOME/doctor.sh)"
    saveall="$(native_path "$VA_HOME")\\vibe.ps1 save-all   (Git Bash: $VA_HOME/save-all.sh)" ;;
  *) never='`reboot`, `shutdown`'; bg=''; doctor="$VA_HOME/doctor.sh"; saveall="$VA_HOME/save-all.sh" ;;
esac

home_notes=""
if [ "$HOST_KIND" != vps ]; then
  home_notes="7. This is a **physical machine at {{OWNER}}'s place**: power or internet can drop. After an outage, run doctor first. Never change BIOS/UEFI, power, Wi-Fi/network or user-account settings, and never install drivers."$'\n'
fi
[ "$HOST_KIND" = laptop ] && home_notes="${home_notes}8. It is a laptop on AC power: never trigger sleep, keep heavy jobs short to limit heat."$'\n'
shared_notes=""
if [ "$HOST_SHARED" = 1 ]; then
  shared_notes="- **Other people also use this computer.** Never close or kill their apps, never touch files outside \`$(native_path "$HOST_ROOT")\` and your own config, never sign out or lock the desktop session, keep CPU/RAM use moderate and stop heavy jobs when done."$'\n'
fi

# ── per-agent notes ──
daemon=""; cmds=""
if wants_agent antigravity; then
  daemon="$daemon\`agy remote-control stop|start\`"
  [ "$VA_OS" = linux ] && daemon="$daemon, \`systemctl --user stop|restart antigravity-cli-daemon\`"
  daemon="$daemon; "
  cmds="$cmds"$'\n'"agy remote-control status                                    # Antigravity daemon"
  [ "$VA_OS" = linux ] && cmds="$cmds"$'\n'"journalctl --user -u antigravity-cli-daemon -n 50 --no-pager   # its log"
fi
if wants_agent claude; then
  if [ "$VA_OS" = windows ]; then daemon="${daemon}killing the \`claude remote-control\` process; "
  else daemon="${daemon}killing the tmux session \`claude-rc\`; "; cmds="$cmds"$'\n'"tmux ls                                                      # claude-rc / codex sessions"; fi
fi
if wants_agent codex; then
  case "$VA_OS" in
    macos|windows) daemon="${daemon}quitting the ChatGPT desktop app (it hosts Codex for the phone); " ;;
    *)             daemon="${daemon}killing the tmux session \`codex\`; " ;;
  esac
  cmds="$cmds"$'\n'"codex login status                                           # Codex auth"
fi
daemon="${daemon%; }"; [ -n "$daemon" ] || daemon="the agent process"
cmds="${cmds#$'\n'}"

protected=""; for b in ${PROTECTED_BRANCHES[@]+"${PROTECTED_BRANCHES[@]}"}; do protected="$protected\`$b\`, "; done
protected="${protected%, }"
public=""; for r in ${PUBLIC_REPOS[@]+"${PUBLIC_REPOS[@]}"}; do public="$public\`$(native_path "$HOST_ROOT/$r")\`, "; done
public="${public%, }"; [ -n "$public" ] || public="none configured (still: never commit secrets anywhere)"
mirror=""; [ -n "$MIRROR_PATH" ] && mirror=" (\`$MIRROR_PATH\` points to it, so absolute paths from the main computer still work)"
extra=""; [ -f "$VA_HOME/config/rules.extra.md" ] && extra=$'\n## 5. Owner\'s own rules\n'"$(cat "$VA_HOME/config/rules.extra.md")"$'\n'

sub HOME_NOTES "$home_notes";    sub SHARED_NOTES "$shared_notes"   # first: they contain {{OWNER}}
sub HOST_NAME "$HOST_NAME";      sub OWNER "$OWNER_NAME";         sub LANGUAGE "$REPLY_LANGUAGE"
sub KIND "$HOST_KIND_LABEL";     sub OS "$(va_os_label)";         sub PROFILE_LABEL "$PROFILE_LABEL"
sub CPUS "$(va_cpus)";           sub RAM_GB "$(( $(va_ram_mb) / 1024 ))"; sub SWAP_GB "$(( $(va_swap_mb) / 1024 ))"
sub MAX_HEAVY_JOBS "$MAX_HEAVY_JOBS"; sub DISK_WARN_PCT "$DISK_WARN_PCT"; sub DOCKER_ADVICE "$DOCKER_ADVICE"
sub NEVER_OS "$never";           sub BACKGROUND_TIP "$bg";        sub DOCTOR "$doctor"; sub SAVE_ALL "$saveall"
sub DAEMON_NOTE "$daemon";       sub HUB "$(native_path "$VA_HOME")"; sub ROOT "$(native_path "$HOST_ROOT")"
sub MIRROR_NOTE "$mirror";       sub WORKSPACE_TABLE "$rows";     sub PROTECTED "$protected"
sub PUBLIC_REPOS "$public";      sub AGENT_COMMANDS "$cmds";      sub EXTRA_RULES "$extra"; sub VERSION "v$VA_VERSION"
printf '%s\n' "$tpl" > "$OUT"

place() { # place <target path>: symlink (Linux/macOS) or copy (Windows)
  local t="$1"
  mkdir -p "$(dirname "$t")"
  if [ -e "$t" ] && [ ! -L "$t" ] && ! grep -q 'generated by vibecode-anywhere' "$t" 2>/dev/null; then
    mv "$t" "$t.bak-$(date +%Y%m%d-%H%M%S)"
    echo "  NOTE  your existing $t was moved to $t.bak-* — copy any personal rules from it into config/rules.extra.md"
  fi
  if [ "$VA_OS" = windows ]; then [ -L "$t" ] && rm -f "$t"; cp -f "$OUT" "$t"; echo "  OK    $t (copy)"
  else ln -sfn "$OUT" "$t"; echo "  OK    $t → rules"; fi
}
echo ">> Agent rules ($OUT)"
place "$HOME/AGENTS.md"
if wants_agent antigravity; then place "$HOME/.gemini/GEMINI.md"; fi
if wants_agent claude;      then place "$HOME/.claude/CLAUDE.md"; fi
if wants_agent codex;       then place "$HOME/.codex/AGENTS.md"; fi
exit 0
