# vibecode-anywhere - bootstrap.ps1: one-time setup of a WINDOWS host (workstation, mini PC, laptop kept on).
# Windows 10 22H2+ / Windows 11, x64 or ARM64. Run it from a NORMAL PowerShell (not "Run as administrator"),
# inside the kit folder, with the account the agents will run under:
#
#   powershell -ExecutionPolicy Bypass -File .\bootstrap.ps1
#
# Phase "machine" asks for admin rights once (UAC) and handles system-wide things: winget packages, power
# settings, Windows Update reboot policy, OpenSSH server. Phase "user" then runs as YOU: coding agents,
# npm globals, environment variables, agent rules - so they land in your profile, not an admin's.
# Idempotent: re-run after any failure. Afterwards use .\vibe.ps1 <command> (or Git Bash).
# (c) 2026 Nguyen Viet Thanh (Nguyễn Việt Thành) - MIT License.
param([ValidateSet("all", "machine", "user")][string]$Phase = "all")
$ErrorActionPreference = "Continue"
$Failed = New-Object System.Collections.Generic.List[string]

function Step($t) { Write-Host "`n== $t" -ForegroundColor Cyan }
function Warn($t) { Write-Host "  WARN $t" -ForegroundColor Yellow }
function Have($c) { [bool](Get-Command $c -ErrorAction SilentlyContinue) }
function Is-Admin { ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator) }
function Refresh-Path {
  $env:Path = [Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [Environment]::GetEnvironmentVariable("Path", "User") +
              ";$env:USERPROFILE\.local\bin;$env:LOCALAPPDATA\agy\bin;$env:APPDATA\npm"
}
function WG($id, $label) {
  Write-Host "  winget: $label ($id)"
  winget install --id $id -e --silent --accept-package-agreements --accept-source-agreements --disable-interactivity | Out-Host
  if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne -1978335189) {   # -1978335189 = already installed / no update
    Warn "${label}: winget exit $LASTEXITCODE"; $Failed.Add($label)
  }
  Refresh-Path
}
function Try-Run($label, [scriptblock]$block) {
  try { & $block } catch { Warn "$label failed: $($_.Exception.Message)"; $Failed.Add($label) }
}
function Find-Bash {
  @("$env:ProgramFiles\Git\bin\bash.exe", "$env:LOCALAPPDATA\Programs\Git\bin\bash.exe") |
    Where-Object { Test-Path $_ } | Select-Object -First 1
}
function Read-Config($bash) {
  $c = @{}
  & $bash "scripts/print-config.sh" | ForEach-Object {
    $i = $_.IndexOf("="); if ($i -gt 0) { $c[$_.Substring(0, $i)] = $_.Substring($i + 1).Trim() }
  }
  if (-not $c["HOST_NAME"]) { Write-Host "Could not read config/hub.conf (see the error above)." -ForegroundColor Red; exit 1 }
  return $c
}
function Report-Failures {
  if ($Failed.Count -gt 0) { Warn ("some steps failed: " + ($Failed -join ", ") + " - fix the cause and re-run .\bootstrap.ps1") }
}

Set-Location $PSScriptRoot
Refresh-Path

