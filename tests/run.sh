#!/usr/bin/env bash
# vibecode-anywhere — end-to-end tests. Safe: everything happens in a temp dir with a fake $HOME and
# local bare repos as "remotes"; nothing touches your real repos, config or network.
#   bash tests/run.sh            (Linux, macOS bash 3.2, Windows Git Bash)
# (c) 2026 Nguyễn Việt Thành — MIT License.
set -uo pipefail
KIT="$(cd "$(dirname "$0")/.." && pwd)"
T="$(mktemp -d 2>/dev/null || mktemp -d -t vibetest)"
trap 'rm -rf "$T"' EXIT
PASS=0; FAILS=0
pass() { PASS=$((PASS + 1)); printf '  \033[32mPASS\033[0m %s\n' "$*"; }
fail() { FAILS=$((FAILS + 1)); printf '  \033[31mFAIL\033[0m %s\n' "$*"; }
check() { local name="$1"; shift; if "$@"; then pass "$name"; else fail "$name"; fi; }
section() { printf '\n== %s\n' "$*"; }

# isolated environment
export HOME="$T/home"; mkdir -p "$HOME"
export GIT_CONFIG_NOSYSTEM=1
git config --global user.name "Test" ; git config --global user.email "test@example.com"
git config --global init.defaultBranch main; git config --global core.autocrlf false
unset VIBE_CONF VIBE_OUT
cp -R "$KIT" "$T/kit"; K="$T/kit"; rm -rf "$K/config/hub.conf" "$K/.rendered" "$K/.git"
ERRPAT='syntax error|unbound variable|command not found|bad substitution|integer expression expected'

mkrepo() { # mkrepo <name> → bare remote + source clone with one commit on main
  git init -q --bare "$T/remotes/$1.git"
  git clone -q "$T/remotes/$1.git" "$T/src/$1" 2>/dev/null
  ( cd "$T/src/$1" && echo "v1" > README && git add README && git commit -q -m init && git push -q origin HEAD:main )
}
mkdir -p "$T/remotes" "$T/src"
mkrepo app; mkrepo pub
( cd "$T/src/app"
  git checkout -q -b feat/x
  echo "local" > local.txt && git add local.txt && git commit -q -m "local only"
  echo "wip" >> README
  echo "new" > "untracked file.txt"
  printf 'API_KEY=s3cr3t\n' > .env.local
  printf '.env.local\nnode_modules/\n' > .gitignore
  mkdir -p node_modules/x && echo junk > node_modules/x/i.js )
mkdir -p "$HOME/.codex" "$HOME/.ssh"
echo 'model="x"' > "$HOME/.codex/config.toml"; echo '{"tok":1}' > "$HOME/.codex/auth.json"
echo "PRIVATE" > "$HOME/.ssh/id_ed25519"

cat > "$T/hub.conf" <<EOF
OWNER_NAME="Tester"; REPLY_LANGUAGE="English"; HOST_NAME="ci-host"; HOST_KIND="vps"
SOURCE_ROOT="$T/src"; HOST_ROOT="$T/host"
AGENTS=(antigravity claude codex); STACKS=(node); TOOLS=()
REPOS=("app|$T/remotes/app.git|App with spaces & symbols" "pub|$T/remotes/pub.git|Public demo")
PUBLIC_REPOS=(pub)
EXTRAS=("app/.env.local")
HOME_EXTRAS=(".codex" ".codex/auth.json" ".ssh")
VIBE_OUT="$HOME/vibecode-out"; PASS_FILE="$HOME/.vibecode-pass"
EOF

# ─────────────────────────────────────────────────────────────────────────────
section "pack"
out="$(VIBE_CONF="$T/hub.conf" "$K/pack.sh" 2>&1)"; rc=$?
check "pack exits 0" [ "$rc" -eq 0 ]
check "pack has no shell errors" sh -c "! printf '%s' \"\$1\" | grep -Eq '$ERRPAT'" _ "$out"
check "bundle written" [ -s "$HOME/vibecode-out/bundle.tar.gz.enc" ]
check "plaintext hub.conf next to bundle" [ -f "$HOME/vibecode-out/hub.conf" ]
check "login token skipped" sh -c "printf '%s' \"\$1\" | grep -q 'SKIP  .codex/auth.json'" _ "$out"
check ".ssh folder skipped" sh -c "printf '%s' \"\$1\" | grep -q 'SKIP  .ssh'" _ "$out"
check "passphrase file is private" sh -c '[ "$(uname -s | cut -c1-5)" = MINGW ] || [ -z "$(find "$1" -perm -044 2>/dev/null)" ]' _ "$HOME/.vibecode-pass"

