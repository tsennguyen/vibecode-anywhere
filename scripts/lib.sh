# shellcheck shell=bash
# vibecode-anywhere — shared helpers, sourced by every script.
# Runs on Linux, macOS (bash 3.2) and Windows (Git Bash / MSYS2): no associative arrays, no mapfile.
# (c) 2026 Nguyễn Việt Thành — MIT License. https://github.com/tsennguyen/vibecode-anywhere

VA_VERSION="2.1.0"
VA_HOME="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PATH="$HOME/.local/bin:$PATH"
# Never let git block waiting for a terminal prompt on a headless host.
export GIT_TERMINAL_PROMPT=0
export GCM_INTERACTIVE=never

case "$(uname -s)" in
  Linux)
    VA_OS=linux
    [ -z "${XDG_RUNTIME_DIR:-}" ] && [ -d "/run/user/$(id -u)" ] && export XDG_RUNTIME_DIR="/run/user/$(id -u)" ;;
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
WINDOWS_BLOCK_AUTO_REBOOT=1; WINDOWS_SSH_SHELL="bash"
REPOS=(); WORKTREES=(); PUBLIC_REPOS=(); PROTECTED_BRANCHES=(main master dev develop prod production)
EXTRAS=(); HOME_EXTRAS=(); DEP_COMMANDS=(); SMOKE_TESTS=()
VIBE_OUT="$HOME/vibecode-out"; PASS_FILE="$HOME/.vibecode-pass"

# ── safe config parser (no eval: hub.conf next to the bundle is unencrypted) ─
_expand_home() {
  local v="$1"
  v="${v//\$\{HOME\}/$HOME}"
  v="${v//\$HOME/$HOME}"
  printf '%s' "$v"
}
_set_scalar() {
  local k="$1" v; v="$(_expand_home "$2")"
  case "$k" in
    OWNER_NAME) OWNER_NAME="$v" ;;           REPLY_LANGUAGE) REPLY_LANGUAGE="$v" ;;
    HOST_NAME) HOST_NAME="$v" ;;             TIMEZONE) TIMEZONE="$v" ;;
    HOST_KIND) HOST_KIND="$v" ;;             HOST_SHARED) HOST_SHARED="$v" ;;
    SSH_SERVER) SSH_SERVER="$v" ;;           SOURCE_ROOT) SOURCE_ROOT="$v" ;;
    HOST_ROOT) HOST_ROOT="$v" ;;             MIRROR_PATH) MIRROR_PATH="$v" ;;
    GIT_NAME) GIT_NAME="$v" ;;               GIT_EMAIL) GIT_EMAIL="$v" ;;
    PROFILE) PROFILE="$v" ;;                 NODE_VERSION) NODE_VERSION="$v" ;;
    JAVA_VERSION) JAVA_VERSION="$v" ;;       DOCKER_ON_MAC) DOCKER_ON_MAC="$v" ;;
    INSTALL_PLAYWRIGHT) INSTALL_PLAYWRIGHT="$v" ;;
    WINDOWS_BLOCK_AUTO_REBOOT) WINDOWS_BLOCK_AUTO_REBOOT="$v" ;;
    WINDOWS_SSH_SHELL) WINDOWS_SSH_SHELL="$v" ;;
    VIBE_OUT) VIBE_OUT="$v" ;;               PASS_FILE) PASS_FILE="$v" ;;
    *) die "unknown setting '$k' in $VA_CONF" ;;
  esac
}
_clear_array() {
  case "$1" in
    AGENTS) AGENTS=() ;;                     STACKS) STACKS=() ;;
    TOOLS) TOOLS=() ;;                       DOCKER_IMAGES) DOCKER_IMAGES=() ;;
    REPOS) REPOS=() ;;                       WORKTREES) WORKTREES=() ;;
    PUBLIC_REPOS) PUBLIC_REPOS=() ;;         PROTECTED_BRANCHES) PROTECTED_BRANCHES=() ;;
    EXTRAS) EXTRAS=() ;;                     HOME_EXTRAS) HOME_EXTRAS=() ;;
    DEP_COMMANDS) DEP_COMMANDS=() ;;         SMOKE_TESTS) SMOKE_TESTS=() ;;
    *) die "unknown list '$1' in $VA_CONF" ;;
  esac
}
_append_array() {
  local k="$1" v; v="$(_expand_home "$2")"
  case "$k" in
    AGENTS) AGENTS+=("$v") ;;                STACKS) STACKS+=("$v") ;;
    TOOLS) TOOLS+=("$v") ;;                  DOCKER_IMAGES) DOCKER_IMAGES+=("$v") ;;
    REPOS) REPOS+=("$v") ;;                  WORKTREES) WORKTREES+=("$v") ;;
    PUBLIC_REPOS) PUBLIC_REPOS+=("$v") ;;    PROTECTED_BRANCHES) PROTECTED_BRANCHES+=("$v") ;;
    EXTRAS) EXTRAS+=("$v") ;;                HOME_EXTRAS) HOME_EXTRAS+=("$v") ;;
    DEP_COMMANDS) DEP_COMMANDS+=("$v") ;;    SMOKE_TESTS) SMOKE_TESTS+=("$v") ;;
    *) die "unknown list '$k' in $VA_CONF" ;;
  esac
}
load_conf() {
  local file="$1" op k v
  while IFS=$'\t' read -r op k v; do
    [ -n "$op" ] || continue
    case "$op" in
      S) _set_scalar "$k" "$v" ;;
      A) _clear_array "$k" ;;
      I) _append_array "$k" "$v" ;;
      E) die "error in $file (line $k): $v" ;;
    esac
  done <<EOF
