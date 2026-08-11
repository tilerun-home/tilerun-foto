[CmdletBinding()]
param(
    [string]$NasHost = "192.168.1.2",
    [string]$NasUser = "Nathalie"
)

$ErrorActionPreference = "Stop"
$ssh = Get-Command "ssh.exe" -ErrorAction SilentlyContinue
if (-not $ssh) {
    throw "OpenSSH (ssh.exe) is niet gevonden."
}

$pythonFile = Join-Path $PSScriptRoot "cloudflare-sso-audit.py"
$shellFile = Join-Path $PSScriptRoot "audit-cloudflare-google-sso.sh"
if (-not (Test-Path -LiteralPath $pythonFile) -or -not (Test-Path -LiteralPath $shellFile)) {
    throw "De lokale SSO-controlebestanden ontbreken."
}

$target = "$NasUser@$NasHost"
Write-Host "De twee controlebestanden worden via een beveiligde SSH-opdracht op de NAS geplaatst." -ForegroundColor Green
Write-Host "Er wordt niets naar GitHub gepubliceerd." -ForegroundColor Yellow

$pythonBase64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($pythonFile))
$shellBase64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($shellFile))
$remoteRoot = "/volume1/docker/projects/test-webapp/immich"
$remoteCommand = "printf '%s' '$pythonBase64' | base64 -d | sudo tee '$remoteRoot/scripts/cloudflare-sso-audit.py' >/dev/null && printf '%s' '$shellBase64' | base64 -d | sudo tee '$remoteRoot/scripts/audit-cloudflare-google-sso.sh' >/dev/null && sudo chmod 755 '$remoteRoot/scripts/cloudflare-sso-audit.py' '$remoteRoot/scripts/audit-cloudflare-google-sso.sh' && sudo sh '$remoteRoot/scripts/audit-cloudflare-google-sso.sh'"
& $ssh.Source -tt $target $remoteCommand
if ($LASTEXITCODE -ne 0) {
    throw "De Cloudflare SSO-controle op de NAS is mislukt."
}
