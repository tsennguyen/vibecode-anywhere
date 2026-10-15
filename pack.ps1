# vibecode-anywhere — pack.ps1: run pack.sh from Windows PowerShell.
# Needs Git for Windows (https://git-scm.com/download/win): it ships bash, tar and openssl.
# In config/hub.conf write Windows paths the Git Bash way: C:\Users\alice\code -> /c/Users/alice/code
#
#   powershell -ExecutionPolicy Bypass -File .\pack.ps1
#
# (c) 2026 Nguyễn Việt Thành — MIT License.
$ErrorActionPreference = "Stop"

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

$here = $PSScriptRoot -replace '\\', '/'
if ($here -match '^([A-Za-z]):(.*)$') { $here = '/' + $Matches[1].ToLower() + $Matches[2] }
& $bash -lc "cd '$here' && ./pack.sh $($args -join ' ')"
exit $LASTEXITCODE
