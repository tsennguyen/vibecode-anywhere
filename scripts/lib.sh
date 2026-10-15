# shellcheck shell=bash
# vibecode-anywhere — shared helpers, sourced by every script.
# Runs on Linux, macOS (bash 3.2) and Windows (Git Bash / MSYS2): no associative arrays, no mapfile.
# (c) 2026 Nguyễn Việt Thành — MIT License. https://github.com/tsennguyen/vibecode-anywhere

VA_VERSION="2.0.1"
VA_HOME="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PATH="$HOME/.local/bin:$PATH"

case "$(uname -s)" in
  Linux)                VA_OS=linux ;;
  Darwin)               VA_OS=macos ;;
  MINGW*|MSYS*|CYGWIN*) VA_OS=windows
    _lad="$(cygpath -u "${LOCALAPPDATA:-}" 2>/dev/null)"; [ -n "$_lad" ] || _lad="$HOME/AppData/Local"
    _apd="$(cygpath -u "${APPDATA:-}" 2>/dev/null)";     [ -n "$_apd" ] || _apd="$HOME/AppData/Roaming"
    export PATH="$PATH:$_lad/agy/bin:$_apd/npm" ;;
  *)                    VA_OS=other ;;
esac
VA_WSL=0; [ "$VA_OS" = linux ] && grep -qi microsoft /proc/version 2>/dev/null && VA_WSL=1
[ "$VA_OS" = macos ] && [ -x /opt/homebrew/bin/brew ] && export PATH="/opt/homebrew/bin:$PATH"

step() { printf '\n\033[1;36m== %s\033[0m\n' "$*"; }
ok()   { printf '  \033[32mOK  \033[0m %s\n' "$*"; }
warn() { printf '  \033[33mWARN\033[0m %s\n' "$*"; }
bad()  { printf '  \033[31mFAIL\033[0m %s\n' "$*"; }
die()  { printf '\033[31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }
# Path as the host's native tools see it: C:\Users\me\code on Windows, unchanged elsewhere.
native_path() { if [ "$VA_OS" = windows ] && have cygpath; then cygpath -w "$1"; else printf '%s' "$1"; fi; }
# Run a PowerShell command (Windows only).
ps1()  { powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$*" | tr -d '\r'; }

# ── defaults (config overrides) ──────────────────────────────────────────────
OWNER_NAME="the owner"; REPLY_LANGUAGE="English"; HOST_NAME="vibecode-host"; TIMEZONE=""
HOST_KIND="vps"; HOST_SHARED=0; SSH_SERVER="auto"
SOURCE_ROOT="$HOME/code"; HOST_ROOT="$HOME/code"; MIRROR_PATH=""
GIT_NAME=""; GIT_EMAIL=""; PROFILE="auto"
AGENTS=(antigravity); STACKS=(node); NODE_VERSION="22"; JAVA_VERSION="21"; TOOLS=(gh)
DOCKER_ON_MAC="colima"
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
# Tolerate configs saved by Windows editors (CRLF line endings, UTF-8 BOM).
_conf_txt="$(tr -d '\r' < "$VA_CONF")"; _conf_txt="${_conf_txt#$'\xef\xbb\xbf'}"
eval "$_conf_txt" || die "error in $VA_CONF (it is bash: KEY=\"value\", lists like REPOS=( \"a|b|c\" ))"
unset _conf_txt

# ── system facts (portable) ──────────────────────────────────────────────────
_n() { local v; v="$(cat)"; case "$v" in ''|*[!0-9]*) echo "$1" ;; *) echo "$v" ;; esac; }   # stdin → number or default
meminfo() { awk -v k="$1" '$1==k":" {print int($2/1024); exit}' /proc/meminfo 2>/dev/null; }
va_ram_mb() { _va_ram_mb 2>/dev/null | _n 8192; }
va_mem_avail_mb() { _va_mem_avail_mb 2>/dev/null | _n 0; }
va_swap_mb() { _va_swap_mb 2>/dev/null | _n 0; }
_va_ram_mb() {
  case "$VA_OS" in
    macos) echo $(( $(sysctl -n hw.memsize) / 1048576 )) ;;
    *)     local m; m="$(meminfo MemTotal)"; echo "${m:-8192}" ;;
  esac
}
_va_mem_avail_mb() {
  case "$VA_OS" in
    macos) vm_stat | awk -v ps="$(sysctl -n hw.pagesize)" '/Pages free|Pages inactive|Pages speculative/ {gsub("\\.","",$NF); s+=$NF} END {print int(s*ps/1048576)}' ;;
    *)     local m; m="$(meminfo MemAvailable)"; [ -n "$m" ] || m="$(meminfo MemFree)"; echo "${m:-0}" ;;
  esac
}
_va_swap_mb() {
  case "$VA_OS" in
    macos) sysctl -n vm.swapusage | awk '{gsub("M","",$3); print int($3)}' ;;
    *)     local m; m="$(meminfo SwapTotal)"; echo "${m:-0}" ;;
  esac
}
va_cpus() {
  case "$VA_OS" in
    macos)   sysctl -n hw.ncpu ;;
    windows) echo "${NUMBER_OF_PROCESSORS:-?}" ;;
    *)       nproc 2>/dev/null || echo "?" ;;
  esac
}
va_load() {
  case "$VA_OS" in
    macos) sysctl -n vm.loadavg | tr -d '{}' | awk '{print $1, $2, $3}' ;;
    *)     cut -d' ' -f1-3 /proc/loadavg 2>/dev/null || echo "n/a" ;;
  esac
}
# Percent used on the disk that holds HOST_ROOT (robust to an empty filesystem-name column).
disk_pct() {
  local d="$HOST_ROOT"; [ -d "$d" ] || d="$HOME"
  df -P "$d" | awk 'NR==2 {for (i=1;i<=NF;i++) if ($i ~ /^[0-9]+%$/) {sub("%","",$i); print $i; exit}}'
}
va_top_procs() {
  case "$VA_OS" in
    linux)   ps -eo rss,comm --sort=-rss | awk 'NR>1 && NR<=6 {printf "       %5d MB  %s\n", $1/1024, $2}' ;;
    macos)   ps -Ao rss,comm | sort -nr | head -5 | awk '{n=split($2,a,"/"); printf "       %5d MB  %s\n", $1/1024, a[n]}' ;;
    windows) ps1 "Get-Process | Sort-Object WS -Descending | Select-Object -First 5 | ForEach-Object { '       {0,5} MB  {1}' -f [int](\$_.WS/1MB), \$_.ProcessName }" ;;
  esac
}
# Is a process whose command line contains $1 running?
proc_running() {
  case "$VA_OS" in
    windows) [ -n "$(ps1 "Get-CimInstance Win32_Process | Where-Object { \$_.CommandLine -like '*$1*' -and \$_.Name -ne 'powershell.exe' } | Select-Object -First 1 -ExpandProperty ProcessId")" ] ;;
    *)       pgrep -f "$1" >/dev/null 2>&1 ;;
  esac
}
va_os_label() {
  case "$VA_OS" in
    linux)   ( . /etc/os-release 2>/dev/null && printf '%s' "$PRETTY_NAME" ) || echo Linux; [ "$VA_WSL" = 1 ] && printf ' (WSL2)' ;;
    macos)   echo "macOS $(sw_vers -productVersion 2>/dev/null)" ;;
    windows) ps1 "(Get-CimInstance Win32_OperatingSystem).Caption" 2>/dev/null || echo Windows ;;
    *)       uname -s ;;
  esac
  return 0
}

