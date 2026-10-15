#!/usr/bin/env bash
# vibecode-anywhere — macOS host bootstrap (called by ./bootstrap.sh). Runs ONCE on the HOST:
# a Mac mini / Mac Studio / MacBook that stays on. Apple Silicon or Intel, macOS 13+.
# Installs via Homebrew what config/hub.conf asks for, keeps the Mac awake and reachable, links the agent rules.
# Idempotent: re-run after any failure. You will be asked for your password (sudo) for power settings.
# (c) 2026 Nguyễn Việt Thành — MIT License.
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"
[ "$VA_OS" = macos ] || die "this script is for macOS"
FAILED=()
try() { local name="$1"; shift; if ( "$@" ); then :; else warn "$name failed (continuing)"; FAILED+=("$name"); fi; }
brew_has() { brew list --formula "$1" >/dev/null 2>&1 || brew list --cask "$1" >/dev/null 2>&1; }
binst() { local n="$1"; [ "$n" = --cask ] && n="$2"; n="${n##*/}"; brew_has "$n" || try "$n" brew install "$@"; }

echo "Config:  $VA_CONF"
echo "Host:    $HOST_KIND_LABEL — $(va_os_label), $(va_cpus) CPU, $(( $(va_ram_mb) / 1024 )) GB RAM"
echo "Profile: $PROFILE_LABEL   Agents: ${AGENTS[*]-}   Stacks: ${STACKS[*]-}   Tools: ${TOOLS[*]-}"

step "Xcode Command Line Tools"
if ! xcode-select -p >/dev/null 2>&1; then
  xcode-select --install || true
  die "a dialog opened to install the Command Line Tools. Finish it, then re-run ./bootstrap.sh"
fi

step "Homebrew"
if ! have brew; then
  NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi
eval "$(/opt/homebrew/bin/brew shellenv 2>/dev/null || /usr/local/bin/brew shellenv)"
for rc in "$HOME/.zprofile" "$HOME/.bash_profile"; do
  grep -q 'brew shellenv' "$rc" 2>/dev/null || echo "eval \"\$($(command -v brew) shellenv)\"" >> "$rc"
done
brew update -q || true
binst git; binst tmux; binst jq; binst ripgrep

step "Repos folder + optional mirror path"
mkdir -p "$HOST_ROOT" "$HOME/.local/bin"; echo "  $HOST_ROOT"
if [ -n "$MIRROR_PATH" ] && [ "$MIRROR_PATH" != "$HOST_ROOT" ]; then
  if [ -e "$MIRROR_PATH" ]; then echo "  $MIRROR_PATH already exists, left as is"
  else sudo mkdir -p "$(dirname "$MIRROR_PATH")" && sudo ln -s "$HOST_ROOT" "$MIRROR_PATH" && ls -ld "$MIRROR_PATH"; fi
fi

step "Stay awake, restart after power loss, allow SSH"
# sleep 0 = never sleep; autorestart = boot again after a power cut; womp = wake on network.
sudo pmset -a sleep 0 disksleep 0 displaysleep 10 womp 1 autorestart 1 powernap 0 || warn "pmset failed"
[ "$HOST_KIND" = laptop ] && { sudo pmset -a lidwake 1 || true; echo "  MacBook: closed-lid only stays awake with power + external display (Apple limitation)."; }
sudo systemsetup -setrestartfreeze on >/dev/null 2>&1 || true
[ -n "$TIMEZONE" ] && { sudo systemsetup -settimezone "$TIMEZONE" >/dev/null 2>&1 || warn "cannot set timezone"; }
if [ "$WANT_SSH" = 1 ]; then
  sudo systemsetup -setremotelogin on >/dev/null 2>&1 \
    || warn "turn on SSH yourself: System Settings → General → Sharing → Remote Login (macOS needs Full Disk Access for Terminal to do it from here)"
fi
echo "  IMPORTANT: Antigravity's macOS daemon and the Claude/Codex sessions run inside your user session."
echo "  After a reboot the Mac must log in by itself: System Settings → Users & Groups → Automatically log in as…"
echo "  (not available while FileVault is on — trade-off explained in docs/HOSTS.md)."

# ── language stacks ──────────────────────────────────────────────────────────
need_node=0
{ wants_stack node || wants_stack pnpm || wants_agent codex || wants_tool vercel; } && need_node=1
if [ "$need_node" = 1 ]; then
  step "Node $NODE_VERSION"
  binst "node@$NODE_VERSION"
  brew link --overwrite --force "node@$NODE_VERSION" >/dev/null 2>&1 || true
  node -v || true
