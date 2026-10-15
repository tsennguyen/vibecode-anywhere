# shellcheck shell=bash
# vibecode-anywhere — shared helpers, sourced by every script.
# Must stay compatible with bash 3.2 (macOS) and Git Bash (Windows): no associative arrays, no mapfile.
# (c) 2026 Nguyễn Việt Thành — MIT License. https://github.com/tsennguyen/vibecode-anywhere

VA_HOME="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PATH="$HOME/.local/bin:$PATH"

step() { printf '\n\033[1;36m== %s\033[0m\n' "$*"; }
ok()   { printf '  \033[32mOK  \033[0m %s\n' "$*"; }
warn() { printf '  \033[33mWARN\033[0m %s\n' "$*"; }
bad()  { printf '  \033[31mFAIL\033[0m %s\n' "$*"; }
die()  { printf '\033[31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

# ── defaults (config overrides) ──────────────────────────────────────────────
OWNER_NAME="the owner"; REPLY_LANGUAGE="English"; HOST_NAME="vibecode-host"; TIMEZONE=""
SOURCE_ROOT="$HOME/code"; HOST_ROOT="$HOME/code"; MIRROR_PATH=""
GIT_NAME=""; GIT_EMAIL=""; PROFILE="auto"
AGENTS=(antigravity); STACKS=(node); NODE_VERSION="22"; JAVA_VERSION="21"; TOOLS=(gh)
INSTALL_PLAYWRIGHT="auto"; DOCKER_IMAGES=()
REPOS=(); WORKTREES=(); PUBLIC_REPOS=(); PROTECTED_BRANCHES=(main master dev develop prod production)
EXTRAS=(); HOME_EXTRAS=(); DEP_COMMANDS=(); SMOKE_TESTS=()
VIBE_OUT="$HOME/vibecode-out"; PASS_FILE="$HOME/.vibecode-pass"

# ── config lookup: $VIBE_CONF, then config/hub.conf, then the copy pack.sh left next to the bundle ──
VA_CONF=""
for _c in "${VIBE_CONF:-}" "$VA_HOME/config/hub.conf" "${VIBE_OUT}/hub.conf"; do
  if [ -n "$_c" ] && [ -f "$_c" ]; then VA_CONF="$_c"; break; fi
done
[ -n "$VA_CONF" ] || die "no config found. Run: cp config/hub.example.conf config/hub.conf  (then edit it, or let your AI fill it in with PROMPT.md)"
# shellcheck disable=SC1090
source "$VA_CONF"

# ── profile ──────────────────────────────────────────────────────────────────
va_ram_mb() {
  if [ -r /proc/meminfo ]; then awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo
  elif have sysctl && sysctl -n hw.memsize >/dev/null 2>&1; then echo $(( $(sysctl -n hw.memsize) / 1048576 ))
  else echo 8192; fi
}
VA_PROFILE="$PROFILE"
if [ "$VA_PROFILE" = auto ]; then
  _ram="$(va_ram_mb)"
  if   [ "$_ram" -lt 5500 ];  then VA_PROFILE=small
  elif [ "$_ram" -lt 14000 ]; then VA_PROFILE=medium
  else VA_PROFILE=large; fi
fi
[ -f "$VA_HOME/profiles/$VA_PROFILE.conf" ] || die "unknown PROFILE '$VA_PROFILE' (use auto, small, medium or large)"
# shellcheck disable=SC1090
source "$VA_HOME/profiles/$VA_PROFILE.conf"
case "$INSTALL_PLAYWRIGHT" in auto) WANT_PLAYWRIGHT="$PLAYWRIGHT_DEFAULT" ;; 1|yes|true) WANT_PLAYWRIGHT=1 ;; *) WANT_PLAYWRIGHT=0 ;; esac

# ── list helpers ─────────────────────────────────────────────────────────────
# Entries look like "a|b|c". f1/f2/f3 print one field (missing field = empty).
f1() { printf '%s' "${1%%|*}"; }
f2() { local r="${1#*|}"; [ "$r" = "$1" ] && return 0; printf '%s' "${r%%|*}"; }
f3() { local r="${1#*|}"; [ "$r" = "$1" ] && return 0; r="${r#*|}"; case "$1" in *\|*\|*) printf '%s' "$r" ;; esac; }
in_list() { local x="$1"; shift; local i; for i in "$@"; do [ "$i" = "$x" ] && return 0; done; return 1; }
wants_agent() { in_list "$1" ${AGENTS[@]+"${AGENTS[@]}"}; }
wants_stack() { in_list "$1" ${STACKS[@]+"${STACKS[@]}"}; }
wants_tool()  { in_list "$1" ${TOOLS[@]+"${TOOLS[@]}"}; }
is_protected() { in_list "$1" ${PROTECTED_BRANCHES[@]+"${PROTECTED_BRANCHES[@]}"}; }
lookup() { # lookup <path> <array entries...> → prints field 2 of the entry whose field 1 = path
  local p="$1"; shift; local e
  for e in "$@"; do [ "$(f1 "$e")" = "$p" ] && { f2 "$e"; return 0; }; done; return 1
}

# Every repo + worktree path, one per line.
all_paths() {
  local e
  for e in ${REPOS[@]+"${REPOS[@]}"}; do f1 "$e"; echo; done
  for e in ${WORKTREES[@]+"${WORKTREES[@]}"}; do f1 "$e"; echo; done
}

# Percent of / in use (robust to an empty filesystem-name column).
disk_pct() { df -P / | awk 'NR==2 {for (i=1;i<=NF;i++) if ($i ~ /^[0-9]+%$/) {sub("%","",$i); print $i; exit}}'; }

# Never pack login tokens, whatever the config says.
is_secret_login_file() {
  case "$(basename "$1")" in
    auth.json|.credentials.json|credentials.json|oauth*|*token*|*.pem|id_rsa*|id_ed25519*|hosts.yml) return 0 ;;
  esac
  return 1
}

PRIMARY_AGENT="${AGENTS[0]:-antigravity}"
