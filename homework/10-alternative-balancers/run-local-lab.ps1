param([switch]$KeepVms)

$ErrorActionPreference = "Stop"
$root = $PSScriptRoot
$evidence = Join-Path $root "evidence"
$labStarted = $false
$result = [ordered]@{
    verified = $false
    status = "not-run"
    vms = @("nginx1", "nginx2", "app1", "app2", "db1")
    vip = "192.168.56.100"
    backend_after_app1_stop = @()
    frontend_after_nginx1_stop = @()
    checks = [ordered]@{}
}

function Invoke-CheckedNative {
    param([scriptblock]$Command)
    & $Command
    if ($LASTEXITCODE -ne 0) { throw "Команда завершилась с кодом $LASTEXITCODE" }
}

function Get-LabResponse {
    param([string]$Path = "/health")
    $response = Invoke-WebRequest -UseBasicParsing -Uri "http://192.168.56.100$Path" -TimeoutSec 12
    if ($response.StatusCode -ne 200) { throw "HTTP $($response.StatusCode) для $Path" }
    return $response
}

function Wait-LabResponse {
    param([string]$Frontend = "")
    for ($attempt = 0; $attempt -lt 25; $attempt++) {
        try {
            $response = Get-LabResponse
            if (-not $Frontend -or $response.Headers["X-Frontend"] -eq $Frontend) { return $response }
        } catch {
            Write-Host "Ожидание ответа: $($_.Exception.Message)"
        }
        Start-Sleep -Seconds 2
    }
    throw "VIP не ответил ожидаемым фронтендом $Frontend за 50 секунд"
}

try {
    Set-Location $root
    New-Item -ItemType Directory -Path $evidence -Force | Out-Null
    if (-not (Get-Command vagrant -ErrorAction SilentlyContinue)) { throw "Vagrant не найден" }
    if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) { throw "WSL не найден" }

    $labStarted = $true
    Invoke-CheckedNative { vagrant up --provider virtualbox }
    $linuxRoot = (& wsl.exe wslpath -a $root).Trim()
    if ($LASTEXITCODE -ne 0 -or -not $linuxRoot) { throw "Не удалось преобразовать путь для WSL" }
    Invoke-CheckedNative { wsl.exe --exec bash "$linuxRoot/scripts/prepare-wsl.sh" $linuxRoot }
    Invoke-CheckedNative { wsl.exe --exec bash "$linuxRoot/scripts/deploy-wsl.sh" $linuxRoot }

    $first = Wait-LabResponse
    $firstBody = $first.Content | ConvertFrom-Json
    if ($firstBody.database -ne "ok" -or $firstBody.static -ne "gfs2") { throw "Бэкенд не подтвердил БД и GFS2" }
    $result.checks["initial_frontend"] = $first.Headers["X-Frontend"]
    $result.checks["initial_backend"] = $firstBody.backend

    $static = Get-LabResponse "/static/index.html"
    if ($static.Content -notmatch "Shared GFS2 static page") { throw "Статическая страница не прочитана" }
    $result.checks["static_http"] = $static.StatusCode
    $result.checks["static_backend"] = $static.Headers["X-Backend"]

    Invoke-CheckedNative { vagrant ssh app1 -c "sudo systemctl stop otus-app" }
    for ($i = 0; $i -lt 6; $i++) {
        $response = Wait-LabResponse
        $body = $response.Content | ConvertFrom-Json
        if ($body.backend -ne "app2") { throw "После остановки app1 ответил $($body.backend)" }
        $result.backend_after_app1_stop += $body.backend
    }
    $result.checks["backend_failover"] = $true
    Invoke-CheckedNative { vagrant ssh app1 -c "sudo systemctl start otus-app" }

    $recoveredBackends = @{}
    for ($i = 0; $i -lt 18 -and $recoveredBackends.Count -lt 2; $i++) {
        $response = Wait-LabResponse
        $body = $response.Content | ConvertFrom-Json
        if ($body.backend -in @("app1", "app2")) { $recoveredBackends[$body.backend] = $true }
        Start-Sleep -Seconds 1
    }
    if ($recoveredBackends.Count -ne 2) { throw "Оба бэкенда не вернулись в балансировку" }
    $result.checks["backend_recovery"] = $true

    $primary = Wait-LabResponse "nginx1"
    Invoke-CheckedNative { vagrant ssh nginx1 -c "sudo systemctl stop nginx" }
    $secondary = Wait-LabResponse "nginx2"
    for ($i = 0; $i -lt 6; $i++) {
        $response = Wait-LabResponse "nginx2"
        $result.frontend_after_nginx1_stop += $response.Headers["X-Frontend"]
    }
    $result.checks["frontend_failover"] = $true
    Invoke-CheckedNative { vagrant ssh nginx1 -c "sudo systemctl start nginx" }
    $restoredPrimary = Wait-LabResponse "nginx1"
    $result.checks["frontend_recovery"] = $restoredPrimary.Headers["X-Frontend"]

    foreach ($vm in @("app1", "app2")) {
        $fs = @(& vagrant ssh $vm -c "findmnt -n -o FSTYPE /srv/otus-static && cat /srv/otus-static/index.html") -join [Environment]::NewLine
        if ($LASTEXITCODE -ne 0 -or $fs -notmatch "gfs2" -or $fs -notmatch "Shared GFS2 static page") {
            throw "Общий GFS2 не проверен на $vm"
        }
        $result.checks["gfs2_$vm"] = $true
    }

    $result.verified = $true
    $result.status = "passed"
    Write-Host "Проверки прошли: VIP, PostgreSQL, GFS2, отказ app1, отказ nginx1"
} catch {
    $result.status = "failed"
    $result["error"] = $_.Exception.Message
    Write-Host "Проверка завершилась ошибкой: $($_.Exception.Message)"
} finally {
    if ($labStarted) {
        Set-Location $root
        try { & vagrant ssh app1 -c "sudo systemctl start otus-app" 2>$null | Out-Null } catch { }
        try { & vagrant ssh nginx1 -c "sudo systemctl start nginx" 2>$null | Out-Null } catch { }
        if (-not $KeepVms -and $result.status -eq "passed") {
            & vagrant destroy -f
            $result["destroy_exit_code"] = $LASTEXITCODE
            if ($LASTEXITCODE -ne 0) { $result.status = "failed-cleanup"; $result.verified = $false }
        }
    }
}

$result | ConvertTo-Json -Depth 8 | Set-Content -Path (Join-Path $evidence "local-lab-results.json") -Encoding utf8
if ($result.status -ne "passed") { exit 1 }
