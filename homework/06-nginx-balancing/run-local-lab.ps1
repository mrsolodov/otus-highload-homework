$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

$evidenceDir = Join-Path $PSScriptRoot 'evidence'
New-Item -ItemType Directory -Path $evidenceDir -Force | Out-Null
$logPath = Join-Path $evidenceDir 'local-lab-run.txt'
$resultPath = Join-Path $evidenceDir 'local-lab-results.json'
$web2Stopped = $false
$destroyExitCode = $null

function Assert-ExitCode {
    param([string]$Step)
    if ($LASTEXITCODE -ne 0) {
        throw "$Step failed with exit code $LASTEXITCODE"
    }
}

function Get-LabResponse {
    param([string]$Path)
    $response = Invoke-WebRequest -UseBasicParsing -Uri "http://192.168.77.10$Path" -TimeoutSec 15
    if ($response.StatusCode -ne 200) {
        throw "HTTP $($response.StatusCode) for $Path"
    }
    [pscustomobject]@{
        Path = $Path
        Status = $response.StatusCode
        Frontend = [string]$response.Headers['X-Frontend']
        Mode = [string]$response.Headers['X-Balancing-Mode']
        Body = $response.Content.Trim()
    }
}

Start-Transcript -Path $logPath -Force
try {
    Write-Host '=== Validate ==='
    & vagrant validate
    Assert-ExitCode 'vagrant validate'

    Write-Host '=== Create and configure four VMs ==='
    & vagrant up --provider=virtualbox
    Assert-ExitCode 'vagrant up'

    Write-Host '=== VM status ==='
    & vagrant status
    Assert-ExitCode 'vagrant status'

    Write-Host '=== Round-robin ==='
    $roundRobin = @(1..9 | ForEach-Object { Get-LabResponse '/rr/api/health' })
    $roundRobin | Format-Table Path, Status, Frontend, Mode -AutoSize
    $names = @($roundRobin | ForEach-Object Frontend | Sort-Object -Unique)
    if ($names.Count -ne 3 -or @($names | Where-Object { $_ -notin @('web1', 'web2', 'web3') }).Count -ne 0) {
        throw "Expected web1, web2, web3; got: $($names -join ', ')"
    }

    Write-Host '=== Consistent hash ==='
    $hash = @(1..6 | ForEach-Object { Get-LabResponse '/hash/api/health?key=otus' })
    $hash | Format-Table Path, Status, Frontend, Mode -AutoSize
    if (@($hash | ForEach-Object Frontend | Sort-Object -Unique).Count -ne 1) {
        throw 'The same hash key reached different frontends'
    }

    Write-Host '=== Static content ==='
    $static = Get-LabResponse '/rr/'
    if ($static.Body -notmatch 'Frontend') {
        throw 'The static page does not identify a frontend'
    }
    $static | Format-List

    Write-Host '=== Stop web2 Nginx and verify availability ==='
    & vagrant ssh web2 -c 'sudo systemctl stop nginx'
    Assert-ExitCode 'Stopping Nginx on web2'
    $web2Stopped = $true
    $failover = @(1..6 | ForEach-Object { Get-LabResponse '/rr/api/health' })
    $failover | Format-Table Path, Status, Frontend, Mode -AutoSize
    if (@($failover | Where-Object { $_.Frontend -eq 'web2' }).Count -ne 0) {
        throw 'The load balancer sent a request to the stopped web2'
    }

    & vagrant ssh web2 -c 'sudo systemctl start nginx'
    Assert-ExitCode 'Restoring Nginx on web2'
    $web2Stopped = $false

    Write-Host '=== Verify recovery ==='
    Start-Sleep -Seconds 12
    $recovered = @(1..12 | ForEach-Object { Get-LabResponse '/rr/api/health' })
    $recovered | Format-Table Path, Status, Frontend, Mode -AutoSize
    if (@($recovered | Where-Object { $_.Frontend -eq 'web2' }).Count -eq 0) {
        throw 'web2 did not reappear after recovery'
    }

    $result = [pscustomobject]@{
        Time = (Get-Date).ToString('o')
        Status = 'passed'
        RoundRobin = $roundRobin
        Hash = $hash
        Static = $static
        Failover = $failover
        Recovered = $recovered
    }
    $json = $result | ConvertTo-Json -Depth 6
    [System.IO.File]::WriteAllText($resultPath, $json + [Environment]::NewLine, [System.Text.UTF8Encoding]::new($false))
    Write-Host "Checks passed. Results: $resultPath"
}
finally {
    if ($web2Stopped) {
        Write-Host '=== Restore web2 Nginx ==='
        & vagrant ssh web2 -c 'sudo systemctl start nginx'
    }
    Write-Host '=== Destroy local VMs ==='
    & vagrant destroy -f
    $destroyExitCode = $LASTEXITCODE
    Write-Host "vagrant destroy exit code: $destroyExitCode"
    Stop-Transcript
}

if ($destroyExitCode -ne 0) {
    throw "Checks passed, but VM removal failed with exit code $destroyExitCode. Check vagrant status."
}
