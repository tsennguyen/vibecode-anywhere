#!/usr/bin/env bash
# vibecode-anywhere — sync.sh  (runs on the HOST: Linux, macOS or Windows/Git Bash)
# Restore a snapshot made by pack.sh: clone missing repos/worktrees, put every repo on the snapshot's
# branch + commit, re-apply uncommitted work, drop secrets/config in place, then render agent rules.
# Safe to re-run:
#   - local changes are stashed first; a branch that would lose commits is saved as backup/<branch>-<time>
#   - files that would be overwritten with different content are copied to ~/.vibecode-backup/<time>/
#   - one repo failing does not stop the others
#
#   ./sync.sh                     restore from $VIBE_OUT/bundle.tar.gz.enc
#   ./sync.sh path/to/bundle.enc  restore from another file
#   ./sync.sh --clone-only        no bundle: just clone REPOS/WORKTREES at their default branch
#
# (c) 2026 Nguyễn Việt Thành — MIT License.
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/scripts/lib.sh"

ROOT="$HOST_ROOT"
STAMP_NOW="$(date +%Y%m%d-%H%M%S)"
BACKUP="$HOME/.vibecode-backup/$STAMP_NOW"
FAILED=()
mkdir -p "$ROOT"

CLONE_ONLY=0
BUNDLE="$VIBE_OUT/bundle.tar.gz.enc"
case "${1:-}" in
  --clone-only) CLONE_ONLY=1 ;;
  "") ;;
  *) BUNDLE="$1" ;;
esac
if [ "$CLONE_ONLY" = 0 ] && [ ! -f "$BUNDLE" ]; then
  warn "$BUNDLE not found → cloning repos only (no secrets, no uncommitted work). Use pack.sh on your main computer to carry those."
  CLONE_ONLY=1
fi

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

if [ "$CLONE_ONLY" = 0 ]; then
  if [ ! -s "$PASS_FILE" ]; then
    printf 'Bundle passphrase (paste, input hidden): '
    read -rs PASS; echo
    ( umask 077; printf '%s' "$PASS" > "$PASS_FILE" )
    unset PASS
  fi
  openssl enc -d -aes-256-cbc -pbkdf2 -iter 200000 -md sha256 -pass "file:$PASS_FILE" -in "$BUNDLE" \
    | tar -xzf - -C "$STAGE" \
    || die "cannot decrypt — wrong passphrase in $PASS_FILE? Delete that file and re-run."
  echo ">> Snapshot from $(cut -d'|' -f1 "$STAGE/source") at $(cut -d'|' -f2 "$STAGE/source")"

  # The config INSIDE the encrypted bundle is the trusted one; the plaintext copy next to it only exists
  # so bootstrap can run before decryption.
  mkdir -p "$VA_HOME/config"
  if [ -f "$VIBE_OUT/hub.conf" ] && ! cmp -s "$STAGE/config/hub.conf" "$VIBE_OUT/hub.conf"; then
    warn "$VIBE_OUT/hub.conf differs from the encrypted copy (stale or modified) — the encrypted one wins"
  fi
  if [ ! -f "$VA_HOME/config/hub.conf" ]; then
    cp "$STAGE/config/hub.conf" "$VA_HOME/config/hub.conf"
    if [ "${VIBE_SYNC_REEXEC:-0}" != 1 ] && [ -z "${VIBE_CONF:-}" ]; then
      echo ">> Using the config from the bundle — restarting sync with it"
      rm -rf "$STAGE"   # exec skips the EXIT trap: never leave decrypted files behind
      VIBE_SYNC_REEXEC=1 exec "$0" "$@"
    fi
  elif ! cmp -s "$STAGE/config/hub.conf" "$VA_HOME/config/hub.conf"; then
    cp "$STAGE/config/hub.conf" "$VA_HOME/config/hub.conf.from-bundle"
    warn "config/hub.conf on this host differs from the bundle's — kept the host copy; bundle copy: config/hub.conf.from-bundle"
  fi
fi

# Copy a staged tree into place; any existing file that would change is backed up first.
place_tree() { # $1 = staged dir, $2 = destination, $3 = label
  local src="$1" dst="$2" n=0 f
  while IFS= read -r f; do
    f="${f#./}"
    if [ -f "$dst/$f" ] && ! cmp -s "$src/$f" "$dst/$f"; then
      mkdir -p "$BACKUP/$3/$(dirname "$f")" && cp -p "$dst/$f" "$BACKUP/$3/$f" && n=$((n + 1))
    fi
  done <<EOF
$(cd "$src" && find . -type f)
EOF
  cp -Rp "$src/." "$dst/"
  [ "$n" -gt 0 ] && echo "  NOTE  $n existing file(s) replaced; previous versions in $BACKUP/$3/"
  return 0
}

