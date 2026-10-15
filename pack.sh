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
umask 077
export COPYFILE_DISABLE=1
source "$(cd "$(dirname "$0")" && pwd)/scripts/lib.sh"

ROOT="$SOURCE_ROOT"; [ -d "$ROOT" ] || ROOT="$HOST_ROOT"
[ "${1:-}" = "--root" ] && ROOT="${2:?--root needs a folder}"
[ -d "$ROOT" ] || die "repos folder not found: $ROOT (check SOURCE_ROOT in $VA_CONF)"
have openssl || die "openssl not found (macOS/Linux ship it; on Windows run this inside Git Bash)"
OUT="$VIBE_OUT/bundle.tar.gz.enc"
case "$PASS_FILE" in
  "$VIBE_OUT"|"$VIBE_OUT"/*) die "PASS_FILE ($PASS_FILE) must not be inside VIBE_OUT ($VIBE_OUT travels to cloud/host)" ;;
esac

# hub.conf travels UNENCRYPTED next to the bundle: refuse anything that looks like a credential in it.
_cred_re='://[^/@[:space:]"]+:[^/@[:space:]"]+@|://(ghp_|gho_|github_pat_|glpat-)[^@"]*@|ghp_[A-Za-z0-9]{20}|github_pat_[A-Za-z0-9_]{20}|glpat-[A-Za-z0-9_-]{16}|sk-[A-Za-z0-9_-]{20}|AKIA[0-9A-Z]{16}|xox[abp]-[A-Za-z0-9-]{10}|-----BEGIN [A-Z ]*PRIVATE KEY'
_hits="$(grep -nE "$_cred_re" "$VA_CONF" | cut -d: -f1 | tr '\n' ' ' || true)"
[ -z "$_hits" ] || die "$VA_CONF looks like it contains a credential (line(s): $_hits). hub.conf is NOT encrypted — remove it; use 'gh auth login' on the host and put secret files in EXTRAS instead."
if [ -f "$VA_HOME/config/rules.extra.md" ]; then
  _rhits="$(grep -nE "$_cred_re" "$VA_HOME/config/rules.extra.md" | cut -d: -f1 | tr '\n' ' ' || true)"
  [ -z "$_rhits" ] || die "config/rules.extra.md looks like it contains a credential (line(s): $_rhits). Agent rules are readable on the host — remove secrets from rules.extra.md."
fi

if [ ! -s "$PASS_FILE" ]; then
  mkdir -p "$(dirname "$PASS_FILE")"
  ( umask 077; openssl rand -base64 30 | tr -d '\n' > "$PASS_FILE" )
  echo ">> Created a new passphrase in $PASS_FILE — the host needs the same one. Save it on your phone."
fi

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE" "$OUT.tmp"' EXIT
mkdir -p "$STAGE/repos" "$VIBE_OUT"

snapshot() { # $1 = path relative to ROOT
  local p="$1" dir="$ROOT/$1" out="$STAGE/repos/${1//\//__}"
  if [ ! -e "$dir/.git" ]; then echo "  WARN  $p: not found, skipped"; return; fi
  if ! git -C "$dir" rev-parse --verify HEAD >/dev/null 2>&1; then
    echo "  WARN  $p: repository has no commits yet, skipped"; return
  fi
  mkdir -p "$out"
  (
    cd "$dir"
    git fetch --quiet --all --prune 2>/dev/null || echo "  WARN  $p: fetch failed (offline?)"
    git branch --show-current > "$out/branch"
    git rev-parse HEAD > "$out/head"
    local ahead
    ahead="$(git rev-list --count --branches HEAD --not --remotes)"
    if [ "$ahead" -gt 0 ]; then
      git bundle create "$out/local.bundle" --branches HEAD --not --remotes >/dev/null
    fi
    # .git/info/exclude and hooks are never cloned (they often guard PUBLIC repos) → carry them.
    local common excl hooks_dir h
    common="$(git_common_dir .)"
    excl="$common/info/exclude"
    [ -s "$excl" ] && cp "$excl" "$out/exclude"
    hooks_dir="$(git config core.hooksPath || true)"
    [ -n "$hooks_dir" ] || hooks_dir="$common/hooks"
    for h in "$hooks_dir"/*; do
      case "$h" in *.sample) continue ;; esac
      [ -f "$h" ] || continue
      grep -qE 'LEFTHOOK|husky|pre-commit\.com' "$h" 2>/dev/null && continue   # managers reinstall these
      mkdir -p "$out/hooks" && cp "$h" "$out/hooks/"
    done
    git diff --binary HEAD > "$out/wip.patch"
    local u n_untracked=0
    git ls-files --others --exclude-standard -z > "$out/untracked.raw"
    : > "$out/untracked.list"
    while IFS= read -r -d '' u; do
      u="${u%/}"
      [ -e "$u/.git" ] && continue
      all_paths | grep -qx "$p/$u" && continue
      printf '%s\0' "$u" >> "$out/untracked.list"
      n_untracked=$((n_untracked + 1))
    done < "$out/untracked.raw"
    if [ "$n_untracked" -gt 0 ]; then
      tar --exclude node_modules --exclude .venv --exclude .next --exclude __pycache__ \
        --null -T "$out/untracked.list" -cf "$out/untracked.tar"
    fi
    rm -f "$out/untracked.raw" "$out/untracked.list"
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
    --exclude auth.json --exclude .credentials.json --exclude credentials.json --exclude .git-credentials \
    --exclude 'oauth*' --exclude '*oauth*' --exclude '*auth_token*' --exclude '*access_token*' --exclude '*refresh_token*' \
    --exclude hosts.yml --exclude 'id_rsa*' --exclude 'id_ed25519*' --exclude 'id_ecdsa*' --exclude '*.pem' --exclude '*.key' \
    -C "$HOME" "${H_EXISTING[@]}"
  while IFS= read -r _entry; do
    [ -n "$_entry" ] || continue
    if is_secret_login_file "$_entry"; then
      die "HOME_EXTRAS packed a credential/key file ($_entry) — remove that folder from HOME_EXTRAS"
    fi
  done <<EOF
$(tar -tf "$STAGE/home.tar")
EOF
fi

# Personal config files travel inside the bundle too.
mkdir -p "$STAGE/config"
cp "$VA_CONF" "$STAGE/config/hub.conf"
[ -f "$VA_HOME/config/rules.extra.md" ] && cp "$VA_HOME/config/rules.extra.md" "$STAGE/config/"

FROM="$(hostname -s 2>/dev/null || hostname 2>/dev/null || echo unknown)"
echo "$FROM|$(date '+%Y-%m-%d %H:%M %Z')|$ROOT" > "$STAGE/source"

tar -czf - -C "$STAGE" . \
  | openssl enc -aes-256-cbc -pbkdf2 -iter 200000 -md sha256 -salt -pass "file:$PASS_FILE" -out "$OUT.tmp"
openssl enc -d -aes-256-cbc -pbkdf2 -iter 200000 -md sha256 -pass "file:$PASS_FILE" -in "$OUT.tmp" \
  | tar -tzf - >/dev/null || die "bundle verification failed — $OUT was not overwritten"
[ -f "$OUT" ] && cp -f "$OUT" "$OUT.prev"
mv -f "$OUT.tmp" "$OUT"
[ "$VA_CONF" -ef "$VIBE_OUT/hub.conf" ] || cp "$VA_CONF" "$VIBE_OUT/hub.conf"

SIZE_KB=$(( $(wc -c < "$OUT") / 1024 ))
echo ">> Wrote $OUT (${SIZE_KB} KB) + hub.conf"
[ "$SIZE_KB" -lt 512000 ] || warn "bundle is over 500 MB — an EXTRAS folder or untracked build output is probably too big (check node_modules/dist/.gitignore)"
echo ">> Next: copy the folder $VIBE_OUT to the host (scp) AND to a private cloud drive as backup."
echo ">> Keep the passphrase ($PASS_FILE) on your phone (password manager / notes), NOT in that folder."
