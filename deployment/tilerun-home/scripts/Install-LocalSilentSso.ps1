[CmdletBinding()]
param(
    [string]$NasHost = "192.168.1.2",
    [string]$NasUser = "Nathalie"
)

$ErrorActionPreference = "Stop"
$scp = Get-Command "scp.exe" -ErrorAction SilentlyContinue
$ssh = Get-Command "ssh.exe" -ErrorAction SilentlyContinue
if (-not $scp -or -not $ssh) {
    throw "OpenSSH (ssh.exe en scp.exe) is niet gevonden."
}

$deploymentRoot = Split-Path -Parent $PSScriptRoot
$serverArchive = Join-Path $deploymentRoot "local-overlay\server-dist.tar.gz"
$webArchive = Join-Path $deploymentRoot "local-overlay\web-build.tar.gz"
$deployScript = Join-Path $PSScriptRoot "deploy-local-overlay.sh"
$composeFile = Join-Path $deploymentRoot "compose.yml"
$familyDeployScript = Join-Path $PSScriptRoot "deploy-family-sync.sh"
$workspaceRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $deploymentRoot))
$centralSyncFile = Join-Path $workspaceRoot ".codex-work\tilerun-current-before-v2\app\tilerun_access\foto_sync.py"
$centralProfilesFile = Join-Path $workspaceRoot ".codex-work\tilerun-current-before-v2\app\tilerun_access\profiles.py"
$centralApiFile = Join-Path $workspaceRoot ".codex-work\tilerun-current-before-v2\app\tilerun_access\api.py"
if (
    -not (Test-Path -LiteralPath $serverArchive) -or
    -not (Test-Path -LiteralPath $webArchive) -or
    -not (Test-Path -LiteralPath $deployScript) -or
    -not (Test-Path -LiteralPath $composeFile) -or
    -not (Test-Path -LiteralPath $familyDeployScript) -or
    -not (Test-Path -LiteralPath $centralSyncFile) -or
    -not (Test-Path -LiteralPath $centralProfilesFile) -or
    -not (Test-Path -LiteralPath $centralApiFile)
) {
    throw "De lokaal gebouwde TileRun Foto-bestanden ontbreken."
}

$target = "$NasUser@$NasHost"
$remoteRoot = "/volume1/docker/projects/test-webapp/immich"
$remoteStaging = "$remoteRoot/.local-upload"

Write-Host "TileRun Foto wordt als lokale validatieversie naar de NAS gestuurd." -ForegroundColor Green
Write-Host "Er wordt niets naar GitHub gepubliceerd." -ForegroundColor Yellow
Write-Host "SSH, sudo en kopieren kunnen om het NAS-wachtwoord vragen." -ForegroundColor Yellow

$prepareCommand = "sudo mkdir -p '$remoteStaging' && sudo chown '$NasUser' '$remoteStaging' && sudo chmod 700 '$remoteStaging'"
$prepared = $false
for ($attempt = 1; $attempt -le 3 -and -not $prepared; $attempt++) {
    & $ssh.Source -o ConnectTimeout=10 -o ServerAliveInterval=15 -o ServerAliveCountMax=2 -tt $target $prepareCommand
    if ($LASTEXITCODE -eq 0) {
        $prepared = $true
    } elseif ($attempt -lt 3) {
        Write-Host "De SSH-verbinding werd onderbroken. Nieuwe poging $($attempt + 1) van 3..." -ForegroundColor Yellow
        Start-Sleep -Seconds 2
    }
}
if (-not $prepared) {
    throw "De tijdelijke uploadmap op de NAS kon niet veilig worden voorbereid. Controleer of SSH-aanmelding voor $NasUser op $NasHost werkt."
}

& $scp.Source -O $serverArchive $webArchive $deployScript $composeFile $familyDeployScript $centralSyncFile $centralProfilesFile $centralApiFile "${target}:${remoteStaging}/"
if ($LASTEXITCODE -ne 0) {
    throw "De lokale TileRun Foto-build kon niet naar de NAS worden gekopieerd."
}

$deployCommand = "sudo sh '$remoteStaging/deploy-family-sync.sh'"
& $ssh.Source -tt $target $deployCommand
if ($LASTEXITCODE -ne 0) {
    throw "De lokale TileRun Foto-validatieversie kon niet worden gestart."
}

Write-Host "De lokale gezinsvalidatieversie draait." -ForegroundColor Green
Write-Host "Controleer TileRun Foto bij Albums; er is niets naar GitHub gepubliceerd." -ForegroundColor Yellow
