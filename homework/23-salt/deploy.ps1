#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$MasterIp = '172.28.19.10',
    [string]$Web2Ip = '172.28.19.11',
    [string]$SshUser = 'ubuntu',
    [string]$SshKey = (Join-Path $HOME '.ssh\id_ed25519')
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not (Test-Path -LiteralPath $SshKey -PathType Leaf)) { throw "SSH key not found: $SshKey" }
foreach ($ip in @($MasterIp, $Web2Ip)) {
    $parsed = $null
    if (-not [System.Net.IPAddress]::TryParse($ip, [ref]$parsed)) {
        throw "Invalid IP: $ip"
    }
}
$sshArgs = @('-i', $SshKey, '-o', 'BatchMode=yes', '-o', 'StrictHostKeyChecking=accept-new', '-o', 'ConnectTimeout=10')
function Invoke-Ssh([string]$Ip, [string]$Command) {
    & ssh.exe @sshArgs "${SshUser}@${Ip}" $Command
    if ($LASTEXITCODE -ne 0) { throw "SSH failed on ${Ip}: $Command" }
}
function Copy-Remote([string]$Path, [string]$Ip, [string]$Target) {
    & scp.exe @sshArgs -r $Path "${SshUser}@${Ip}:${Target}"
    if ($LASTEXITCODE -ne 0) { throw "SCP failed on $Ip" }
}

foreach ($ip in @($MasterIp, $Web2Ip)) { Invoke-Ssh $ip 'true' }
foreach ($ip in @($MasterIp, $Web2Ip)) {
    foreach ($domain in @('archive.ubuntu.com', 'security.ubuntu.com', 'packages.broadcom.com', 'github.com', 'release-assets.githubusercontent.com')) {
        $address = (Resolve-DnsName $domain -Type A -ErrorAction Stop |
            Where-Object { $_.IPAddress } | Select-Object -First 1 -ExpandProperty IPAddress)
        if (-not $address) { throw "Could not resolve $domain on host" }
        Invoke-Ssh $ip "sudo sed -i '/[[:space:]]$domain`$/d' /etc/hosts; echo '$address $domain' | sudo tee -a /etc/hosts"
    }
}
Invoke-Ssh $MasterIp 'mkdir -p /tmp/otus-salt'
Copy-Remote (Join-Path $root 'salt\.') $MasterIp '/tmp/otus-salt/'
Copy-Remote (Join-Path $root 'bootstrap.sh') $MasterIp '/tmp/otus-salt-bootstrap.sh'
Copy-Remote (Join-Path $root 'bootstrap.sh') $Web2Ip '/tmp/otus-salt-bootstrap.sh'
Invoke-Ssh $MasterIp "sudo bash /tmp/otus-salt-bootstrap.sh $MasterIp web1 true"
Invoke-Ssh $Web2Ip "sudo bash /tmp/otus-salt-bootstrap.sh $MasterIp web2 false"

foreach ($id in @('web1', 'web2')) {
    $seen = $false
    for ($i = 0; $i -lt 30; $i++) {
        $keys = Invoke-Ssh $MasterIp 'sudo salt-key -L --out=json' | Out-String | ConvertFrom-Json
        if (@($keys.minions) -contains $id) { $seen = $true; break }
        if (@($keys.minions_pre) -contains $id) {
            Invoke-Ssh $MasterIp "sudo salt-key -a $id -y"
            $seen = $true
            break
        }
        Start-Sleep -Seconds 2
    }
    if (-not $seen) { throw "Salt key not seen: $id" }
}
$ready = $false
for ($i = 0; $i -lt 30; $i++) {
    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $pingText = & ssh.exe @sshArgs "${SshUser}@${MasterIp}" "sudo salt 'web*' test.ping --timeout=60 --static --out=json" 2>$null | Out-String
    $ErrorActionPreference = $previousPreference
    if ($LASTEXITCODE -eq 0) {
        try {
            $ping = $pingText | ConvertFrom-Json
            if ($ping.web1 -eq $true -and $ping.web2 -eq $true) { $ready = $true; break }
        } catch { }
    }
    Start-Sleep -Seconds 3
}
if (-not $ready) { throw 'Salt minions did not answer test.ping' }
$first = Invoke-Ssh $MasterIp "sudo salt 'web*' state.highstate --timeout=60 --static --out=json" | Out-String | ConvertFrom-Json
$second = Invoke-Ssh $MasterIp "sudo salt 'web*' state.highstate --timeout=60 --static --out=json" | Out-String | ConvertFrom-Json
foreach ($id in @('web1', 'web2')) {
    foreach ($run in @($first, $second)) {
        if (-not $run.$id) { throw "Missing highstate result: $id" }
        foreach ($state in $run.$id.PSObject.Properties) {
            if ($state.Value.result -ne $true) { throw "Failed state on ${id}: $($state.Name)" }
        }
    }
    foreach ($state in $second.$id.PSObject.Properties) {
        $changes = $state.Value.changes
        if ($null -ne $changes -and $changes.PSObject.Properties.Count -gt 0) {
            throw "Second highstate changed ${id}: $($state.Name)"
        }
    }
}
foreach ($ip in @($MasterIp, $Web2Ip)) {
    $response = Invoke-WebRequest -Uri "http://${ip}/health" -UseBasicParsing -TimeoutSec 10
    if ($response.StatusCode -ne 200 -or $response.Content.Trim() -ne 'ok') {
        throw "Health check failed: $ip"
    }
}
Write-Host 'Salt deployment and health checks completed.'
