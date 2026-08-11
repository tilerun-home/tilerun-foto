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

$target = "$NasUser@$NasHost"
$python = @'
import json
import os
from tilerun_access.config import AccessConfig
from tilerun_access.db import configure
from tilerun_access.foto_sync import desired_users
from tilerun_access.sync import get_client

config = AccessConfig.from_env(os.environ.get("TILERUN_STATE_DB_PATH", "/state/tilerun_web.db"))
configure(config.state_db_path)
print("LOKALE FOTO-TOEGANG")
print(json.dumps(desired_users(), ensure_ascii=False, indent=2))
print("CLOUDFLARE FOTO-POLICIES")
client = get_client(config)
apps = [app for app in client.list_applications() if "foto" in str(app.get("name", "")).lower()]
result = []
for app in apps:
    policies = client.list_policies(str(app.get("id", ""))) if app.get("id") else []
    result.append({
        "application": app.get("name"),
        "type": app.get("type"),
        "domain": app.get("domain"),
        "policies": [
            {
                "name": policy.get("name"),
                "decision": policy.get("decision"),
                "include": policy.get("include", []),
                "exclude": policy.get("exclude", []),
                "require": policy.get("require", []),
            }
            for policy in policies
        ],
    })
print(json.dumps(result, ensure_ascii=False, indent=2))
'@
$encodedPython = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($python))
$remote = "DOCKER=/var/packages/ContainerManager/target/usr/bin/docker; [ -x `$DOCKER ] || DOCKER=/var/packages/Docker/target/usr/bin/docker; echo '$encodedPython' | base64 -d | sudo `$DOCKER exec -i tilerun-access-worker python -"

Write-Host "De berekende TileRun Foto-toegang wordt alleen-lezen gecontroleerd." -ForegroundColor Green
Write-Host "Er wordt niets gewijzigd en niets naar GitHub gepubliceerd." -ForegroundColor Yellow
& $ssh.Source -o ConnectTimeout=10 -tt $target $remote
if ($LASTEXITCODE -ne 0) {
    throw "De Foto-gebruikerscontrole is mislukt."
}