# ════════════════════════════════════════════════════════════════════════════
function Machine-Phase {
  Step "winget"
  if (-not (Have winget)) { Write-Host "winget is missing. Install 'App Installer' from the Microsoft Store, then re-run." -ForegroundColor Red; exit 1 }

  Step "Git for Windows (provides Git Bash, which runs the rest of the kit)"
  if (-not (Have git)) { WG "Git.Git" "Git for Windows" }
  $bash = Find-Bash
  if (-not $bash) { Write-Host "Git Bash not found after install. Re-run .\bootstrap.ps1 from a new PowerShell." -ForegroundColor Red; exit 1 }
  git config --system core.longpaths true       # node_modules paths exceed 260 chars

  $cfg = Read-Config $bash
  $agents = $cfg["AGENTS"] -split " "; $stacks = $cfg["STACKS"] -split " "; $tools = $cfg["TOOLS"] -split " "
  Write-Host "  Host: $($cfg['HOST_NAME']) - $($cfg['HOST_KIND_LABEL']), profile $($cfg['PROFILE_LABEL'])"

  Step "Stay awake on AC power (no sleep, no hibernate)"
  powercfg /change standby-timeout-ac 0
  powercfg /change hibernate-timeout-ac 0
  powercfg /change monitor-timeout-ac 10
  powercfg /hibernate off
  if ($cfg["HOST_KIND"] -eq "laptop") {
    powercfg /setacvalueindex SCHEME_CURRENT SUB_BUTTONS LIDACTION 0    # closing the lid does nothing on AC
    powercfg /setactive SCHEME_CURRENT
    Write-Host "  laptop: lid close ignored while plugged in"
  }

  if ($cfg["WINDOWS_BLOCK_AUTO_REBOOT"] -eq "1") {
    Step "Windows Update: no automatic reboot while you are signed in"
    $au = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU"
    New-Item -Path $au -Force | Out-Null
    New-ItemProperty -Path $au -Name NoAutoRebootWithLoggedOnUsers -Value 1 -PropertyType DWord -Force | Out-Null
    Write-Host "  Updates still install; the reboot waits for you. Reboot yourself once a month when home."
  }

  if ($cfg["WANT_SSH"] -eq "1") {
    Step "OpenSSH server (your rescue line from the phone)"
    Try-Run "openssh" {
      $cap = Get-WindowsCapability -Online -Name "OpenSSH.Server*" | Select-Object -First 1
      if ($cap.State -ne "Installed") { Add-WindowsCapability -Online -Name $cap.Name | Out-Null }
      Set-Service -Name sshd -StartupType Automatic; Start-Service sshd
      if ($cfg["WINDOWS_SSH_SHELL"] -eq "bash") {
        New-ItemProperty -Path "HKLM:\SOFTWARE\OpenSSH" -Name DefaultShell -Value $bash -PropertyType String -Force | Out-Null
        New-ItemProperty -Path "HKLM:\SOFTWARE\OpenSSH" -Name DefaultShellCommandOption -Value "-c" -PropertyType String -Force | Out-Null
        Write-Host "  SSH sessions open Git Bash, so the RESCUE commands work as written."
      }
      # Accounts in the Administrators group read keys from ProgramData, not from ~/.ssh/authorized_keys.
      $userKeys = Join-Path $env:USERPROFILE ".ssh\authorized_keys"
      if (Test-Path $userKeys) {
        $adminKeys = "$env:ProgramData\ssh\administrators_authorized_keys"
        $existing = if (Test-Path $adminKeys) { Get-Content $adminKeys } else { @() }
        Get-Content $userKeys | Where-Object { $_ -and ($existing -notcontains $_) } | Add-Content -Path $adminKeys -Encoding ascii
        icacls $adminKeys /inheritance:r /grant "*S-1-5-32-544:F" /grant "*S-1-5-18:F" | Out-Null
        Write-Host "  copied your ~/.ssh/authorized_keys into administrators_authorized_keys (admin accounts need it)"
      } else {
        Write-Host "  Key login: put your public key in $env:USERPROFILE\.ssh\authorized_keys and re-run (password login works meanwhile)."
      }
      Write-Host "  Reach it from outside your home with Tailscale (TOOLS+=(tailscale)) - never port-forward 22."
    }
  }

  $needNode = ($stacks -contains "node") -or ($stacks -contains "pnpm") -or ($agents -contains "codex") -or ($tools -contains "vercel")
  if ($needNode -and -not (Have node)) { Step "Node.js LTS"; WG "OpenJS.NodeJS.LTS" "Node.js LTS" }
  if ($stacks -contains "pnpm" -and (Have corepack)) { Step "corepack (pnpm)"; Try-Run "corepack" { corepack enable } }
  if ($stacks -contains "bun")       { Step "Bun"; if (-not (Have bun)) { WG "Oven-sh.Bun" "Bun" } }
  if ($stacks -contains "python-uv") { Step "uv (Python)"; if (-not (Have uv)) { WG "astral-sh.uv" "uv" } }
  if ($stacks -contains "java")      { Step "JDK $($cfg['JAVA_VERSION'])"; WG "Microsoft.OpenJDK.$($cfg['JAVA_VERSION'])" "OpenJDK $($cfg['JAVA_VERSION'])" }
  if ($stacks -contains "go")        { Step "Go"; if (-not (Have go)) { WG "GoLang.Go" "Go" } }
  if ($stacks -contains "rust")      { Step "Rust"; if (-not (Have rustup)) { WG "Rustlang.Rustup" "Rustup" } }
  if ($stacks -contains "docker") {
    Step "Docker Desktop (uses WSL2; may ask for a reboot)"
    if (-not (Have docker)) { WG "Docker.DockerDesktop" "Docker Desktop" }
    Write-Host "  Open Docker Desktop once: accept the terms, enable 'Start Docker Desktop when you sign in'."
  }
  if ($tools -contains "gh" -and -not (Have gh)) { Step "GitHub CLI"; WG "GitHub.cli" "GitHub CLI" }
  if ($tools -contains "tailscale" -and -not (Have tailscale)) { Step "Tailscale"; WG "Tailscale.Tailscale" "Tailscale"; Write-Host "  Open Tailscale and sign in; it starts with Windows." }
  Report-Failures
}

