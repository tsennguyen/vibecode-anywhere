# Choosing and setting up the host

The host is the **always-on** machine your agent runs on. Since v2 it can be a VPS, a workstation, a mini PC, a laptop kept plugged in, a Mac mini or a Raspberry Pi, running **Linux, macOS or Windows**. For a VPS, use Ubuntu.

[Tiếng Việt](HOSTS.md) · [README](../README.en.md)

## 1. Pick a machine
| Kind (`HOST_KIND`) | OS | Good for | Pros | Cons |
|---|---|---|---|---|
| `vps` | **Ubuntu 22.04 / 24.04** | Long trips, no worries about home power or internet | Always online; rebuild in 45 min if it dies | Monthly cost; no GPU |
| `workstation` | Linux, Windows, macOS | You already own a strong PC at home or the office | Powerful, free, your full environment | Home power/internet outages; may be shared |
| `minipc` | Linux, Windows | A small, low-power box running 24/7 | 6–15 W, quiet, cheap | Usually 8–16 GB RAM |
| `laptop` | Linux, Windows, macOS | An old laptop left at home | Its battery is a small built-in UPS | Heat; a closed MacBook needs an external display |
| `mac` | macOS | You have a Mac mini / Mac Studio | Very efficient; official Codex path via the ChatGPT app | Needs automatic login |
| `sbc` | Raspberry Pi OS 64-bit, Ubuntu | Editing only, builds on CI | Cheap, ~5 W | Weak: use `PROFILE="small"`, boot from SSD instead of an SD card |

RAM size is chosen with `PROFILE` (`small` / `medium` / `large` / `auto`), independent of the machine kind.

## 2. How each agent stays online, per OS
| | Linux | macOS | Windows |
|---|---|---|---|
| **Antigravity** | systemd service, back after reboot even with nobody logged in (bootstrap enables linger) | `agy remote-control start` registers with the OS; needs **automatic login** | `agy remote-control start` registers with Windows; needs **automatic sign-in** |
| **Claude Code** | tmux `claude-rc`; back after reboot with `remote.sh autostart claude` (systemd) | tmux + LaunchAgent (`remote.sh autostart claude`) | minimized window; back at sign-in via a Scheduled Task (`remote.sh autostart claude`) |
| **Codex** | a Mac/Windows ChatGPT desktop app opens this host over SSH; or SSH + tmux | **the ChatGPT desktop app is the official host** | **the ChatGPT desktop app is the official host** |

## 3. Setup per OS
### Linux: VPS, workstation, mini PC, laptop, Raspberry Pi
```bash
sudo apt-get update && sudo apt-get install -y git
git clone https://github.com/tsennguyen/vibecode-anywhere ~/vibecode-anywhere && cd ~/vibecode-anywhere
./bootstrap.sh
```
- Supported: Ubuntu, Debian and their family (Mint, Pop!_OS, Raspberry Pi OS 64-bit). On Fedora/Arch, install the tools yourself, then use `sync.sh` / `install-deps.sh` as usual.
- Home machines: bootstrap installs `openssh-server`. With `HOST_KIND=laptop`, closing the lid no longer suspends the machine (after the next reboot).
- Ubuntu Desktop works too: the agents run in the background with nobody logged in.

### macOS: Mac mini, Mac Studio, MacBook
```bash
xcode-select --install          # if git is missing
git clone https://github.com/tsennguyen/vibecode-anywhere ~/vibecode-anywhere && cd ~/vibecode-anywhere
./bootstrap.sh
```
- Installs everything through Homebrew. Turns off sleep, makes the Mac boot again after a power cut (`pmset autorestart 1`), and turns on Remote Login (SSH).
- Docker: **colima** by default (headless). For Docker Desktop, set `DOCKER_ON_MAC="desktop"`.
- **Required:** System Settings → Users & Groups → **Automatically log in as…** Without it, the agents don't come back after a reboot. This setting is **unavailable while FileVault is on**, so you trade disk encryption for unattended recovery (see section 4).
- A closed MacBook stays awake only with power **and** an external display (Apple limitation). Leaving the lid open is simplest.

