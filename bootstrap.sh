#!/usr/bin/env bash
# vibecode-anywhere — bootstrap.sh  (runs ONCE on the HOST: Ubuntu 22.04+/Debian 12+, amd64 or arm64)
# Installs what config/hub.conf asks for: base tools, swap (by profile), language stacks, CLIs and coding
# agents; keeps the machine awake; links the agent rules. Idempotent: re-run after any failure.
# Run as root or as a user with sudo (you will type the sudo password if it asks).
# (c) 2026 Nguyễn Việt Thành — MIT License.
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/scripts/lib.sh"

[ "$(uname -s)" = Linux ] && have apt-get || die "bootstrap.sh targets Ubuntu/Debian hosts (apt). See docs/windows.md for other setups."
if [ "$(id -u)" -eq 0 ]; then sudo() { [ "${1:-}" = "-E" ] && shift; "$@"; }; fi
ME="$(id -un)"
ARCH="$(dpkg --print-architecture)"
FAILED=()
try() { local name="$1"; shift; if ( "$@" ); then :; else warn "$name failed (continuing)"; FAILED+=("$name"); fi; }

echo "Config:  $VA_CONF"
echo "Profile: $PROFILE_LABEL   Agents: ${AGENTS[*]-}   Stacks: ${STACKS[*]-}   Tools: ${TOOLS[*]-}"

mkdir -p "$HOME/.local/bin"
grep -q 'HOME/.local/bin' "$HOME/.bashrc" 2>/dev/null || echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"

step "Base packages"
sudo apt-get update -y
sudo apt-get install -y git curl wget ca-certificates gnupg unzip zip jq build-essential openssl \
  tmux htop ripgrep fd-find python3 python3-venv dbus-user-session

step "Swap ${SWAP_GB} GB (profile: $PROFILE_LABEL)"
if [ "$(free -m | awk '/Swap:/ {print $2}')" -lt 1000 ]; then
  if sudo fallocate -l "${SWAP_GB}G" /swapfile && sudo chmod 600 /swapfile && sudo mkswap /swapfile >/dev/null && sudo swapon /swapfile; then
    grep -q '^/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab >/dev/null
  else
    warn "swap not allowed on this machine type — continuing without it"
  fi
fi
free -h | sed -n 1,3p

step "Repos folder + optional mirror path"
mkdir -p "$HOST_ROOT"; echo "  $HOST_ROOT"
if [ -n "$MIRROR_PATH" ] && [ "$MIRROR_PATH" != "$HOST_ROOT" ]; then
  if [ -e "$MIRROR_PATH" ]; then echo "  $MIRROR_PATH already exists, left as is"
  else sudo mkdir -p "$(dirname "$MIRROR_PATH")" && sudo ln -s "$HOST_ROOT" "$MIRROR_PATH" && ls -ld "$MIRROR_PATH"; fi
fi

step "Stay awake + keep user services running without a login"
[ -n "$TIMEZONE" ] && { sudo timedatectl set-timezone "$TIMEZONE" 2>/dev/null || warn "cannot set timezone"; }
sudo systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target >/dev/null 2>&1 || true
sudo loginctl enable-linger "$ME" || warn "enable-linger failed — user daemons may stop when you log out"

# ── language stacks ──────────────────────────────────────────────────────────
need_node=0
{ wants_stack node || wants_stack pnpm || wants_agent codex || wants_tool vercel; } && need_node=1
if [ "$need_node" = 1 ]; then
  step "Node $NODE_VERSION"
  if ! node -v 2>/dev/null | grep -q "^v$NODE_VERSION"; then
    curl -fsSL "https://deb.nodesource.com/setup_${NODE_VERSION}.x" | sudo -E bash -
    sudo apt-get install -y nodejs
  fi
  node -v
fi
if wants_stack pnpm; then
  step "pnpm (corepack)"
  have corepack || sudo npm install -g corepack
  sudo corepack enable
  try "pnpm" corepack prepare pnpm@latest --activate
