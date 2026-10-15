# Rescue from a phone

Use this when the agent on your phone stops working. Have these on the phone in advance: an SSH app (**Termius** iOS/Android, **Blink** iOS, **JuiceSSH** Android) with the host saved, and the bundle passphrase in your password manager.

Replace `~/vibecode-anywhere` with where you cloned the kit, `my-vps` with your `HOST_NAME`, and `~/code` with your `HOST_ROOT`.


> **Windows host:** SSH lands in Git Bash (set up by `bootstrap.ps1`), so the commands below work as written; or use PowerShell `.\vibe.ps1 doctor`. No tmux there: Claude runs in a minimized window, so restart it with `~/vibecode-anywhere/remote.sh start claude`. For §3, use `~/vibecode-anywhere/doctor.sh` instead of `free`/`ps`. If the machine is unreachable after a power cut, check Autologon and the BIOS "Restore on AC power loss" setting.
>
> **macOS host:** same as Linux (tmux comes from Homebrew). If the agents don't come back after a reboot, check that **automatic login** is on (System Settings → Users & Groups). Codex: reopen the ChatGPT app.
>
> **Home machine:** SSH over Tailscale (`tailscale ip -4` shows the address). If the router or home power is down, someone at home has to bring it back.

## §0. No idea what's wrong → run this first
```bash
~/vibecode-anywhere/doctor.sh
```
Every **FAIL/WARN** line ends with the `§` section to follow.

## §1. The phone can't see the machine / session
**Antigravity:**
```bash
agy remote-control status
agy remote-control start --name my-vps
journalctl --user -u antigravity-cli-daemon -n 40 --no-pager
```
If the log shows a sign-in error, run `agy`, open the link on the phone, paste the code, type `/exit`, then `start` again.

**Claude Code:**
```bash
tmux ls
~/vibecode-anywhere/remote.sh start claude
tmux attach -t claude-rc          # see what it says; leave with Ctrl+b then d
```
If it says "requires a claude.ai subscription", an API key is in use → `unset ANTHROPIC_API_KEY`, run `claude` → `/login`.

**Codex:** `~/vibecode-anywhere/remote.sh start codex`, then connect through the ChatGPT desktop app or with `tmux attach -t codex`.

## §2. The daemon is completely broken → run the agent in tmux
```bash
tmux new -As agent
cd ~/code && agy --remote-control        # or: claude remote-control --name my-vps   |   codex
```
The agent prints a link → open it on the phone. To leave Termius but keep the session: **Ctrl+b**, release, then **d**. To come back later: `tmux attach -t agent`.

## §3. Slow, frozen, out of RAM
```bash
free -h && ps -eo rss,comm --sort=-rss | head -6
pkill -f "next dev"; pkill -f "vite"; pkill -f "turbo run dev"; pkill -f playwright; docker ps -q | xargs -r docker stop
```

## §4. Disk full
```bash
df -h / && du -sh ~/.cache ~/code/* 2>/dev/null | sort -h | tail -8
docker system prune -af; npm cache clean --force; pnpm store prune; rm -rf ~/.cache/pip ~/.cache/ms-playwright/*/
```
(If you need Playwright again later, reinstall it with `install-deps.sh`.)

## §5. Push all work to GitHub now (before anything risky)
```bash
~/vibecode-anywhere/save-all.sh
```
Changes on a protected branch (`PROTECTED_BRANCHES`) move to a new `wip/rescue-<time>` branch. It never pushes straight to the main branch and never force-pushes.

## §6. GitHub not signed in / push rejected / Codex signed out
```bash
gh auth login --web --git-protocol https && gh auth setup-git
codex login --device-auth
```
Both print a link and a code → open the link on the phone.

## §7. Backup agent
Install a second agent (`AGENTS=(antigravity claude)`) so you still have one if the main agent breaks: `~/vibecode-anywhere/remote.sh start claude`.

## §8. VPS about to expire / suspended
Renew it on your provider's page. Run §5 first. A machine that expires without renewal may be deleted for good.

## §9. Machine wiped → rebuild (~45 min)
Get a new machine and redo the README section "Set up the host". Code is on GitHub, secrets are in your `vibecode-out` copy on a cloud drive, and the passphrase is on your phone.

## Never type
`reboot` / `shutdown` (unless you are sure the machine comes back on its own), `agy remote-control stop`, `ufw enable`, edits to `/etc/ssh/sshd_config`, `rm -rf ~/code`, `git push --force`. These can lock you out of the machine or lose your code.

---
<sub>[vibecode-anywhere](https://github.com/tsennguyen/vibecode-anywhere) — © 2026 Nguyễn Việt Thành, MIT.</sub>