# ════════════════════════════════════════════════════════════════════════════
function User-Phase {
  $bash = Find-Bash
  if (-not $bash) { Write-Host "Git Bash not found - the machine phase did not finish. Re-run .\bootstrap.ps1" -ForegroundColor Red; exit 1 }
  $cfg = Read-Config $bash
  $agents = $cfg["AGENTS"] -split " "; $stacks = $cfg["STACKS"] -split " "; $tools = $cfg["TOOLS"] -split " "
  New-Item -ItemType Directory -Force -Path $cfg["HOST_ROOT_WIN"] | Out-Null

  Set-ExecutionPolicy -Scope CurrentUser RemoteSigned -Force   # npm/agent .ps1 shims need this
  if ($stacks -contains "pnpm") {
    Step "pnpm"
    Try-Run "pnpm" { if (Have corepack) { corepack prepare pnpm@latest --activate } else { npm install -g pnpm } }
  }
  if ($tools -contains "vercel" -and -not (Have vercel)) { Step "Vercel CLI"; Try-Run "vercel" { npm install -g vercel } }
  if ($tools -contains "supabase") { Step "Supabase CLI"; Write-Host "  Windows: install with Scoop -> scoop bucket add supabase https://github.com/supabase/scoop-bucket.git; scoop install supabase" }

  if ($agents -contains "antigravity") {
    Step "Antigravity CLI (agy)"
    if (-not (Have agy)) { Try-Run "antigravity" { Invoke-RestMethod https://antigravity.google/cli/install.ps1 | Invoke-Expression } }
    Refresh-Path; if (Have agy) { agy --version }
  }
  if ($agents -contains "claude") {
    Step "Claude Code (claude)"
    if (-not (Have claude)) { Try-Run "claude" { Invoke-RestMethod https://claude.ai/install.ps1 | Invoke-Expression } }
    Refresh-Path; if (Have claude) { claude --version }
  }
  if ($agents -contains "codex") {
    Step "OpenAI Codex CLI + ChatGPT desktop app"
    if (-not (Have codex)) { Try-Run "codex" { npm install -g @openai/codex } }
    Write-Host "  The ChatGPT desktop app is the official phone remote host for Codex on Windows:"
    Write-Host "  install it from the Microsoft Store (or chatgpt.com/download), sign in, then"
    Write-Host "  Settings -> Connections -> 'Control this Mac or PC' -> scan the QR code with your phone."
  }

  Step "Defaults for the agent's shells"
  [Environment]::SetEnvironmentVariable("NODE_OPTIONS", "--max-old-space-size=$($cfg['NODE_HEAP_MB'])", "User")
  if ($cfg["GIT_NAME"] -and $cfg["GIT_EMAIL"]) { git config --global user.name $cfg["GIT_NAME"]; git config --global user.email $cfg["GIT_EMAIL"] }
  git config --global init.defaultBranch main
  git config --global pull.ff only

  Step "Agent rules"
  & $bash "scripts/render-rules.sh"

  Write-Host ""
  Report-Failures
  @"
========================================================================
 Windows bootstrap done. Open a NEW PowerShell (normal) in this folder, then:
   gh auth login --web --git-protocol https; gh auth setup-git
   .\vibe.ps1 sync            (or: .\vibe.ps1 sync --clone-only)
   .\vibe.ps1 install-deps
   .\vibe.ps1 remote login;  .\vibe.ps1 remote start;  .\vibe.ps1 doctor

 So everything comes back after a power cut or reboot:
   - BIOS/UEFI: "Restore on AC power loss" = Power On
   - Windows must sign in by itself: Sysinternals Autologon (winget install Microsoft.Sysinternals.Autologon)
   - .\vibe.ps1 remote autostart claude   (if you use Claude)
   Trade-offs explained in docs/HOSTS.en.md
========================================================================
"@ | Write-Host
}

# ════════════════════════════════════════════════════════════════════════════
switch ($Phase) {
  "machine" { Machine-Phase; Read-Host "`nMachine setup finished. Press Enter to close this window" | Out-Null }
  "user"    { User-Phase }
  default {
    if (Is-Admin) {
      Warn "running as administrator: user-level parts (agents, npm globals) will install for THIS account."
      Warn "If the agents should run under another account, re-run from that account's normal PowerShell."
      Machine-Phase; User-Phase
    } else {
      Step "Machine setup needs admin rights once - approve the UAC prompt (a second window opens)"
      $p = Start-Process powershell -Verb RunAs -Wait -PassThru `
             -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -Phase machine"
      if (-not $p -or $p.ExitCode -ne 0) { Warn "machine phase did not finish cleanly (exit $($p.ExitCode)) - continuing with the user phase" }
      Refresh-Path
      User-Phase
    }
  }
}
