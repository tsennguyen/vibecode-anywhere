#!/usr/bin/env bash
# vibecode-anywhere — sync.sh  (runs on the HOST: Ubuntu/Debian)
# Restore a snapshot made by pack.sh: clone missing repos/worktrees, put every repo on the snapshot's
# branch + commit, re-apply uncommitted work, drop secrets/config in place, then render agent rules.
# Safe to re-run: local changes are stashed first; a branch that would lose commits is backed up.
#
#   ./sync.sh                     restore from $VIBE_OUT/bundle.tar.gz.enc
#   ./sync.sh path/to/bundle.enc  restore from another file
#   ./sync.sh --clone-only        no bundle: just clone REPOS/WORKTREES at their default branch
#
# (c) 2026 Nguyễn Việt Thành — MIT License.
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/scripts/lib.sh"

ROOT="$HOST_ROOT"
STAMP_NOW="$(date +%Y%m%d-%H%M)"
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
fi

restore() { # $1 = path, $2 = repo|worktree, $3 = clone url | parent path
  local p="$1" kind="$2" src="$3" dir="$ROOT/$1" s="$STAGE/repos/${1//\//__}"

  if [ ! -e "$dir/.git" ]; then
    mkdir -p "$(dirname "$dir")"
    if [ "$kind" = repo ]; then
      [ -n "$src" ] || { warn "$p: no clone url in config, skipped"; return; }
      git clone -q "$src" "$dir" || { bad "$p: clone failed (gh auth login? private repo?)"; return; }
    else
      git -C "$ROOT/$src" worktree prune
      git -C "$ROOT/$src" worktree add -q --detach "$dir" || { bad "$p: worktree add failed"; return; }
    fi
  fi
  if [ ! -d "$s" ]; then
    printf '  OK    %-50s [%s] cloned (not in snapshot)\n' "$p" "$(git -C "$dir" branch --show-current)"
    return
  fi

  local br head
  br="$(cat "$s/branch")"; head="$(cat "$s/head")"
  (
    cd "$dir"
    local common
    common="$(git rev-parse --path-format=absolute --git-common-dir)"
    if [ -f "$s/exclude" ]; then mkdir -p "$common/info" && cp "$s/exclude" "$common/info/exclude"; fi
    if [ -d "$s/hooks" ]; then mkdir -p "$common/hooks" && cp "$s/hooks/"* "$common/hooks/" && chmod +x "$common/hooks/"*; fi
    if [ -n "$(git status --porcelain)" ]; then
      git stash push -q -u -m "vibecode-sync backup $STAMP_NOW"
      echo "  NOTE  $p: local changes stashed (git stash list)"
    fi
    git fetch -q --all --prune || true
    [ -f "$s/local.bundle" ] && git fetch -q "$s/local.bundle" HEAD

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

    [ -s "$s/wip.patch" ] && git apply --whitespace=nowarn "$s/wip.patch"
    [ -f "$s/untracked.tar" ] && tar -xf "$s/untracked.tar"
    printf '  OK    %-50s [%s] %s changed\n' "$p" "${br:-detached}" "$(git status --porcelain | wc -l | tr -d ' ')"
  )
}

echo ">> Repos → $ROOT"
for e in ${REPOS[@]+"${REPOS[@]}"}; do restore "$(f1 "$e")" repo "$(f2 "$e")"; done
echo ">> Worktrees"
for e in ${WORKTREES[@]+"${WORKTREES[@]}"}; do restore "$(f1 "$e")" worktree "$(f2 "$e")"; done

if [ "$CLONE_ONLY" = 0 ]; then
  echo ">> Extras"
  [ -f "$STAGE/extras.tar" ] && tar -xf "$STAGE/extras.tar" -C "$ROOT" && echo "  OK    secrets + local config + work folders"
  [ -f "$STAGE/home.tar" ] && tar -xf "$STAGE/home.tar" -C "$HOME" && echo "  OK    agent config in \$HOME"
  mkdir -p "$VA_HOME/config"
  [ -f "$VA_HOME/config/hub.conf" ] || cp "$STAGE/config/hub.conf" "$VA_HOME/config/hub.conf"
  [ -f "$STAGE/config/rules.extra.md" ] && cp "$STAGE/config/rules.extra.md" "$VA_HOME/config/rules.extra.md"
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
echo ">> Done. Next (first time only): ./install-deps.sh"
