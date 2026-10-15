# Changelog

## 2.0.1 — 2026-10-15
Security and safety fixes found in a risk review of 2.0.0.

- **save-all.sh could push secrets.** New untracked files such as `.env.local` were committed and pushed, including to PUBLIC repos. Now new files that look like secrets (`.env*`, keys, credentials, `.npmrc`…) or are listed in `EXTRAS` are never committed. In `PUBLIC_REPOS`, new AI files (`AGENTS.md`, `CLAUDE.md`, `.claude/`, `.agents/`…) are never committed either. A notice tells you to add them to `.gitignore`.
- **pack.sh** refuses to run if `hub.conf` contains something that looks like a credential (e.g. a token in a clone URL), because `hub.conf` travels unencrypted. It also skips `node_modules`/`.venv`/`.next` in untracked files and warns when the bundle exceeds 500 MB.
- **sync.sh**:
  - Files that would be overwritten with different content (secrets, agent config, untracked files) are first copied to `~/.vibecode-backup/<time>/`.
  - One failing repo no longer aborts the whole sync.
  - Uncommitted changes that don't apply cleanly are saved as a patch instead of stopping.
  - `.git/info/exclude` is merged rather than replaced.
  - The config inside the encrypted bundle now wins over the plaintext copy, and sync warns if the two differ.
  - Decrypted temp files are removed before the restart.
- **Windows-edited configs** (CRLF line endings, UTF-8 BOM from Notepad) used to break every script silently; they are now read correctly.
- **bootstrap.ps1** runs from a normal PowerShell. It asks for UAC once for the system part, and installs agents, npm globals and rules into the user's own profile instead of an admin profile. It also copies SSH keys to `administrators_authorized_keys` (needed for admin accounts) and sets `DefaultShellCommandOption` for Git Bash.
- **bootstrap-linux.sh**: installs `sudo` on minimal root images; falls back to Eclipse Temurin when the distro lacks the requested JDK (e.g. Debian 12 + Java 21).
- `render-rules.sh` tells you to move personal rules into `config/rules.extra.md` when it backs up an existing global rules file. `doctor.sh` warns when git has no identity.
- System facts default to safe numbers when a probe fails.

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
