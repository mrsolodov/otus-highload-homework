#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$ServerIp = '172.28.19.10',
    [string]$AgentIp = '172.28.19.11',
    [string]$SshUser = 'ubuntu',
    [string]$SshKey = (Join-Path $HOME '.ssh\id_ed25519')
)
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
if (-not (Test-Path -LiteralPath $SshKey -PathType Leaf)) { throw "SSH key not found: $SshKey" }
if ([string]::IsNullOrEmpty($env:PORTAL_PASSWORD)) { throw 'Set PORTAL_PASSWORD in the current PowerShell session.' }
$sshArgs = @('-i', $SshKey, '-o', 'BatchMode=yes', '-o', 'StrictHostKeyChecking=accept-new', '-o', 'ConnectTimeout=10')

function Invoke-Remote([string]$Ip, [string]$Command) {
    & ssh.exe @sshArgs "${SshUser}@${Ip}" $Command
    if ($LASTEXITCODE -ne 0) { throw "Remote command failed on ${Ip}: $Command" }
}

# The nested Proxmox network cannot reliably reach public DNS. Resolve on Windows
# and put the addresses required by the installer and image registries on both VMs.
$downloadHosts = @('get.k3s.io', 'update.k3s.io', 'github.com',
    'release-assets.githubusercontent.com', 'objects.githubusercontent.com',
    'registry.k8s.io', 'registry-1.docker.io', 'auth.docker.io',
    'production.cloudflare.docker.com', 'production.cloudfront.docker.com',
    'archive.ubuntu.com', 'security.ubuntu.com', 'packages.broadcom.com')
foreach ($name in $downloadHosts) {
    $address = Resolve-DnsName $name -Type A -ErrorAction Stop |
        Where-Object { $_.IPAddress } | Select-Object -First 1 -ExpandProperty IPAddress
    if (-not $address) { throw "Could not resolve $name on Windows" }
    foreach ($ip in @($ServerIp, $AgentIp)) {
        Invoke-Remote $ip "sudo sed -i '/[[:space:]]$name`$/d' /etc/hosts; echo '$address $name' | sudo tee -a /etc/hosts >/dev/null"
    }
}

foreach ($ip in @($ServerIp, $AgentIp)) {
    Invoke-Remote $ip 'mkdir -p /tmp/otus-k8s'
    & scp.exe @sshArgs -r (Join-Path $root 'scripts') "${SshUser}@${ip}:/tmp/otus-k8s/"
    if ($LASTEXITCODE -ne 0) { throw "Could not copy scripts to $ip" }
}
& scp.exe @sshArgs -r (Join-Path $root 'manifests') "${SshUser}@${ServerIp}:/tmp/otus-k8s/"
if ($LASTEXITCODE -ne 0) { throw 'Could not copy manifests' }

Invoke-Remote $ServerIp "sudo env SERVER_IP=$ServerIp bash /tmp/otus-k8s/scripts/bootstrap-server.sh"
$token = (& ssh.exe @sshArgs "${SshUser}@${ServerIp}" 'sudo cat /var/lib/rancher/k3s/server/node-token' | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrEmpty($token)) { throw 'Could not read the K3s join token' }
try {
    $token | & ssh.exe @sshArgs "${SshUser}@${AgentIp}" "sudo env SERVER_IP=$ServerIp AGENT_IP=$AgentIp bash /tmp/otus-k8s/scripts/run-agent.sh"
    if ($LASTEXITCODE -ne 0) { throw 'Agent installation failed' }
} finally { $token = $null }

Invoke-Remote $ServerIp 'sudo kubectl wait --for=condition=Ready nodes --all --timeout=180s'
$env:PORTAL_PASSWORD | & ssh.exe @sshArgs "${SshUser}@${ServerIp}" 'sudo bash /tmp/otus-k8s/scripts/run-portal.sh'
if ($LASTEXITCODE -ne 0) { throw 'Portal deployment failed' }
Invoke-Remote $ServerIp 'sudo apt-get update && sudo apt-get install -y sqlite3 && sudo bash /tmp/otus-k8s/scripts/install-backup-timer.sh'
& (Join-Path $root 'fetch-backup.ps1') -ServerIp $ServerIp -SshUser $SshUser -SshKey $SshKey

$response = Invoke-WebRequest -Uri "http://${ServerIp}/health" -Headers @{ Host = 'portal.otus.test' } -UseBasicParsing -TimeoutSec 15
if ($response.StatusCode -ne 200 -or $response.Content.Trim() -ne 'ok') { throw 'Ingress health check failed' }
$credentials = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("otus:$($env:PORTAL_PASSWORD)"))
$response = Invoke-WebRequest -Uri "http://${ServerIp}/" -Headers @{ Host = 'portal.otus.test'; Authorization = "Basic $credentials" } -UseBasicParsing -TimeoutSec 15
if ($response.StatusCode -ne 200 -or $response.Content -notmatch 'Веб-портал OTUS') { throw 'Portal content check failed' }
Invoke-Remote $ServerIp 'sudo kubectl get nodes -o wide && sudo kubectl -n otus-portal get pods,service,ingress -o wide'
Write-Host 'Kubernetes portal and backup timer are ready.'