fi
if wants_stack pnpm; then step "pnpm"; have corepack || try corepack npm install -g corepack; corepack enable || true; try pnpm corepack prepare pnpm@latest --activate; fi
if wants_stack bun; then step "Bun"; binst oven-sh/bun/bun; fi
if wants_stack python-uv; then step "uv (Python)"; binst uv; fi
if wants_stack java; then
  step "JDK $JAVA_VERSION"
  binst "openjdk@$JAVA_VERSION"
  jdk="$(brew --prefix "openjdk@$JAVA_VERSION" 2>/dev/null)/libexec/openjdk.jdk"
  [ -d "$jdk" ] && [ ! -e "/Library/Java/JavaVirtualMachines/openjdk-$JAVA_VERSION.jdk" ] \
    && sudo ln -sfn "$jdk" "/Library/Java/JavaVirtualMachines/openjdk-$JAVA_VERSION.jdk"
fi
if wants_stack go; then step "Go"; binst go; fi
if wants_stack rust; then step "Rust (rustup)"; have cargo || try rust bash -c 'curl -fsSL https://sh.rustup.rs | sh -s -- -y'; fi
if wants_stack docker; then
  step "Docker ($DOCKER_ON_MAC)"
  if [ "$DOCKER_ON_MAC" = desktop ]; then
    binst --cask docker; echo "  Open Docker Desktop once and tick 'Start Docker Desktop when you sign in'."
  else
    # Colima = headless Docker engine, no GUI needed; starts at login via brew services.
    binst colima; binst docker; binst docker-compose
    mkdir -p "$HOME/.docker/cli-plugins"
    ln -sfn "$(brew --prefix)/opt/docker-compose/bin/docker-compose" "$HOME/.docker/cli-plugins/docker-compose" 2>/dev/null || true
    try "colima start" colima start --cpu "$(( $(va_cpus) / 2 ))" --memory "$(( $(va_ram_mb) / 4096 ))"
    brew services start colima >/dev/null 2>&1 || true
  fi
fi

# ── tools ────────────────────────────────────────────────────────────────────
wants_tool gh && binst gh
if wants_tool vercel; then step "Vercel CLI"; have vercel || try vercel npm install -g vercel; fi
wants_tool supabase && binst supabase/tap/supabase
if wants_tool tailscale; then step "Tailscale"; binst --cask tailscale; echo "  Open Tailscale once, sign in, and enable 'Launch at login'."; fi

# ── coding agents ────────────────────────────────────────────────────────────
if wants_agent antigravity; then
  step "Antigravity CLI (agy)"
  have agy || try antigravity bash -c 'curl -fsSL https://antigravity.google/cli/install.sh | bash'
  agy --version 2>/dev/null || true
fi
if wants_agent claude; then
  step "Claude Code (claude)"
  have claude || try claude bash -c 'curl -fsSL https://claude.ai/install.sh | bash'
  claude --version 2>/dev/null || true
fi
if wants_agent codex; then
  step "OpenAI Codex CLI + ChatGPT desktop app"
  have codex || binst codex
  # On a Mac the desktop app IS the official phone remote host for Codex.
  binst --cask chatgpt
  echo "  Open ChatGPT → Settings → Connections → 'Control this Mac or PC' → scan the QR with your phone."
fi

step "Shell defaults for the agent"
for rc in "$HOME/.zshrc" "$HOME/.bashrc"; do
  grep -q '# >>> vibecode-anywhere' "$rc" 2>/dev/null && continue
  cat >> "$rc" <<EOF
# >>> vibecode-anywhere
export PATH="\$HOME/.local/bin:\$PATH"
export NODE_OPTIONS="--max-old-space-size=$NODE_HEAP_MB"
# <<< vibecode-anywhere
EOF
done
if [ -n "$GIT_NAME" ] && [ -n "$GIT_EMAIL" ]; then
  git config --global user.name "$GIT_NAME"; git config --global user.email "$GIT_EMAIL"
fi
git config --global init.defaultBranch main
git config --global pull.ff only

"$VA_HOME/scripts/render-rules.sh"

echo
if [ "${#FAILED[@]}" -gt 0 ]; then warn "some steps failed: ${FAILED[*]} — fix the cause and re-run ./bootstrap.sh"; fi
cat <<EOF
========================================================================
 macOS bootstrap done. Open a NEW terminal, then:
   gh auth login --web --git-protocol https && gh auth setup-git
   ./sync.sh            (or ./sync.sh --clone-only)
   ./install-deps.sh
   ./remote.sh login && ./remote.sh start && ./doctor.sh
 Then turn on automatic login (System Settings → Users & Groups) so everything comes back after a reboot.
========================================================================
EOF
