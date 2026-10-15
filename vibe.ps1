# vibecode-anywhere - vibe.ps1: run any kit script from PowerShell on Windows (through Git Bash).
#
#   .\vibe.ps1 pack                 .\vibe.ps1 sync [--clone-only]     .\vibe.ps1 install-deps [--all]
#   .\vibe.ps1 doctor               .\vibe.ps1 save-all                 .\vibe.ps1 remote <login|start|status|autostart> [agent]
#   .\vibe.ps1 config               (print the resolved config)
#
# If scripts are blocked: powershell -ExecutionPolicy Bypass -File .\vibe.ps1 <command>
# Needs Git for Windows (bootstrap.ps1 installs it; or: winget install --id Git.Git -e).
# (c) 2026 Nguyen Viet Thanh (Nguyễn Việt Thành) - MIT License.
$ErrorActionPreference = "Stop"

$cmd = if ($args.Count -gt 0) { $args[0] } else { "help" }
$rest = if ($args.Count -gt 1) { $args[1..($args.Count - 1)] } else { @() }
$map = @{
  "pack" = "pack.sh"; "sync" = "sync.sh"; "install-deps" = "install-deps.sh"; "doctor" = "doctor.sh"
  "save-all" = "save-all.sh"; "remote" = "remote.sh"; "config" = "scripts/print-config.sh"
  "render-rules" = "scripts/render-rules.sh"
}
if (-not $map.ContainsKey($cmd)) {
  Write-Host "usage: .\vibe.ps1 <pack|sync|install-deps|doctor|save-all|remote|config> [args]"; exit 1
}

$candidates = @(
  "$env:ProgramFiles\Git\bin\bash.exe",
  "${env:ProgramFiles(x86)}\Git\bin\bash.exe",
  "$env:LOCALAPPDATA\Programs\Git\bin\bash.exe"
)
$bash = $candidates | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
if (-not $bash) {
  $git = Get-Command git -ErrorAction SilentlyContinue
  if ($git) { $guess = Join-Path (Split-Path (Split-Path $git.Source)) "bin\bash.exe"; if (Test-Path $guess) { $bash = $guess } }
}
if (-not $bash) {
  Write-Host "Git Bash not found. Install Git for Windows: winget install --id Git.Git -e" -ForegroundColor Red
  exit 1
}

Set-Location $PSScriptRoot
& $bash $map[$cmd] @rest
exit $LASTEXITCODE
