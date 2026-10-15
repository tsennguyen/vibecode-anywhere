#!/usr/bin/env bash
# vibecode-anywhere — pack.sh
# Snapshot every repo (branch, HEAD, uncommitted work, local-only commits, .git/info/exclude, local hooks)
# plus gitignored secrets/config and selected agent config into ONE encrypted file.
#
# Runs on your main computer: macOS, Linux, or Windows (Git Bash — or use pack.ps1 from PowerShell).
# Also runs on the host at the end of a trip, to bring the work back home.
#
#   ./pack.sh                 pack from SOURCE_ROOT (falls back to HOST_ROOT when run on the host)
#   ./pack.sh --root DIR      pack from another folder
#
# Output ($VIBE_OUT, default ~/vibecode-out):
#   bundle.tar.gz.enc   encrypted (AES-256-CBC, PBKDF2 200k, SHA-256) — repos state + secrets
#   hub.conf            copy of your config (no secrets) so the host can bootstrap before decrypting
#
# (c) 2026 Nguyễn Việt Thành — MIT License.
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/scripts/lib.sh"

ROOT="$SOURCE_ROOT"; [ -d "$ROOT" ] || ROOT="$HOST_ROOT"
[ "${1:-}" = "--root" ] && ROOT="${2:?--root needs a folder}"
[ -d "$ROOT" ] || die "repos folder not found: $ROOT (check SOURCE_ROOT in $VA_CONF)"
have openssl || die "openssl not found (macOS/Linux ship it; on Windows run this inside Git Bash)"
OUT="$VIBE_OUT/bundle.tar.gz.enc"

if [ ! -s "$PASS_FILE" ]; then
  ( umask 077; openssl rand -base64 30 | tr -d '\n' > "$PASS_FILE" )
  echo ">> Created a new passphrase in $PASS_FILE — the host needs the same one. Save it on your phone."
fi

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
mkdir -p "$STAGE/repos" "$VIBE_OUT"

snapshot() { # $1 = path relative to ROOT
  local p="$1" dir="$ROOT/$1" out="$STAGE/repos/${1//\//__}"
  if [ ! -e "$dir/.git" ]; then echo "  WARN  $p: not found, skipped"; return; fi
  mkdir -p "$out"
  (
    cd "$dir"
    git fetch --quiet --all --prune 2>/dev/null || echo "  WARN  $p: fetch failed (offline?)"
    git branch --show-current > "$out/branch"
    git rev-parse HEAD > "$out/head"
    local ahead
    ahead="$(git rev-list --count HEAD --not --remotes)"
    [ "$ahead" -gt 0 ] && git bundle create "$out/local.bundle" HEAD --not --remotes >/dev/null 2>&1
    # .git/info/exclude and hooks are never cloned (they often guard PUBLIC repos) → carry them.
    local common excl h
    common="$(git rev-parse --path-format=absolute --git-common-dir)"
    excl="$common/info/exclude"
    [ -s "$excl" ] && cp "$excl" "$out/exclude"
    for h in "$common/hooks"/*; do
      case "$h" in *.sample) continue ;; esac
      [ -f "$h" ] || continue
      grep -qE 'LEFTHOOK|husky|pre-commit\.com' "$h" 2>/dev/null && continue   # managers reinstall these
      mkdir -p "$out/hooks" && cp "$h" "$out/hooks/"
    done
    git diff --binary HEAD > "$out/wip.patch"
    git ls-files --others --exclude-standard -z > "$out/untracked.list"
    local n_untracked=0
    if [ -s "$out/untracked.list" ]; then
      n_untracked="$(tr -cd '\0' < "$out/untracked.list" | wc -c | tr -d ' ')"
      tar --null -T "$out/untracked.list" -cf "$out/untracked.tar"
    fi
    rm -f "$out/untracked.list"
    printf '  OK    %-50s [%s] local-commits=%s changed=%s untracked=%s\n' \
      "$p" "$(cat "$out/branch")" "$ahead" "$(git diff --name-only HEAD | wc -l | tr -d ' ')" "$n_untracked"
  )
}

echo ">> Repos + worktrees from $ROOT"
while IFS= read -r p; do [ -n "$p" ] && snapshot "$p" </dev/null; done <<EOF
$(all_paths)
EOF

echo ">> Extras (gitignored files)"
EXISTING=()
for e in ${EXTRAS[@]+"${EXTRAS[@]}"}; do
  if [ -e "$ROOT/$e" ]; then EXISTING+=("$e"); echo "  OK    $e"; else echo "  WARN  $e: not found, skipped"; fi
done
if [ "${#EXISTING[@]}" -gt 0 ]; then
  tar -cf "$STAGE/extras.tar" --exclude node_modules --exclude .DS_Store -C "$ROOT" "${EXISTING[@]}"
fi

echo ">> Agent config from \$HOME (login tokens are always skipped)"
H_EXISTING=()
for e in ${HOME_EXTRAS[@]+"${HOME_EXTRAS[@]}"}; do
  if is_secret_login_file "$e"; then echo "  SKIP  $e (login token — sign in again on the host)"; continue; fi
  if [ -e "$HOME/$e" ]; then H_EXISTING+=("$e"); echo "  OK    ~/$e"; else echo "  WARN  ~/$e: not found, skipped"; fi
done
if [ "${#H_EXISTING[@]}" -gt 0 ]; then
  tar -cf "$STAGE/home.tar" --exclude node_modules --exclude .DS_Store \
    --exclude auth.json --exclude .credentials.json --exclude 'oauth*' --exclude '*token*' \
    -C "$HOME" "${H_EXISTING[@]}"
fi

# Personal config files travel inside the bundle too.
mkdir -p "$STAGE/config"
cp "$VA_CONF" "$STAGE/config/hub.conf"
[ -f "$VA_HOME/config/rules.extra.md" ] && cp "$VA_HOME/config/rules.extra.md" "$STAGE/config/"

FROM="$(hostname -s 2>/dev/null || hostname 2>/dev/null || echo unknown)"
echo "$FROM|$(date '+%Y-%m-%d %H:%M %Z')|$ROOT" > "$STAGE/source"

tar -czf - -C "$STAGE" . \
  | openssl enc -aes-256-cbc -pbkdf2 -iter 200000 -md sha256 -salt -pass "file:$PASS_FILE" -out "$OUT"
[ "$VA_CONF" -ef "$VIBE_OUT/hub.conf" ] || cp "$VA_CONF" "$VIBE_OUT/hub.conf"

SIZE_KB=$(( $(wc -c < "$OUT") / 1024 ))
echo ">> Wrote $OUT (${SIZE_KB} KB) + hub.conf"
echo ">> Next: copy the folder $VIBE_OUT to the host (scp) AND to a private cloud drive as backup."
echo ">> Keep the passphrase ($PASS_FILE) on your phone (password manager / notes), NOT in that folder."