# ── profile ──────────────────────────────────────────────────────────────────
VA_PROFILE="$PROFILE"
if [ "$VA_PROFILE" = auto ]; then
  _ram="$(va_ram_mb)"
  if   [ "$_ram" -lt 5500 ];  then VA_PROFILE=small
  elif [ "$_ram" -lt 14000 ]; then VA_PROFILE=medium
  else VA_PROFILE=large; fi
fi
[ -f "$VA_HOME/profiles/$VA_PROFILE.conf" ] || die "unknown PROFILE '$VA_PROFILE' (use auto, small, medium, large or a file in profiles/)"
# shellcheck disable=SC1090
source "$VA_HOME/profiles/$VA_PROFILE.conf"
case "$INSTALL_PLAYWRIGHT" in auto) WANT_PLAYWRIGHT="$PLAYWRIGHT_DEFAULT" ;; 1|yes|true) WANT_PLAYWRIGHT=1 ;; *) WANT_PLAYWRIGHT=0 ;; esac

case "$HOST_KIND" in
  vps)         HOST_KIND_LABEL="rented VPS (datacenter)" ;;
  workstation) HOST_KIND_LABEL="workstation / desktop PC at home or office" ;;
  minipc)      HOST_KIND_LABEL="mini PC (always on)" ;;
  laptop)      HOST_KIND_LABEL="laptop kept plugged in (lid may be closed)" ;;
  mac)         HOST_KIND_LABEL="Mac (mini / Studio / laptop) kept on" ;;
  sbc)         HOST_KIND_LABEL="single-board computer (Raspberry Pi class)" ;;
  *)           HOST_KIND_LABEL="$HOST_KIND" ;;
esac
# An SSH server is how you rescue the host from the phone. VPSes ship one; home machines usually don't.
case "$SSH_SERVER" in auto) [ "$HOST_KIND" = vps ] && WANT_SSH=0 || WANT_SSH=1 ;; 1|yes|true) WANT_SSH=1 ;; *) WANT_SSH=0 ;; esac

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

# Files that must never be committed by our scripts (checked on NEW files only).
is_secret_path() {
  case "$(basename "$1")" in
    .env.example|.env.sample|.env.template|.env.dist|.env.defaults) return 1 ;;
    .env|.env.*|*.pem|*.key|*.p12|*.pfx|*.jks|*.keystore|*.kdbx|id_rsa*|id_ed25519*|id_ecdsa*|\
    credentials.json|.credentials.json|auth.json|service-account*.json|*secret*.json|.npmrc|.pypirc|.netrc|.vibecode-pass) return 0 ;;
  esac
  return 1
}
# AI/agent files that must not land in PUBLIC repos.
is_ai_path() {
  case "$1" in
    AGENTS.md|CLAUDE.md|GEMINI.md|*/AGENTS.md|*/CLAUDE.md|*/GEMINI.md|AGENTS.override.md|CLAUDE.local.md) return 0 ;;
    .agents/*|.claude/*|.codex/*|.gemini/*|.cursor/*|.windsurf/*|ai-workspace/*|_bmad*|*/_bmad*) return 0 ;;
  esac
  return 1
}
is_public_repo() { in_list "$1" ${PUBLIC_REPOS[@]+"${PUBLIC_REPOS[@]}"}; }
# Is "repo/path" listed in EXTRAS (or inside a listed folder)?
is_extra_path() {
  local x="$1" e
  for e in ${EXTRAS[@]+"${EXTRAS[@]}"}; do
    case "$x" in "$e"|"$e"/*) return 0 ;; esac
  done
  return 1
}

# Never pack login tokens, whatever the config says.
is_secret_login_file() {
  case "$(basename "$1")" in
    auth.json|.credentials.json|credentials.json|oauth*|*token*|*.pem|id_rsa*|id_ed25519*|hosts.yml) return 0 ;;
  esac
  return 1
}

PRIMARY_AGENT="${AGENTS[0]:-antigravity}"
