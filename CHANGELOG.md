# Changelog

## 2.0.0 — 2026-10-15
**Hosts beyond Ubuntu.** The always-on machine can now be a VPS, workstation, mini PC, laptop, Mac mini or Raspberry Pi, running Linux, macOS or Windows. VPSes stay on Ubuntu.

- New `HOST_KIND` (`vps`, `workstation`, `minipc`, `laptop`, `mac`, `sbc`), `HOST_SHARED` and `SSH_SERVER` settings. The host OS is detected automatically.
- `bootstrap.sh` now dispatches by OS:
  - `scripts/bootstrap-linux.sh` (Ubuntu/Debian family incl. Raspberry Pi OS and WSL2): adds an SSH server on home machines and makes laptop lid-close ignored.
  - **New** `scripts/bootstrap-macos.sh` (Homebrew): `pmset` never-sleep + restart after power loss, Remote Login, colima for headless Docker, ChatGPT desktop for Codex.
- **New** `bootstrap.ps1` for Windows 10/11 (winget). It reads the same `hub.conf`, keeps the PC awake, blocks automatic Windows Update reboots, and enables the OpenSSH Server with Git Bash as its shell. It installs Antigravity/Claude through their official PowerShell installers.
- **New** `vibe.ps1`: run every script from PowerShell (`.\vibe.ps1 sync|doctor|remote ...`). `pack.ps1` remains as a wrapper.
- `remote.sh`: per-OS `start`/`status`/`autostart`:
  - Claude: systemd unit (Linux), LaunchAgent (macOS), Scheduled Task (Windows).
  - Codex on macOS/Windows uses the official ChatGPT desktop remote host.
- `doctor.sh`: portable RAM/swap/disk/load/process checks on all three OSes; checks for the SSH server, Tailscale and the ChatGPT app.
- Agent rules: machine kind, OS-specific "never run" lists, notes for home and shared machines. Windows gets copies instead of symlinks.
- `install-deps.sh`: `uv`-based venvs for `requirements.txt`; Playwright `--with-deps` only on Linux.
- Docs: new `docs/HOSTS.md` / `HOSTS.en.md` (choose and set up a host, home-machine checklist). README, HDSD, AGENTS-GUIDE, RESCUE and PROMPT updated.

## 1.0.0 — 2026-10-15
First public release: pack → bootstrap → sync → install-deps for an Ubuntu/Debian host, with Antigravity, Claude Code and Codex remote control, generated agent rules, a rescue sheet, and the PROMPT.md setup assistant.

---
vibecode-anywhere © 2026 Nguyễn Việt Thành — MIT.