section "pack refuses credentials in hub.conf"
sed "s|$T/remotes/app.git|https://user:ghp_abcdefghijklmnopqrstuvwxyz0123@github.com/x/app.git|" "$T/hub.conf" > "$T/bad.conf"
out="$(VIBE_CONF="$T/bad.conf" "$K/pack.sh" 2>&1)"; rc=$?
check "refused credential in hub.conf (non-zero exit)" [ "$rc" -ne 0 ]
check "token value not echoed" sh -c "! printf '%s' \"\$1\" | grep -q ghp_abcdef" _ "$out"

section "config parser rejects command substitution / RCE without executing it"
RCE_PROBE="$T/pwned"
cat > "$T/rce.conf" <<EOF
HOST_NAME="\$(touch $RCE_PROBE)"
EOF
out="$(VIBE_CONF="$T/rce.conf" "$K/scripts/print-config.sh" 2>&1)"; rc=$?
check "rejected \$() in hub.conf (non-zero exit)" [ "$rc" -ne 0 ]
check "payload was NOT executed" [ ! -e "$RCE_PROBE" ]

# ─────────────────────────────────────────────────────────────────────────────
section "sync on a fresh host (config only next to the bundle)"
export HOME="$T/host-home"; mkdir -p "$HOME"
git config --global user.name "Test"; git config --global user.email "test@example.com"; git config --global core.autocrlf false
cp -R "$T/home/vibecode-out" "$HOME/"; cp "$T/home/.vibecode-pass" "$HOME/"
mkdir -p "$HOME/.codex"; echo 'model="host-own"' > "$HOME/.codex/config.toml"
out="$("$K/sync.sh" 2>&1)"; rc=$?
check "sync exits 0" [ "$rc" -eq 0 ]
check "sync has no shell errors" sh -c "! printf '%s' \"\$1\" | grep -Eq '$ERRPAT'" _ "$out"
check "config taken from the encrypted bundle" [ -f "$K/config/hub.conf" ]
A="$T/host/app"
check "branch restored" [ "$(git -C "$A" branch --show-current)" = "feat/x" ]
check "local-only commit restored" sh -c 'git -C "$1" log --oneline | grep -q "local only"' _ "$A"
check "uncommitted change restored" grep -q wip "$A/README"
check "untracked file (with space) restored" [ -f "$A/untracked file.txt" ]
check "node_modules not carried" [ ! -e "$A/node_modules" ]
check "secret extra restored" grep -q s3cr3t "$A/.env.local"
check "agent config restored from .codex dir" grep -q 'model="x"' "$HOME/.codex/config.toml"
check "overwritten agent config backed up" sh -c 'grep -rq host-own "$1"/.vibecode-backup' _ "$HOME"
check "login token inside .codex dir NOT restored" [ ! -e "$HOME/.codex/auth.json" ]
check "SSH key NOT restored" [ ! -e "$HOME/.ssh/id_ed25519" ]
check "rules rendered" [ -s "$K/.rendered/AGENTS.md" ]
check "no unreplaced {{placeholders}}" sh -c '! grep -q "{{" "$1"' _ "$K/.rendered/AGENTS.md"
check "no bash 3.2 stray quotes around values" sh -c 'grep -q "^# AGENTS.md — \`ci-host\`" "$1"' _ "$K/.rendered/AGENTS.md"
check "rules placed for claude" [ -e "$HOME/.claude/CLAUDE.md" ]
check "rules placed for codex" [ -e "$HOME/.codex/AGENTS.md" ]
check "rules placed for antigravity" [ -e "$HOME/.gemini/GEMINI.md" ]

section "re-sync is safe"
echo "host edit" >> "$A/README"
out="$("$K/sync.sh" 2>&1)"; rc=$?
check "re-sync exits 0" [ "$rc" -eq 0 ]
check "host edit kept in git stash" sh -c 'git -C "$1" stash list | grep -q vibecode-sync' _ "$A"

# ─────────────────────────────────────────────────────────────────────────────
section "save-all never commits secrets, renamed secrets, or nested AI files in public repos"
P="$T/host/pub"
echo "EXAMPLE=1" > "$P/.env.example"
git -C "$P" checkout -q -b feat/p
git -C "$P" add .env.example && git -C "$P" commit -q -m "add example"
git -C "$P" mv .env.example .env
echo "TOKEN=abc" >> "$P/.env"
echo "# ai" > "$P/AGENTS.md"
mkdir -p "$P/.claude" "$P/apps/web/.claude"
echo x > "$P/.claude/s.json"; echo y > "$P/apps/web/.claude/nested.json"
echo code > "$P/app.js"
out="$("$K/save-all.sh" 2>&1)"; rc=$?
check "save-all exits 0" [ "$rc" -eq 0 ]
pushed="$(git -C "$T/remotes/pub.git" ls-tree -r --name-only feat/p 2>/dev/null)"
check "code pushed" sh -c 'printf "%s\n" "$1" | grep -qx app.js' _ "$pushed"
check "renamed .env NOT pushed" sh -c '! printf "%s\n" "$1" | grep -qx .env' _ "$pushed"
check "AGENTS.md NOT pushed (public repo)" sh -c '! printf "%s\n" "$1" | grep -qx AGENTS.md' _ "$pushed"
check ".claude/ NOT pushed (public repo)" sh -c '! printf "%s\n" "$1" | grep -q "^.claude/"' _ "$pushed"
check "nested apps/web/.claude/ NOT pushed (public repo)" sh -c '! printf "%s\n" "$1" | grep -q "apps/web/.claude/"' _ "$pushed"
check "EXTRAS secret in private repo NOT pushed" sh -c '! git -C "$1" ls-tree -r --name-only feat/x | grep -qx .env.local' _ "$T/remotes/app.git"

