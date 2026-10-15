#!/usr/bin/env bash
# vibecode-anywhere — install-deps.sh (HOST — Linux, macOS or Windows/Git Bash — after sync.sh): install every repo's dependencies,
# pre-pull Docker images, optionally Playwright Chromium, then run SMOKE_TESTS.
#
#   ./install-deps.sh          main repos only
#   ./install-deps.sh --all    also every worktree (each worktree = another node_modules, watch the disk)
#
# Auto-detection (repo root and one level down; DEP_COMMANDS in config overrides a repo):
#   package-lock.json → npm ci      pnpm-lock.yaml → pnpm install --frozen-lockfile   yarn.lock → yarn install
#   bun.lock(b) → bun install       uv.lock → uv sync      requirements.txt → .venv + pip install
#   mvnw → dependency:go-offline    gradlew → dependencies  go.mod → go mod download   Cargo.toml → cargo fetch
# (c) 2026 Nguyễn Việt Thành — MIT License.
set -uo pipefail
source "$(cd "$(dirname "$0")" && pwd)/scripts/lib.sh"
ALL=0; [ "${1:-}" = "--all" ] && ALL=1
FAILED=()
run() { local name="$1"; shift; if ( "$@" ); then echo "  OK    $name"; else echo "  FAIL  $name"; FAILED+=("$name"); fi; }

disk="$(disk_pct)"
[ "$disk" -lt "$DISK_WARN_PCT" ] || die "disk ${disk}% full — clean up first (docs/RESCUE.md §4)"

detect_one() { # $1 = folder containing a manifest; prints commands
  local d="$1"
  if   [ -f "$d/pnpm-lock.yaml" ];    then echo "pnpm install --frozen-lockfile"
  elif [ -f "$d/package-lock.json" ]; then echo "npm ci --no-audit --no-fund"
  elif [ -f "$d/yarn.lock" ];         then echo "corepack yarn install"
  elif [ -f "$d/bun.lock" ] || [ -f "$d/bun.lockb" ]; then echo "bun install"
  fi
  if   [ -f "$d/uv.lock" ];           then echo "uv sync"
  elif [ -f "$d/requirements.txt" ]; then
    if have uv; then echo "uv venv -q && uv pip install -q -r requirements.txt"
    elif [ "$VA_OS" = windows ]; then echo "python -m venv .venv && .venv/Scripts/python -m pip install -q -r requirements.txt"
    else echo "python3 -m venv .venv && .venv/bin/pip install -q -r requirements.txt"; fi
  fi
  [ -x "$d/mvnw" ]      && echo "./mvnw -q -B -DskipTests dependency:go-offline"
  [ -x "$d/gradlew" ]   && echo "./gradlew -q dependencies"
  [ -f "$d/go.mod" ]    && echo "go mod download"
  [ -f "$d/Cargo.toml" ] && echo "cargo fetch"
  return 0
}

install_repo() { # $1 = path relative to HOST_ROOT
  local p="$1" d="$HOST_ROOT/$1" custom sub cmd
  [ -d "$d" ] || { echo "  SKIP  $p (missing — run ./sync.sh)"; return; }
  if custom="$(lookup "$p" ${DEP_COMMANDS[@]+"${DEP_COMMANDS[@]}"})"; then
    run "$p: $custom" bash -c "cd '$d' && $custom"; return
  fi
  local found=0
  for sub in "$d" "$d"/*/; do
    sub="${sub%/}"
    [ -d "$sub" ] || continue
    case "$(basename "$sub")" in node_modules|.git|.venv|target|build|dist|.next) continue ;; esac
    # a nested folder that is itself a configured repo/worktree gets its own pass
    [ "$sub" != "$d" ] && all_paths | grep -qx "${sub#"$HOST_ROOT"/}" && continue
    # inside a JS workspace the root lockfile already covers sub-packages
    if [ "$sub" != "$d" ] && [ -f "$d/pnpm-workspace.yaml" ] && [ ! -f "$sub/uv.lock" ] && [ ! -x "$sub/mvnw" ]; then continue; fi
    while IFS= read -r cmd; do
      [ -n "$cmd" ] || continue; found=1
      run "${sub#"$HOST_ROOT"/}: $cmd" bash -c "cd '$sub' && $cmd" </dev/null
    done <<EOF
$(detect_one "$sub")
EOF
  done
  [ "$found" = 1 ] || echo "  --    $p: no lockfile found (add a DEP_COMMANDS entry if it needs one)"
}

step "Dependencies (profile: $PROFILE_LABEL)"
for e in ${REPOS[@]+"${REPOS[@]}"}; do install_repo "$(f1 "$e")" </dev/null; done
if [ "$ALL" = 1 ]; then
  for e in ${WORKTREES[@]+"${WORKTREES[@]}"}; do install_repo "$(f1 "$e")" </dev/null; done
fi

if [ "$WANT_PLAYWRIGHT" = 1 ]; then
  step "Playwright Chromium"
  pw_repo=""
  for e in ${REPOS[@]+"${REPOS[@]}"}; do
    grep -qs '"@playwright/test"\|"playwright"' "$HOST_ROOT/$(f1 "$e")/package.json" && { pw_repo="$HOST_ROOT/$(f1 "$e")"; break; }
  done
  pw_flags="--with-deps"; [ "$VA_OS" = linux ] || pw_flags=""   # system libraries only matter on Linux
  if [ -n "$pw_repo" ]; then run "playwright chromium" bash -c "cd '$pw_repo' && npx playwright install $pw_flags chromium"
  else echo "  --    no repo uses Playwright"; fi
fi

if [ "${#DOCKER_IMAGES[@]}" -gt 0 ] && have docker; then
  step "Docker images"
  for img in "${DOCKER_IMAGES[@]}"; do run "docker pull $img" docker pull -q "$img"; done
fi

if [ "${#SMOKE_TESTS[@]}" -gt 0 ]; then
  step "Smoke tests"
  for e in "${SMOKE_TESTS[@]}"; do run "$(f1 "$e"): $(f2 "$e")" bash -c "cd '$HOST_ROOT/$(f1 "$e")' && $(f2 "$e")" </dev/null; done
fi

echo
if [ "${#FAILED[@]}" -eq 0 ]; then echo "All good."; else printf 'Failed: %s\n' "${FAILED[@]}"; exit 1; fi
