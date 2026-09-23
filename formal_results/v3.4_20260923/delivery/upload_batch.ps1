#requires -Version 7.0
param([Parameter(Mandatory)][string]$PublicationDirectory,[Parameter(Mandatory)][string]$RepositoryDirectory,[Parameter(Mandatory)][long]$ReleaseId,[int]$Concurrency=4)
$ErrorActionPreference='Stop'
$plan=Get-Content -LiteralPath (Join-Path $PublicationDirectory 'upload_plan.json') -Raw|ConvertFrom-Json
$pending=[Collections.Generic.Queue[object]]::new();foreach($item in $plan.assets){$pending.Enqueue($item)}
$active=[Collections.Generic.List[object]]::new();$done=0;$failed=0;$bytesDone=0L;$started=[DateTimeOffset]::UtcNow;$last=[DateTimeOffset]::MinValue
$receiptDir=Join-Path $PublicationDirectory 'upload_receipts';$logDir=Join-Path $PublicationDirectory 'upload_logs'
New-Item -ItemType Directory -Path $receiptDir,$logDir -Force|Out-Null
while($pending.Count-gt 0-or $active.Count-gt 0){
 while($pending.Count-gt 0-and $active.Count-lt $Concurrency){
  $item=$pending.Dequeue();$receipt=Join-Path $receiptDir ($item.name+'.json');$log=Join-Path $logDir ($item.name+'.log')
  $job=Start-ThreadJob -ScriptBlock {
   param($script,$repo,$rid,$file,$receipt,$log)
   & pwsh.exe -NoLogo -NoProfile -File $script -RepositoryDirectory $repo -ReleaseId $rid -File $file -ReceiptPath $receipt 2>&1|Out-File -LiteralPath $log -Encoding utf8
   [pscustomobject]@{exitCode=$LASTEXITCODE;receipt=$receipt;log=$log}
  } -ArgumentList (Join-Path $PublicationDirectory 'upload_formal_asset.ps1'),$RepositoryDirectory,$ReleaseId,$item.path,$receipt,$log
  $active.Add([pscustomobject]@{job=$job;item=$item;receipt=$receipt;log=$log})
 }
 foreach($task in @($active.ToArray())){
  if($task.job.State-in @('Completed','Failed','Stopped')){
   $res=@(Receive-Job -Job $task.job -ErrorAction Continue);$ok=$task.job.State-eq 'Completed'-and $res.Count-gt 0-and $res[-1].exitCode-eq 0-and (Test-Path -LiteralPath $task.receipt)
   if($ok){$receiptData=Get-Content -LiteralPath $task.receipt -Raw|ConvertFrom-Json;$ok=$receiptData.status-eq 'REMOTE_SHA256_AND_SIZE_VERIFIED'-and $receiptData.sha256-eq $task.item.sha256-and $receiptData.bytes-eq $task.item.bytes}
   if($ok){$done++;$bytesDone+=$task.item.bytes;Write-Output ("ASSET_OK {0} ({1}/{2})"-f $task.item.name,$done,$plan.assets.Count)}else{$failed++;Write-Output ("ASSET_FAILED {0} log={1}"-f $task.item.name,$task.log)}
   Remove-Job -Job $task.job;$active.Remove($task)|Out-Null
  }
 }
 if(([DateTimeOffset]::UtcNow-$last).TotalSeconds-ge 30){
  $progress=[ordered]@{at=[DateTimeOffset]::UtcNow.ToString('o');verified=$done;failed=$failed;active=$active.Count;remaining=$pending.Count;total=$plan.assets.Count;bytes_verified=$bytesDone;elapsed_seconds=([DateTimeOffset]::UtcNow-$started).TotalSeconds}
  $progress|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $PublicationDirectory 'upload_progress.json') -Encoding utf8
  Write-Output ("UPLOAD_TOTAL verified={0}/{1} failed={2} bytes={3:N0} active={4}"-f $done,$plan.assets.Count,$failed,$bytesDone,$active.Count);$last=[DateTimeOffset]::UtcNow
 }
 if($active.Count-gt 0){Start-Sleep -Seconds 2}
}
[ordered]@{status=$(if($failed-eq 0){'PASS'}else{'FAILED'});verified=$done;failed=$failed;total=$plan.assets.Count;bytes_verified=$bytesDone;finished_at=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $PublicationDirectory 'upload_batch_result.json') -Encoding utf8
if($failed-ne 0){exit 1}