$(awk '
BEGIN { state = "top"; arr = "" }
NR == 1 { sub(/^\xef\xbb\xbf/, "") }
{
  sub(/\r$/, "")
  line = $0; i = 1; n = length(line)
  while (i <= n) {
    c = substr(line, i, 1)
    if (c ~ /[ \t]/ || (state == "top" && c == ";")) { i++; continue }
    if (c == "#") break
    if (state == "top") {
      rest = substr(line, i)
      if (match(rest, /^[A-Za-z_][A-Za-z0-9_]*(\+=|=)/)) {
        tok = substr(rest, 1, RLENGTH); i += RLENGTH
        plus = ( substr(tok, length(tok)-1, 2) == "+=" )
        key = substr(tok, 1, length(tok) - (plus ? 2 : 1))
        while (i <= n && substr(line, i, 1) ~ /[ \t]/) i++
        if (substr(line, i, 1) == "(") {
          i++; state = "arr"; arr = key
          if (!plus) printf "A\t%s\t\n", arr
          continue
        }
        if (plus) { printf "E\t%d\t+= requires parentheses\n", NR; exit }
        val = ""; ok = parse_val()
        if (!ok) exit
        printf "S\t%s\t%s\n", key, val
      } else {
        printf "E\t%d\tunexpected syntax\n", NR; exit
      }
    } else if (state == "arr") {
      if (c == ")") { i++; state = "top"; arr = ""; continue }
      val = ""; ok = parse_val()
      if (!ok) exit
      printf "I\t%s\t%s\n", arr, val
    }
  }
}
END { if (state == "arr") printf "E\t%d\tunclosed array %s\n", NR, arr }
function parse_val(    q, ch, nxt) {
  if (i > n) { val = ""; return 1 }
  q = substr(line, i, 1)
  if (q == "\"" || q == "\x27") {
    i++
    while (i <= n) {
      ch = substr(line, i, 1)
      if (q == "\"" && ch == "\\" && i < n) {
        nxt = substr(line, i+1, 1)
        if (nxt == "\"" || nxt == "\\" || nxt == "$") { val = val nxt; i += 2; continue }
      }
      if (ch == q) { i++; break }
      if (q == "\"" && (ch == "`" || substr(line, i, 2) == "$(")) {
        printf "E\t%d\tcommand substitution is not allowed in hub.conf\n", NR; return 0
      }
      val = val ch; i++
    }
    if (ch != q) { printf "E\t%d\tunclosed quote\n", NR; return 0 }
    return 1
  }
  while (i <= n) {
    ch = substr(line, i, 1)
    if (ch ~ /[ \t;#)]/) break
    if (ch == "`" || substr(line, i, 2) == "$(" || ch == "|" || ch == "&" || ch == ">" || ch == "<") {
      printf "E\t%d\tunsafe unquoted character in hub.conf\n", NR; return 0
    }
    val = val ch; i++
  }
  return 1
}
' "$file")
EOF
}

# ── config lookup: $VIBE_CONF, then config/hub.conf, then the copy pack.sh left next to the bundle ──
VA_CONF=""
for _c in "${VIBE_CONF:-}" "$VA_HOME/config/hub.conf" "${VIBE_OUT}/hub.conf"; do
  if [ -n "$_c" ] && [ -f "$_c" ]; then VA_CONF="$_c"; break; fi
done
[ -n "$VA_CONF" ] || die "no config found. Run: cp config/hub.example.conf config/hub.conf  (then edit it, or let your AI fill it in with PROMPT.md)"
load_conf "$VA_CONF"
case "$HOST_NAME" in ''|*[!A-Za-z0-9._-]*) die "invalid HOST_NAME '$HOST_NAME' in $VA_CONF (use letters, digits, . _ -)" ;; esac
case "$NODE_VERSION" in ''|*[!0-9]*) die "invalid NODE_VERSION '$NODE_VERSION' in $VA_CONF (digits only)" ;; esac
case "$JAVA_VERSION" in ''|*[!0-9]*) die "invalid JAVA_VERSION '$JAVA_VERSION' in $VA_CONF (digits only)" ;; esac

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
case "$VA_PROFILE" in ''|*/*|*..*) die "invalid PROFILE '$VA_PROFILE'" ;; esac
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

# ── git & concurrency helpers ────────────────────────────────────────────────
# Portable absolute --git-common-dir (works on git < 2.31 where --path-format=absolute is missing).
git_common_dir() {
  local repo="${1:-.}" d
  d="$(git -C "$repo" rev-parse --git-common-dir)" || return 1
  ( cd "$repo" && cd "$d" && pwd -P )
}
VA_LOCK="$HOME/.vibecode.lock"
acquire_lock() {
  local holder=""
  if ! mkdir "$VA_LOCK" 2>/dev/null; then
    [ -f "$VA_LOCK/pid" ] && holder="$(cat "$VA_LOCK/pid" 2>/dev/null || true)"
    if [ -n "$holder" ] && kill -0 "$holder" 2>/dev/null; then
      die "another vibecode script (PID $holder) is currently running; wait for it or remove $VA_LOCK"
    fi
    rm -rf "$VA_LOCK"
    mkdir "$VA_LOCK" 2>/dev/null || die "could not acquire lock $VA_LOCK"
  fi
  printf '%s\n' "$$" > "$VA_LOCK/pid"
}
release_lock() { rm -rf "$VA_LOCK" 2>/dev/null || true; }

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

# Files that must never be committed by our scripts.
is_secret_path() {
  case "$(basename "$1")" in
    .env.example|.env.sample|.env.template|.env.dist|.env.defaults) return 1 ;;
    .env|.env.*|.envrc|.dev.vars|*.pem|*.key|*.p12|*.pfx|*.jks|*.keystore|*.kdbx|*.tfvars|*.tfstate|*.tfstate.*|\
    id_rsa*|id_ed25519*|id_ecdsa*|credentials.json|.credentials.json|.git-credentials|auth.json|\
    service-account*.json|firebase-adminsdk*.json|*secret*.json|*secrets*.json|kubeconfig|\
    .npmrc|.pypirc|.netrc|.vibecode-pass|hosts.yml) return 0 ;;
  esac
  return 1
}
# AI/agent files that must not land in PUBLIC repos.
is_ai_path() {
  case "$1" in
    AGENTS.md|CLAUDE.md|GEMINI.md|AGENTS.override.md|CLAUDE.local.md|.cursorrules|.windsurfrules|.github/copilot-instructions.md|\
    */AGENTS.md|*/CLAUDE.md|*/GEMINI.md|*/AGENTS.override.md|*/CLAUDE.local.md|*/.cursorrules|*/.windsurfrules) return 0 ;;
    .agents/*|*/.agents/*|.claude/*|*/.claude/*|.codex/*|*/.codex/*|.gemini/*|*/.gemini/*|\
    .cursor/*|*/.cursor/*|.windsurf/*|*/.windsurf/*|ai-workspace/*|*/ai-workspace/*|_bmad*|*/_bmad*) return 0 ;;
  esac
  return 1
}
# True if $1 is in PUBLIC_REPOS, or is a worktree whose parent repo is in PUBLIC_REPOS.
is_public_repo() {
  in_list "$1" ${PUBLIC_REPOS[@]+"${PUBLIC_REPOS[@]}"} && return 0
  local parent
  if parent="$(lookup "$1" ${WORKTREES[@]+"${WORKTREES[@]}"})"; then
    in_list "$parent" ${PUBLIC_REPOS[@]+"${PUBLIC_REPOS[@]}"} && return 0
  fi
  return 1
}
# Is "repo/path" listed in EXTRAS (or inside a listed folder)?
is_extra_path() {
  local x="$1" e
  for e in ${EXTRAS[@]+"${EXTRAS[@]}"}; do
    case "$x" in "$e"|"$e"/*) return 0 ;; esac
  done
  return 1
}

# Never pack login tokens or SSH/TLS/cloud keys from $HOME, whatever the config says.
is_secret_login_file() {
  case "${1%/}" in
    .ssh|.ssh/*|*/.ssh|.gnupg|.gnupg/*|*/.gnupg|.aws|.aws/*|*/.aws|.kube|.kube/*|*/.kube|.config/gh|.config/gh/*|*/.config/gh) return 0 ;;
  esac
  case "$(basename "${1%/}")" in
    auth.json|.credentials.json|credentials.json|.git-credentials|oauth*|*oauth*|*auth_token*|*access_token*|*refresh_token*|\
    *.pem|*.key|*.p12|*.pfx|id_rsa*|id_ed25519*|id_ecdsa*|hosts.yml|authorized_keys) return 0 ;;
  esac
  return 1
}

PRIMARY_AGENT="${AGENTS[0]:-antigravity}"
