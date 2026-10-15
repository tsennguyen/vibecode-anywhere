#!/usr/bin/env bash
# vibecode-anywhere — print the resolved config as KEY=VALUE lines (used by bootstrap.ps1 on Windows,
# handy for debugging anywhere). Never prints secrets: hub.conf holds none.
# (c) 2026 Nguyễn Việt Thành — MIT License.
set -uo pipefail
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"
winpath() { if have cygpath; then cygpath -w "$1"; else printf '%s' "$1"; fi; }
cat <<EOF
VA_VERSION=$VA_VERSION
VA_OS=$VA_OS
VA_CONF=$VA_CONF
VA_HOME_WIN=$(winpath "$VA_HOME")
HOST_NAME=$HOST_NAME
HOST_KIND=$HOST_KIND
HOST_KIND_LABEL=$HOST_KIND_LABEL
HOST_SHARED=$HOST_SHARED
HOST_ROOT=$HOST_ROOT
HOST_ROOT_WIN=$(winpath "$HOST_ROOT")
PROFILE_LABEL=$PROFILE_LABEL
NODE_HEAP_MB=$NODE_HEAP_MB
NODE_VERSION=$NODE_VERSION
JAVA_VERSION=$JAVA_VERSION
WANT_SSH=$WANT_SSH
WANT_PLAYWRIGHT=$WANT_PLAYWRIGHT
TIMEZONE=$TIMEZONE
GIT_NAME=$GIT_NAME
GIT_EMAIL=$GIT_EMAIL
AGENTS=${AGENTS[*]-}
STACKS=${STACKS[*]-}
TOOLS=${TOOLS[*]-}
WINDOWS_BLOCK_AUTO_REBOOT=${WINDOWS_BLOCK_AUTO_REBOOT:-1}
WINDOWS_SSH_SHELL=${WINDOWS_SSH_SHELL:-bash}
EOF
