#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$ServerIp = '172.28.19.10',
    [string]$SshUser = 'ubuntu',
    [string]$SshKey = (Join-Path $HOME '.ssh\id_ed25519')
)
$ErrorActionPreference = 'Stop'
$sshArgs = @('-i', $SshKey, '-o', 'BatchMode=yes', '-o', 'StrictHostKeyChecking=accept-new', '-o', 'ConnectTimeout=10')
$name = & ssh.exe @sshArgs "${SshUser}@${ServerIp}" "sudo ls -1t /var/backups/otus-k3s | grep '^cluster-.*\.tar\.gz$' | head -1"
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($name)) { throw 'No cluster backup found' }
$name = $name.Trim()
$remote = "/var/backups/otus-k3s/$name"
$localDir = Join-Path $PSScriptRoot 'backups'
New-Item -ItemType Directory -Force -Path $localDir | Out-Null
$temporary = "/tmp/$name"
try {
    & ssh.exe @sshArgs "${SshUser}@${ServerIp}" "sudo install -m 600 -o $SshUser -g $SshUser $remote $temporary"
    if ($LASTEXITCODE -ne 0) { throw 'Could not stage the backup for transfer' }
    & scp.exe @sshArgs "${SshUser}@${ServerIp}:$temporary" (Join-Path $localDir $name)
    if ($LASTEXITCODE -ne 0) { throw 'Could not copy the backup' }
    $localHash = (Get-FileHash -LiteralPath (Join-Path $localDir $name) -Algorithm SHA256).Hash.ToLowerInvariant()
    $remoteHash = (& ssh.exe @sshArgs "${SshUser}@${ServerIp}" "sudo sha256sum $remote" | Out-String).Split(' ')[0].ToLowerInvariant()
    if ($localHash -ne $remoteHash) { throw 'Backup checksum mismatch' }
    Write-Host "Verified backup: $(Join-Path $localDir $name)"
} finally {
    & ssh.exe @sshArgs "${SshUser}@${ServerIp}" "rm -f $temporary" | Out-Null
}
