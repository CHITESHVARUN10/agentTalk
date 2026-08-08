param(
  [Parameter(Mandatory=$true)][string]$Identity,
  [string]$Path = "dist/AgentTalk-*-x64-setup.exe",
  [string]$TimestampUrl = "http://timestamp.digicert.com"
)

$ErrorActionPreference = "Stop"
$files = Get-ChildItem $Path -ErrorAction SilentlyContinue
if (-not $files) { throw "No files matching $Path" }
foreach ($f in $files) {
  Write-Host "Signing $($f.FullName) with $Identity..." -ForegroundColor Cyan
  & signtool sign /fd SHA256 /tr $TimestampUrl /td SHA256 /n $Identity $f.FullName
  if ($LASTEXITCODE -ne 0) { throw "signtool failed for $($f.Name)" }
}
Write-Host "Signed $($files.Count) file(s)." -ForegroundColor Green
