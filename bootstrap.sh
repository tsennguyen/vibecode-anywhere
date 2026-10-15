#!/usr/bin/env bash
# vibecode-anywhere — bootstrap.sh: one-time setup of the HOST (the always-on machine the agent runs on).
# Picks the right installer for this OS:
#   Linux (Ubuntu/Debian family: VPS, workstation, mini PC, Raspberry Pi OS 64-bit, WSL2) → scripts/bootstrap-linux.sh
#   macOS (Mac mini, Mac Studio, MacBook kept on)                                       → scripts/bootstrap-macos.sh
#   Windows (workstation, mini PC, laptop)  → run bootstrap.ps1 from a normal PowerShell instead (it asks for UAC once)
# (c) 2026 Nguyễn Việt Thành — MIT License.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
case "$(uname -s)" in
  Linux)  exec "$HERE/scripts/bootstrap-linux.sh" "$@" ;;
  Darwin) exec "$HERE/scripts/bootstrap-macos.sh" "$@" ;;
  MINGW*|MSYS*|CYGWIN*)
    echo "On Windows, open a normal PowerShell in this folder and run (it asks for admin rights once):"
    echo "  powershell -ExecutionPolicy Bypass -File .\\bootstrap.ps1"
    exit 1 ;;
  *) echo "Unsupported OS: $(uname -s). Supported hosts: Ubuntu/Debian-family Linux, macOS, Windows 10/11." >&2; exit 1 ;;
esac
