# Allow atomic rename while reading a Windows-hosted queue status file.
$ErrorActionPreference = 'Stop'
$taskAnalysisRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
function Read-TaskSharedText([string]$TaskPath) {
    $taskShare = [IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete
    $taskStream = [IO.File]::Open($TaskPath,[IO.FileMode]::Open,[IO.FileAccess]::Read,$taskShare)
    try {
        $taskReader = [IO.StreamReader]::new($taskStream,[Text.Encoding]::UTF8)
        try { return $taskReader.ReadToEnd() } finally { $taskReader.Dispose() }
    } finally { $taskStream.Dispose() }
}
$taskRows = @(foreach ($taskName in @('fit_queue_status.json','cv_queue_status.json','extensions_queue_status.json')) {
    $taskPath = Join-Path $taskAnalysisRoot ('provenance\'+$taskName)
    if (Test-Path -LiteralPath $taskPath) {
        $taskState = (Read-TaskSharedText $taskPath) | ConvertFrom-Json
        [pscustomobject]@{
            Queue = $taskName
            PID = $taskState.pid
            Status = $taskState.status
            Updated = $taskState.updated_at
            Passed = $taskState.passed
            PrimaryPassed = if ($taskName -eq 'fit_queue_status.json') { @($taskState.finished | Where-Object { $_.status -eq 'PASS' -and $_.variant -eq 'primary' }).Count } else { $null }
            SensitivityPassed = if ($taskName -eq 'fit_queue_status.json') { @($taskState.finished | Where-Object { $_.status -eq 'PASS' -and $_.variant -ne 'primary' }).Count } else { $null }
            Pending = $taskState.pending
            Active = @($taskState.active | Select-Object job_id,name,pid,started_at)
            Attention = $taskState.needs_attention
            Failures = $taskState.failures
        }
    }
})
$taskRows | ConvertTo-Json -Depth 6