restore() { # $1 = path, $2 = repo|worktree, $3 = clone url | parent path   (runs with set -e)
  local p="$1" kind="$2" src="$3" dir="$ROOT/$1" s="$STAGE/repos/${1//\//__}"

  if [ ! -e "$dir/.git" ]; then
    mkdir -p "$(dirname "$dir")"
    if [ "$kind" = repo ]; then
      [ -n "$src" ] || { echo "  WARN  $p: no clone url in config, skipped"; return 0; }
      git clone -q "$src" "$dir"
    else
      git -C "$ROOT/$src" worktree prune
      git -C "$ROOT/$src" worktree add -q --detach "$dir"
    fi
  fi
  if [ ! -d "$s" ]; then
    printf '  OK    %-50s [%s] cloned (not in snapshot)\n' "$p" "$(git -C "$dir" branch --show-current)"
    return 0
  fi

  local br head common
  br="$(cat "$s/branch")"; head="$(cat "$s/head")"
  cd "$dir"
  common="$(git rev-parse --path-format=absolute --git-common-dir)"
  if [ -f "$s/exclude" ]; then   # merge: keep host-only lines, add the snapshot's
    mkdir -p "$common/info"; touch "$common/info/exclude"
    cat "$common/info/exclude" "$s/exclude" | awk '!seen[$0]++' > "$common/info/exclude.new"
    mv "$common/info/exclude.new" "$common/info/exclude"
  fi
  if [ -d "$s/hooks" ]; then mkdir -p "$common/hooks" && cp "$s/hooks/"* "$common/hooks/" && chmod +x "$common/hooks/"*; fi
  if [ -n "$(git status --porcelain)" ]; then
    git stash push -q -u -m "vibecode-sync backup $STAMP_NOW"
    echo "  NOTE  $p: local changes stashed (git stash list)"
  fi
  git fetch -q --all --prune || echo "  WARN  $p: fetch failed (offline?)"
  if [ -f "$s/local.bundle" ]; then git fetch -q "$s/local.bundle" HEAD; fi

  if [ -n "$br" ]; then
    if git rev-parse -q --verify "refs/heads/$br" >/dev/null \
       && ! git merge-base --is-ancestor "refs/heads/$br" "$head"; then
      git branch -q -f "backup/$br-$STAMP_NOW" "refs/heads/$br"
      echo "  NOTE  $p: '$br' had other commits, saved as backup/$br-$STAMP_NOW"
    fi
    git checkout -q -B "$br" "$head"
    if git rev-parse -q --verify "refs/remotes/origin/$br" >/dev/null; then
      git branch -q --set-upstream-to="origin/$br" "$br"
    fi
  else
    git checkout -q --detach "$head"
  fi

  if [ -s "$s/wip.patch" ]; then
    if ! git apply --whitespace=nowarn "$s/wip.patch" 2>/dev/null && ! git apply --3way --whitespace=nowarn "$s/wip.patch"; then
      mkdir -p "$BACKUP"; cp "$s/wip.patch" "$BACKUP/${p//\//__}.wip.patch"
      echo "  WARN  $p: uncommitted changes did not apply cleanly — patch saved to $BACKUP/${p//\//__}.wip.patch"
    fi
  fi
  if [ -f "$s/untracked.tar" ]; then
    mkdir -p "$STAGE/untracked/${p//\//__}"
    tar -xf "$s/untracked.tar" -C "$STAGE/untracked/${p//\//__}"
    place_tree "$STAGE/untracked/${p//\//__}" "$dir" "repos/$p"
  fi
  printf '  OK    %-50s [%s] %s changed\n' "$p" "${br:-detached}" "$(git status --porcelain | wc -l | tr -d ' ')"
}

# Run restore in its own subshell with errexit ON, but never let one repo abort the whole sync.
run_restore() {
  local rc
  set +e
  ( set -e; restore "$@" )
  rc=$?
  set -e
  if [ "$rc" -ne 0 ]; then
    bad "$1: restore stopped at the step above — repo left as it was (local changes, if any, are in git stash)"
    FAILED+=("$1")
  fi
  return 0
}

echo ">> Repos → $ROOT"
for e in ${REPOS[@]+"${REPOS[@]}"}; do run_restore "$(f1 "$e")" repo "$(f2 "$e")"; done
echo ">> Worktrees"
for e in ${WORKTREES[@]+"${WORKTREES[@]}"}; do run_restore "$(f1 "$e")" worktree "$(f2 "$e")"; done

if [ "$CLONE_ONLY" = 0 ]; then
  echo ">> Extras"
  if [ -f "$STAGE/extras.tar" ]; then
    mkdir -p "$STAGE/x-extras" && tar -xf "$STAGE/extras.tar" -C "$STAGE/x-extras"
    place_tree "$STAGE/x-extras" "$ROOT" extras && echo "  OK    secrets + local config + work folders"
  fi
  if [ -f "$STAGE/home.tar" ]; then
    mkdir -p "$STAGE/x-home" && tar -xf "$STAGE/home.tar" -C "$STAGE/x-home"
    place_tree "$STAGE/x-home" "$HOME" home && echo "  OK    agent config in \$HOME"
  fi
  if [ -f "$STAGE/config/rules.extra.md" ]; then
    [ -f "$VA_HOME/config/rules.extra.md" ] && ! cmp -s "$STAGE/config/rules.extra.md" "$VA_HOME/config/rules.extra.md" \
      && mkdir -p "$BACKUP" && cp "$VA_HOME/config/rules.extra.md" "$BACKUP/rules.extra.md"
    cp "$STAGE/config/rules.extra.md" "$VA_HOME/config/rules.extra.md"
  fi
fi

if [ -n "$GIT_NAME" ] && [ -n "$GIT_EMAIL" ]; then
  while IFS= read -r p; do
    [ -n "$p" ] && [ -e "$ROOT/$p/.git" ] || continue
    git -C "$ROOT/$p" config user.name "$GIT_NAME"
    git -C "$ROOT/$p" config user.email "$GIT_EMAIL"
  done <<EOF
$(all_paths)
EOF
fi

"$VA_HOME/scripts/render-rules.sh"
if [ "${#FAILED[@]}" -gt 0 ]; then
  warn "not restored: ${FAILED[*]} — fix the cause (network? auth?) and re-run ./sync.sh"
  exit 1
fi
echo ">> Done. Next (first time only): ./install-deps.sh"
