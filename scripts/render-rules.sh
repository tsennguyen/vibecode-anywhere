#!/usr/bin/env bash
# vibecode-anywhere — render the agent rules from templates/AGENTS.md.tpl + config, then link them where
# each agent looks for global instructions:
#   Antigravity → ~/.gemini/GEMINI.md     Claude Code → ~/.claude/CLAUDE.md     Codex → ~/.codex/AGENTS.md
# plus ~/AGENTS.md (for sessions started in $HOME). Existing real files are backed up, never overwritten.
# (c) 2026 Nguyễn Việt Thành — MIT License.
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"
shopt -u patsub_replacement 2>/dev/null || true   # bash ≥5.2: keep '&' literal in replacements

OUT_DIR="$VA_HOME/.rendered"; OUT="$OUT_DIR/AGENTS.md"
mkdir -p "$OUT_DIR"
tpl="$(cat "$VA_HOME/templates/AGENTS.md.tpl")"
sub() { tpl="${tpl//\{\{$1\}\}/"$2"}"; }

# workspace table
rows=""
for e in ${REPOS[@]+"${REPOS[@]}"}; do
  d="$(f3 "$e")"; [ -n "$d" ] || d="(no description)"
  in_list "$(f1 "$e")" ${PUBLIC_REPOS[@]+"${PUBLIC_REPOS[@]}"} && d="**PUBLIC repo.** $d"
  rows="$rows| \`$HOST_ROOT/$(f1 "$e")\` | $d |"$'\n'
done
for e in ${WORKTREES[@]+"${WORKTREES[@]}"}; do
  rows="$rows| \`$HOST_ROOT/$(f1 "$e")\` | git worktree of \`$(f2 "$e")\` |"$'\n'
done
[ -n "$rows" ] || rows="| (none yet) | add REPOS to config/hub.conf |"$'\n'
rows="${rows%$'\n'}"

# per-agent notes
daemon=""; cmds=""
if wants_agent antigravity; then
  daemon="$daemon\`agy remote-control stop|start\`, \`systemctl --user stop|restart antigravity-cli-daemon\`; "
  cmds="$cmds"$'\n'"agy remote-control status                                    # Antigravity daemon"
  cmds="$cmds"$'\n'"journalctl --user -u antigravity-cli-daemon -n 50 --no-pager   # its log"
fi
if wants_agent claude; then
  daemon="${daemon}killing the tmux session \`claude-rc\` (Claude Code remote control); "
  cmds="$cmds"$'\n'"tmux ls                                                      # claude-rc / codex sessions"
fi
if wants_agent codex; then
  daemon="${daemon}killing the tmux session \`codex\`; "
  cmds="$cmds"$'\n'"codex login status                                           # Codex auth"
fi
daemon="${daemon%; }"; [ -n "$daemon" ] || daemon="the agent process"
cmds="${cmds#$'\n'}"

protected=""; for b in ${PROTECTED_BRANCHES[@]+"${PROTECTED_BRANCHES[@]}"}; do protected="$protected\`$b\`, "; done
protected="${protected%, }"
public=""; for r in ${PUBLIC_REPOS[@]+"${PUBLIC_REPOS[@]}"}; do public="$public\`$HOST_ROOT/$r\`, "; done
public="${public%, }"; [ -n "$public" ] || public="none configured (still: never commit secrets anywhere)"
mirror=""; [ -n "$MIRROR_PATH" ] && mirror=" (\`$MIRROR_PATH\` is a symlink to it, so absolute paths from the main computer still work)"
extra=""; [ -f "$VA_HOME/config/rules.extra.md" ] && extra=$'\n## 5. Owner\'s own rules\n'"$(cat "$VA_HOME/config/rules.extra.md")"$'\n'

os="$( . /etc/os-release 2>/dev/null && echo "$PRETTY_NAME" || uname -s)"
swap_now="$(free -g 2>/dev/null | awk '/Swap:/ {print $2}')"

sub HOST_NAME "$HOST_NAME";      sub OWNER "$OWNER_NAME";         sub LANGUAGE "$REPLY_LANGUAGE"
sub OS "$os";                    sub PROFILE_LABEL "$PROFILE_LABEL"
sub CPUS "$(nproc 2>/dev/null || echo '?')"; sub RAM_GB "$(( $(va_ram_mb) / 1024 ))"; sub SWAP_GB "${swap_now:-$SWAP_GB}"
sub MAX_HEAVY_JOBS "$MAX_HEAVY_JOBS"; sub DISK_WARN_PCT "$DISK_WARN_PCT"; sub DOCKER_ADVICE "$DOCKER_ADVICE"
sub DAEMON_NOTE "$daemon";       sub HUB "$VA_HOME";              sub ROOT "$HOST_ROOT"
sub MIRROR_NOTE "$mirror";       sub WORKSPACE_TABLE "$rows";     sub PROTECTED "$protected"
sub PUBLIC_REPOS "$public";      sub AGENT_COMMANDS "$cmds";      sub EXTRA_RULES "$extra"
printf '%s\n' "$tpl" > "$OUT"

link() { # link <target path>
  local t="$1"
  mkdir -p "$(dirname "$t")"
  if [ -e "$t" ] && [ ! -L "$t" ]; then
    mv "$t" "$t.bak-$(date +%Y%m%d-%H%M%S)"; echo "  NOTE  backed up existing $t"
  fi
  ln -sfn "$OUT" "$t"; echo "  OK    $t → rules"
}
echo ">> Agent rules ($OUT)"
link "$HOME/AGENTS.md"
wants_agent antigravity && link "$HOME/.gemini/GEMINI.md"
wants_agent claude      && link "$HOME/.claude/CLAUDE.md"
wants_agent codex       && link "$HOME/.codex/AGENTS.md"
exit 0
