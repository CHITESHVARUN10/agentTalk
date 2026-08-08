param(
  [switch]$NoInstaller
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Set-Location $Root

Write-Host "==> Building Rust core (Windows, Vulkan)..." -ForegroundColor Cyan
Push-Location rust-core
cargo build --release --features vulkan
if ($LASTEXITCODE -ne 0) { throw "cargo build failed" }
Pop-Location

Write-Host "==> Building Tauri app..." -ForegroundColor Cyan
Push-Location windows/src-tauri
# Requires: cargo install tauri-cli  OR  npm i -D @tauri-apps/cli
# This scaffold uses cargo tauri; fallback to cargo build if Tauri not installed
$hasTauri = Get-Command cargo-tauri -ErrorAction SilentlyContinue
if ($hasTauri) {
  cargo tauri build
} else {
  Write-Host "  cargo-tauri not found — building Tauri wrapper via cargo build (no bundle)" -ForegroundColor Yellow
  cargo build --release
}
if ($LASTEXITCODE -ne 0) { throw "tauri build failed" }
Pop-Location

if ($NoInstaller) {
  Write-Host "==> Skipping installer (-NoInstaller)" -ForegroundColor Yellow
  exit 0
}

Write-Host "==> Building Inno Setup installer..." -ForegroundColor Cyan
$iscc = Get-Command ISCC.exe -ErrorAction SilentlyContinue
if (-not $iscc) {
  $iscc = Get-ChildItem "C:\Program Files*\Inno Setup*\ISCC.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
}
if ($iscc) {
  & $iscc.Path windows/installer/installer.iss
  if ($LASTEXITCODE -ne 0) { throw "ISCC failed" }
  Write-Host "==> Installer: dist/AgentTalk-*-x64-setup.exe" -ForegroundColor Green
} else {
  Write-Host "  ISCC.exe not found — install Inno Setup 6 (https://jrsoftware.org/isinfo.php)" -ForegroundColor Yellow
  Write-Host "  Installer step skipped. Built binaries are in windows/src-tauri/target/release/" -ForegroundColor Yellow
}