### Windows: workstation, mini PC, laptop (Windows 10 22H2+ / 11)
Open a **normal** PowerShell (not "Run as administrator"), signed in as the account the agents will run under:
```powershell
winget install --id Git.Git -e          # then open a new PowerShell window
git clone https://github.com/tsennguyen/vibecode-anywhere $HOME\vibecode-anywhere
cd $HOME\vibecode-anywhere
powershell -ExecutionPolicy Bypass -File .\bootstrap.ps1
```
The script asks for admin rights (UAC) **once**, for the system part: winget, power settings, Windows Update, OpenSSH. Agents, npm globals and rules then install as you, so they land in your own profile. Afterwards, use `.\vibe.ps1 <command>`, e.g. `.\vibe.ps1 sync` or `.\vibe.ps1 doctor`. If you prefer Git Bash, `./sync.sh` works there too.

What `bootstrap.ps1` does:
- Installs with winget only what the config selects: Git, Node LTS, uv, OpenJDK, Docker Desktop, gh, Tailscale, the agents.
- Turns off sleep and hibernation on AC power. On a laptop, closing the lid does nothing.
- **Blocks automatic Windows Update reboots** while you are signed in (`WINDOWS_BLOCK_AUTO_REBOOT=1`). Updates still install; the reboot waits for you.
- Enables the **OpenSSH Server** with Git Bash as the shell, so the RESCUE commands work as written. For admin accounts, Windows reads SSH keys from `C:\ProgramData\ssh\administrators_authorized_keys`; bootstrap copies `~\.ssh\authorized_keys` there (add your key, then re-run bootstrap).
- Sets `git config core.longpaths true`, because `node_modules` paths often exceed 260 characters.

To make everything come back after a power cut:
1. BIOS/UEFI: set **Restore on AC Power Loss = Power On**.
2. Make Windows sign in automatically: `winget install Microsoft.Sysinternals.Autologon`, then run Autologon (it stores the password encrypted in the LSA).
3. Run `.\vibe.ps1 remote autostart claude` if you use Claude.

**WSL2 option:** if you want a Linux environment on the Windows box, install Ubuntu in WSL2, enable systemd (`/etc/wsl.conf` → `[boot]` `systemd=true`, then `wsl --shutdown`), and follow the Linux steps inside WSL. Note that WSL stops when nothing keeps it running, and SSH into WSL has to go through Windows. Running `bootstrap.ps1` natively on Windows is the simpler choice.

## 4. Checklist for home machines (workstation, mini PC, laptop, Mac, Pi)
- [ ] **Power back on by itself:** BIOS `Restore on AC Power Loss = Power On` / Mac: `pmset autorestart 1` (done by bootstrap) / a Pi boots whenever it gets power.
- [ ] **Automatic login** (Windows, macOS) so the agents come back after a reboot. Trade-off: anyone with physical access gets your session. Keep the machine somewhere safe.
- [ ] **A small UPS** (500–1000 VA) for the machine and the router, so a brownout doesn't cost you work.
- [ ] **Wired Ethernet** rather than Wi-Fi when possible.
- [ ] **Tailscale** (`TOOLS+=(tailscale)`) to SSH from the phone into a machine behind a router, with **no port forwarding**. Remote control for all three agents uses outbound connections only, so it needs no open ports either.
- [ ] **No sleep:** bootstrap sets this. Re-check after major OS updates.
- [ ] **Shared machine** (family, coworkers): set `HOST_SHARED=1` so the agent stays away from other people's apps and files. A separate user account for the agent is even better.
- [ ] **Test once before you leave:** pull the plug → plug it back in → wait 3 min. Does the phone still see the machine? If not, see RESCUE §1.

## 5. Quick recommendations
- **Long trip, must not fail:** Ubuntu VPS + Antigravity (primary) + Claude (backup).
- **Mac mini at home:** make it the host. Codex works officially through the ChatGPT app, with Antigravity and Claude alongside.
- **Strong Windows PC at home:** `bootstrap.ps1` + Tailscale + Autologon. Watch out for Windows Update.
- **Lowest budget:** Raspberry Pi 5 8 GB + SSD, `PROFILE="small"`, heavy builds on CI.

---
<sub>[vibecode-anywhere](https://github.com/tsennguyen/vibecode-anywhere) — © 2026 Nguyễn Việt Thành, MIT.</sub>