section "save-all on a protected branch (dirty and clean-with-unpushed-commit)"
git -C "$P" rm -rf --cached . >/dev/null 2>&1 || true
git -C "$P" checkout -f -q main
rm -f "$P/.env" "$P/AGENTS.md"; rm -rf "$P/.claude" "$P/apps/web"
echo more > "$P/more.js"
out="$("$K/save-all.sh" 2>&1)"
check "dirty protected branch moved to wip/rescue-* branch" sh -c 'git -C "$1" for-each-ref --format="%(refname:short)" refs/heads | grep -q "^wip/rescue-"' _ "$T/remotes/pub.git"
check "main on remote untouched" [ "$(git -C "$T/remotes/pub.git" rev-parse main)" = "$(git -C "$T/src/pub" rev-parse HEAD)" ]

git -C "$P" checkout -f -q main
echo "committed-on-main" > "$P/on-main.js"
git -C "$P" add on-main.js && git -C "$P" commit -q -m "unpushed commit on clean main"
sleep 1
out="$("$K/save-all.sh" 2>&1)"; rc=$?
check "clean protected branch with unpushed commit exits 0" [ "$rc" -eq 0 ]
check "unpushed commit on clean main pushed to wip/rescue-*" sh -c 'git -C "$1" log --all --grep="unpushed commit on clean main" --oneline | grep -q .' _ "$T/remotes/pub.git"
check "local main reset back to origin/main" [ "$(git -C "$P" rev-parse main)" = "$(git -C "$T/remotes/pub.git" rev-parse main)" ]

# ─────────────────────────────────────────────────────────────────────────────
section "config saved by a Windows editor (CRLF + BOM)"
{ printf '\357\273\277'; sed 's/$/\r/' "$T/hub.conf"; } > "$T/crlf.conf"
out="$(VIBE_CONF="$T/crlf.conf" "$K/scripts/print-config.sh" 2>&1)"
check "parsed without errors" sh -c "! printf '%s' \"\$1\" | grep -Eq '$ERRPAT'" _ "$out"
check "values have no stray \\r" sh -c 'printf "%s\n" "$1" | grep -qx "HOST_NAME=ci-host"' _ "$out"

section "clone-only + a failing repo does not stop the others"
cat > "$T/c2.conf" <<EOF
HOST_NAME=h2; HOST_ROOT="$T/host2"; AGENTS=(claude)
REPOS=("broken|$T/remotes/does-not-exist.git|x" "app|$T/remotes/app.git|y")
VIBE_OUT="$T/none"; PASS_FILE="$T/none/pass"
EOF
out="$(VIBE_CONF="$T/c2.conf" "$K/sync.sh" --clone-only 2>&1)"; rc=$?
check "reports failure (non-zero)" [ "$rc" -ne 0 ]
check "other repo still cloned" [ -d "$T/host2/app/.git" ]

section "doctor / remote / render-rules smoke (including BASH_COMPAT=32)"
out="$("$K/doctor.sh" 2>&1)"
check "doctor has no shell errors" sh -c "! printf '%s' \"\$1\" | grep -Eq '$ERRPAT'" _ "$out"
out="$("$K/remote.sh" status 2>&1)"
check "remote status has no shell errors" sh -c "! printf '%s' \"\$1\" | grep -Eq '$ERRPAT'" _ "$out"
for kind in vps workstation laptop mac sbc minipc; do
  sed "s/HOST_KIND=\"vps\"/HOST_KIND=\"$kind\"; HOST_SHARED=1/" "$T/hub.conf" > "$T/k.conf"
  out="$(BASH_COMPAT=32 VIBE_CONF="$T/k.conf" "$K/scripts/render-rules.sh" 2>&1)"; rc=$?
  check "render-rules HOST_KIND=$kind (BASH_COMPAT=32)" sh -c '[ "$1" -eq 0 ] && ! grep -q "{{" "$2" && grep -q "^# AGENTS.md — \`ci-host\`" "$2"' _ "$rc" "$K/.rendered/AGENTS.md"
done

printf '\n%s passed, %s failed\n' "$PASS" "$FAILS"
[ "$FAILS" -eq 0 ]
