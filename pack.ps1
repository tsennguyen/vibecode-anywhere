# vibecode-anywhere - pack.ps1: kept for v1 users. Same as: .\vibe.ps1 pack
#   powershell -ExecutionPolicy Bypass -File .\pack.ps1
# (c) 2026 Nguyen Viet Thanh (Nguyễn Việt Thành) - MIT License.
& (Join-Path $PSScriptRoot "vibe.ps1") pack @args
exit $LASTEXITCODE