fi
if wants_stack bun; then step "Bun"; have bun || try "bun" bash -c 'curl -fsSL https://bun.sh/install | bash'; fi
if wants_stack python-uv; then step "uv (Python)"; have uv || curl -LsSf https://astral.sh/uv/install.sh | sh; uv --version || true; fi
if wants_stack java; then
  step "JDK $JAVA_VERSION"
  try "jdk" sudo apt-get install -y "openjdk-${JAVA_VERSION}-jdk-headless"
fi
if wants_stack go; then step "Go"; have go || try "go" sudo apt-get install -y golang-go; fi
if wants_stack rust; then step "Rust (rustup)"; have cargo || try "rust" bash -c 'curl -fsSL https://sh.rustup.rs | sh -s -- -y'; fi
if wants_stack docker; then
  step "Docker + Compose"
  have docker || try "docker" bash -c 'curl -fsSL https://get.docker.com | sudo sh'
  [ "$ME" = root ] || sudo usermod -aG docker "$ME" || true
  sudo docker run --rm hello-world >/dev/null 2>&1 && echo "  docker works" || warn "docker cannot run containers here (some VPS types block it)"
fi

# ── tools ────────────────────────────────────────────────────────────────────
if wants_tool gh && ! have gh; then
  step "GitHub CLI"
  sudo mkdir -p -m 755 /etc/apt/keyrings
  wget -qO- https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg >/dev/null
  sudo chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg
  echo "deb [arch=$ARCH signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
    | sudo tee /etc/apt/sources.list.d/github-cli.list >/dev/null
  sudo apt-get update -y && sudo apt-get install -y gh
fi
if wants_tool vercel; then step "Vercel CLI"; have vercel || try "vercel" sudo npm install -g vercel; fi
if wants_tool supabase && ! have supabase; then
  step "Supabase CLI"
  try "supabase" bash -c "curl -fsSL https://github.com/supabase/cli/releases/latest/download/supabase_linux_${ARCH}.tar.gz | tar -xz -C '$HOME/.local/bin' supabase"
fi
if wants_tool tailscale; then step "Tailscale"; have tailscale || try "tailscale" bash -c 'curl -fsSL https://tailscale.com/install.sh | sh'; fi

# ── coding agents ────────────────────────────────────────────────────────────
if wants_agent antigravity; then
  step "Antigravity CLI (agy)"
  have agy || try "antigravity" bash -c 'curl -fsSL https://antigravity.google/cli/install.sh | bash'
  agy --version 2>/dev/null || true
fi
if wants_agent claude; then
  step "Claude Code (claude)"
  have claude || try "claude" bash -c 'curl -fsSL https://claude.ai/install.sh | bash'
  claude --version 2>/dev/null || true
fi
if wants_agent codex; then
  step "OpenAI Codex CLI (codex)"
  have codex || try "codex" sudo npm install -g @openai/codex
  codex --version 2>/dev/null || true
fi

step "Shell defaults for the agent (Node heap for this profile)"
if ! grep -q '# >>> vibecode-anywhere' "$HOME/.bashrc"; then
  cat >> "$HOME/.bashrc" <<EOF
# >>> vibecode-anywhere
export NODE_OPTIONS="--max-old-space-size=$NODE_HEAP_MB"
# <<< vibecode-anywhere
EOF
fi
if [ -n "$GIT_NAME" ] && [ -n "$GIT_EMAIL" ]; then
  git config --global user.name "$GIT_NAME"; git config --global user.email "$GIT_EMAIL"
fi
git config --global init.defaultBranch main
git config --global pull.ff only

"$VA_HOME/scripts/render-rules.sh"

echo
if [ "${#FAILED[@]}" -gt 0 ]; then warn "some steps failed: ${FAILED[*]} — fix the network/cause and re-run ./bootstrap.sh"; fi
cat <<EOF
========================================================================
 Bootstrap done. Open a NEW ssh session once (PATH, docker group), then:
   gh auth login --web --git-protocol https && gh auth setup-git
   ./sync.sh            (or ./sync.sh --clone-only if you have no bundle)
   ./install-deps.sh
   ./remote.sh login    # sign in to each agent (prints links you open on your phone)
   ./remote.sh start    # start phone remote control for each agent
   ./doctor.sh
========================================================================
EOF
