param(
    [int]$Port = 9999
)

. "$PSScriptRoot\common.ps1"

try {
    $state = Read-WebDemoRuntimeState
    $connections = @(Get-NetTCPConnection -LocalPort $Port -ErrorAction SilentlyContinue)
    $pids = New-Object System.Collections.Generic.List[int]
    if ($state -and $state.port -eq $Port -and $state.pid -gt 4) {
        $pids.Add([int]$state.pid) | Out-Null
    }
    foreach ($pidValue in @($connections | Select-Object -ExpandProperty OwningProcess -Unique | Where-Object { $_ -gt 4 })) {
        if (-not $pids.Contains([int]$pidValue)) { $pids.Add([int]$pidValue) | Out-Null }
    }

    $stopped = New-Object System.Collections.Generic.List[int]
    $errors = New-Object System.Collections.Generic.List[string]

    foreach ($pidValue in $pids.ToArray()) {
        try {
            Stop-Process -Id $pidValue -ErrorAction Stop
            $stopped.Add([int]$pidValue) | Out-Null
        }
        catch {
            $errors.Add("PID $pidValue：$($_.Exception.Message)") | Out-Null
        }
    }

    if ($state -and $state.port -eq $Port) { Clear-WebDemoRuntimeState }

    $exitCode = if ($errors.Count -eq 0) { 0 } else { 1 }
    Write-WebDemoJson @{
        ok = ($errors.Count -eq 0)
        port = $Port
        runtimeState = $state
        stoppedPids = @($stopped.ToArray())
        errors = @($errors)
        message = if ($stopped.Count -gt 0) { "已停止端口 $Port 上的旧服务" } else { "端口 $Port 当前没有旧服务" }
    } $exitCode
}
catch {
    Write-WebDemoJson @{ ok = $false; error = "stop_port_failed"; port = $Port; message = $_.Exception.Message } 1
}
