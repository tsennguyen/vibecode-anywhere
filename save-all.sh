#!/usr/bin/env bash
# vibecode-anywhere — save-all.sh: commit + push every repo with uncommitted or unpushed work,
# so nothing lives only on this machine. Never force-pushes, never skips hooks.
# Work on a protected branch (PROTECTED_BRANCHES) or a detached HEAD moves to a new wip/rescue-<time> branch.
# Safety: NEW files that look like secrets (.env*, keys, credentials…) or are listed in EXTRAS are never
# committed; in PUBLIC_REPOS, new AI files (AGENTS.md, CLAUDE.md, .claude/, .agents/…) are never committed either.
# (c) 2026 Nguyễn Việt Thành — MIT License.
set -uo pipefail
source "$(cd "$(dirname "$0")" && pwd)/scripts/lib.sh"
STAMP="$(date +%Y%m%d-%H%M)"
FAILED=()

save() {
  local p="$1" d="$HOST_ROOT/$1"
  [ -e "$d/.git" ] || return 0
  (
    cd "$d" || exit 1
    br="$(git branch --show-current)"
    if [ -n "$(git status --porcelain)" ]; then
      git add -A || exit 1
      # Unstage new files that must stay local.
      git diff --cached --name-only --diff-filter=A -z | while IFS= read -r -d '' f; do
        why=""
        if is_secret_path "$f"; then why="looks like a secret"
        elif is_extra_path "$p/$f"; then why="listed in EXTRAS"
        elif is_public_repo "$p" && is_ai_path "$f"; then why="AI file in a PUBLIC repo"; fi
        if [ -n "$why" ]; then
          git rm -q --cached -- "$f"
          echo "  KEEP  $p/$f stays local ($why) — add it to .gitignore"
        fi
      done
      if git diff --cached --quiet; then
        echo "  OK    $p [${br:-detached}] only local-only files changed, nothing to commit"
      else
        if [ -z "$br" ] || is_protected "$br"; then git switch -q -c "wip/rescue-$STAMP" || exit 1; br="wip/rescue-$STAMP"; fi
        git commit -q -m "wip: rescue snapshot $STAMP" || exit 1
      fi
    fi
    if [ -z "$br" ] || is_protected "$br"; then echo "  SKIP  $p [${br:-detached}] nothing to push (protected branch)"; exit 0; fi
    if [ -n "$(git rev-list HEAD --not --remotes | head -1)" ]; then
      git push -q -u origin HEAD || exit 1
      echo "  PUSH  $p [$br]"
    else
      echo "  OK    $p [$br] already pushed"
    fi
  ) || { echo "  FAIL  $p (see message above)"; FAILED+=("$p"); }
}

while IFS= read -r p; do [ -n "$p" ] && save "$p" </dev/null; done <<EOF
$(all_paths)
EOF

if [ "${#FAILED[@]}" -gt 0 ]; then printf 'Not saved: %s\n' "${FAILED[@]}"; exit 1; fi
echo "All work is on the remote."
