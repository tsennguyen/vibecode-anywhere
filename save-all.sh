#!/usr/bin/env bash
# vibecode-anywhere — save-all.sh: commit + push every repo with uncommitted or unpushed work,
# so nothing lives only on this machine. Never force-pushes, never skips hooks.
# Work on a protected branch (PROTECTED_BRANCHES) or a detached HEAD moves to a new wip/rescue-<time> branch.
# Safety: NEW files that look like secrets (.env*, keys, credentials…) or are listed in EXTRAS are never
# committed; in PUBLIC_REPOS, new AI files (AGENTS.md, CLAUDE.md, .claude/, .agents/…) are never committed either.
# (c) 2026 Nguyễn Việt Thành — MIT License.
set -uo pipefail
source "$(cd "$(dirname "$0")" && pwd)/scripts/lib.sh"
acquire_lock
trap 'release_lock' EXIT
STAMP="$(date +%Y%m%d-%H%M%S)"
FAILED=()

unstage_one() { # $1 = file path relative to repo
  if git cat-file -e "HEAD:$1" 2>/dev/null; then
    git reset -q HEAD -- "$1"
  else
    git rm -q --cached -r -- "$1"
  fi
}

save() {
  local p="$1" d="$HOST_ROOT/$1"
  [ -e "$d/.git" ] || return 0
  (
    cd "$d" || exit 1
    gdir="$(git rev-parse --git-dir)"
    if [ -d "$gdir/rebase-merge" ] || [ -d "$gdir/rebase-apply" ] || [ -f "$gdir/MERGE_HEAD" ] \
       || [ -n "$(git diff --name-only --diff-filter=U)" ]; then
      echo "  WARN  $p has an unfinished merge/rebase or conflict markers — resolve first"
      exit 1
    fi
    br="$(git branch --show-current)"
    if [ -n "$(git status --porcelain)" ]; then
      git add -A || exit 1
      # Unstage secrets, EXTRAS, AI files in public repos, nested .git dirs, and >95 MB files.
      git diff --cached --no-renames --name-only --diff-filter=ACMR -z > "$gdir/va-staged.z"
      while IFS= read -r -d '' f; do
        [ -n "$f" ] || continue
        why=""
        if [ -e "$f/.git" ]; then why="nested git repository"
        elif is_secret_path "$f"; then why="looks like a secret"
        elif is_extra_path "$p/$f"; then why="listed in EXTRAS"
        elif is_public_repo "$p" && is_ai_path "$f"; then why="AI file in a PUBLIC repo"
        elif [ -f "$f" ] && [ "$(wc -c < "$f" | tr -d ' ')" -gt 99614720 ]; then why="over 95 MB (GitHub limit)"; fi
        if [ -n "$why" ]; then
          unstage_one "$f"
          echo "  KEEP  $p/$f stays local ($why) — add it to .gitignore"
        fi
      done < "$gdir/va-staged.z"
      rm -f "$gdir/va-staged.z"
      if git diff --cached --quiet; then
        echo "  OK    $p [${br:-detached}] only local-only files changed, nothing to commit"
      else
        if [ -z "$br" ] || is_protected "$br"; then
          git switch -q -c "wip/rescue-$STAMP" || exit 1
          br="wip/rescue-$STAMP"
        fi
        git commit -q -m "wip: rescue snapshot $STAMP" || exit 1
      fi
    fi

    ahead="$(git rev-list HEAD --not --remotes=origin 2>/dev/null | head -1)"
    if [ -n "$ahead" ] && { [ -z "$br" ] || is_protected "$br"; }; then
      old_br="$br"
      git switch -q -c "wip/rescue-$STAMP" || exit 1
      [ -n "$old_br" ] && git rev-parse -q --verify "refs/remotes/origin/$old_br" >/dev/null \
        && git branch -q -f "$old_br" "refs/remotes/origin/$old_br"
      br="wip/rescue-$STAMP"
    fi
    if [ -z "$br" ] || is_protected "$br"; then
      echo "  OK    $p [${br:-detached}] clean, nothing to push"
      exit 0
    fi
    if [ -n "$ahead" ]; then
      if git push -q -u origin HEAD 2>/dev/null; then
        echo "  PUSH  $p [$br]"
      else
        git push -q -u origin "HEAD:refs/heads/wip/rescue-$STAMP" || exit 1
        echo "  PUSH  $p [wip/rescue-$STAMP] (remote '$br' had diverged)"
      fi
    else
      echo "  OK    $p [$br] already pushed"
    fi
    for b in $(git for-each-ref --format='%(refname:short)' refs/heads/backup/); do
      git push -q origin "$b:$b" 2>/dev/null || true
    done
  ) || { echo "  FAIL  $p (see message above)"; FAILED+=("$p"); }
}

while IFS= read -r p; do [ -n "$p" ] && save "$p" </dev/null; done <<EOF
$(all_paths)
EOF

if [ "${#FAILED[@]}" -gt 0 ]; then printf 'Not saved: %s\n' "${FAILED[@]}"; exit 1; fi
echo "All work is on the remote."
