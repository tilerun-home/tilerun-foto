[CmdletBinding()]
param(
    [string]$Audience = "",
    [string]$NasHost = "192.168.1.2",
    [string]$NasUser = "Nathalie"
)

$ErrorActionPreference = "Stop"
if ($Audience -and $Audience -notmatch '^[A-Za-z0-9_-]{32,128}$') {
    throw "De opgegeven Cloudflare Access-audience is ongeldig."
}
$ssh = Get-Command "ssh.exe" -ErrorAction SilentlyContinue
if (-not $ssh) {
    throw "OpenSSH (ssh.exe) is niet gevonden."
}

$target = "$NasUser@$NasHost"
$remoteRoot = "/volume1/docker/projects/test-webapp/immich"
$shellFile = Join-Path $PSScriptRoot "enable-cloudflare-access-web-login.sh"
$pythonFile = Join-Path $PSScriptRoot "configure-cloudflare-access-web-login.py"
if (-not (Test-Path -LiteralPath $shellFile) -or -not (Test-Path -LiteralPath $pythonFile)) {
    throw "Het activeringsscript ontbreekt."
}
$shellBase64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($shellFile))
$pythonBase64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($pythonFile))
$remoteCommand = "printf '%s' '$shellBase64' | base64 -d | sudo tee '$remoteRoot/scripts/enable-cloudflare-access-web-login.sh' >/dev/null && printf '%s' '$pythonBase64' | base64 -d | sudo tee '$remoteRoot/scripts/configure-cloudflare-access-web-login.py' >/dev/null && sudo chmod 700 '$remoteRoot/scripts/enable-cloudflare-access-web-login.sh' '$remoteRoot/scripts/configure-cloudflare-access-web-login.py' && cd '$remoteRoot' && sudo sh scripts/enable-cloudflare-access-web-login.sh '$Audience'"

Write-Host "De smalle Cloudflare Access-loginroute wordt veilig aangemaakt of gecontroleerd." -ForegroundColor Green
Write-Host "Er wordt niets naar GitHub gepubliceerd." -ForegroundColor Yellow
& $ssh.Source -tt $target $remoteCommand
if ($LASTEXITCODE -ne 0) {
    throw "De TileRun Access-weblogin kon niet worden geactiveerd."
}

Write-Host "TileRun Access-weblogin is geactiveerd. Test nu via https://tilerun.net." -ForegroundColor Green
