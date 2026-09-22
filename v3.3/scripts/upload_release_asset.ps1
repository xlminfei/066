#requires -Version 7.0
param([Parameter(Mandatory)][string]$RepositoryDirectory,[Parameter(Mandatory)][long]$ReleaseId,[Parameter(Mandatory)][string]$File,[Parameter(Mandatory)][string]$ReceiptPath)
$ErrorActionPreference='Stop'
$taskFile=(Resolve-Path -LiteralPath $File).Path
$taskName=[IO.Path]::GetFileName($taskFile)
$taskExpected=(Get-FileHash -LiteralPath $taskFile -Algorithm SHA256).Hash.ToLowerInvariant()
$env:GIT_TERMINAL_PROMPT='0';$env:GCM_INTERACTIVE='Never'
# The existing Git credential remains in this process only; never log or save it.
$taskQuery=@('protocol=https','host=github.com','path=xlminfei/066.git','','') -join [char]10
$taskCredential=@($taskQuery | git -C $RepositoryDirectory -c credential.interactive=never credential fill)
if($LASTEXITCODE -ne 0){throw 'GitHub credential helper failed'}
$taskPasswordLine=@($taskCredential|Where-Object { $_.StartsWith('password=') })
if($taskPasswordLine.Count -ne 1){throw 'GitHub credential unavailable'}
$taskSecret=$taskPasswordLine[0].Substring(9)
$taskClient=[Net.Http.HttpClient]::new();$taskClient.Timeout=[TimeSpan]::FromMinutes(45)
$taskClient.DefaultRequestHeaders.Authorization=[Net.Http.Headers.AuthenticationHeaderValue]::new('Bearer',$taskSecret)
$taskClient.DefaultRequestHeaders.UserAgent.ParseAdd('ratio-v3.3-evidence-uploader')
$taskClient.DefaultRequestHeaders.Accept.ParseAdd('application/vnd.github+json')
$taskClient.DefaultRequestHeaders.Add('X-GitHub-Api-Version','2022-11-28')
$taskInput=$null;$taskRequest=$null
try {
 $taskAssets=$taskClient.GetStringAsync("https://api.github.com/repos/xlminfei/066/releases/$ReleaseId/assets?per_page=100").GetAwaiter().GetResult() | ConvertFrom-Json
 $taskExisting=@($taskAssets|Where-Object name -eq $taskName)
 if($taskExisting.Count){
  if($taskExisting.Count -ne 1 -or $taskExisting[0].digest -ne "sha256:$taskExpected" -or $taskExisting[0].size -ne (Get-Item -LiteralPath $taskFile).Length){throw 'Existing release asset differs; no overwrite performed'}
  $taskAsset=$taskExisting[0]
 } else {
  $taskUrl="https://uploads.github.com/repos/xlminfei/066/releases/$ReleaseId/assets?name=$([Uri]::EscapeDataString($taskName))"
  $taskInput=[IO.File]::OpenRead($taskFile)
  $taskRequest=[Net.Http.HttpRequestMessage]::new([Net.Http.HttpMethod]::Post,$taskUrl)
  $taskRequest.Content=[Net.Http.StreamContent]::new($taskInput)
  $taskRequest.Content.Headers.ContentType=[Net.Http.Headers.MediaTypeHeaderValue]::new('application/octet-stream')
  $taskRequest.Content.Headers.ContentLength=$taskInput.Length
  $taskUpload=$taskClient.SendAsync($taskRequest,[Net.Http.HttpCompletionOption]::ResponseHeadersRead)
  while(!$taskUpload.IsCompleted){Start-Sleep -Seconds 10;Write-Output ("UPLOAD {0}: {1:N1}% read from source" -f $taskName,(100*$taskInput.Position/$taskInput.Length))}
  $taskResponse=$taskUpload.GetAwaiter().GetResult()
  $taskBody=$taskResponse.Content.ReadAsStringAsync().GetAwaiter().GetResult()
  if(!$taskResponse.IsSuccessStatusCode){throw "GitHub asset upload failed: HTTP $([int]$taskResponse.StatusCode); $taskBody"}
  $taskAsset=$taskBody|ConvertFrom-Json
 }
 # Re-read authoritative metadata and require both server checksum and byte count.
 $taskVerified=$taskClient.GetStringAsync("https://api.github.com/repos/xlminfei/066/releases/assets/$($taskAsset.id)").GetAwaiter().GetResult() | ConvertFrom-Json
 if($taskVerified.state -ne 'uploaded' -or $taskVerified.digest -ne "sha256:$taskExpected" -or $taskVerified.size -ne (Get-Item -LiteralPath $taskFile).Length){throw 'Remote asset verification failed'}
 $taskReceipt=[ordered]@{status='REMOTE_SHA256_AND_SIZE_VERIFIED';release_id=$ReleaseId;asset_id=$taskVerified.id;name=$taskName;bytes=$taskVerified.size;sha256=$taskExpected;server_digest=$taskVerified.digest;url=$taskVerified.browser_download_url}
 $taskParent=Split-Path -Parent $ReceiptPath;New-Item -ItemType Directory -Path $taskParent -Force|Out-Null
 $taskReceipt|ConvertTo-Json|Set-Content -LiteralPath $ReceiptPath -Encoding utf8
 $taskReceipt|ConvertTo-Json
}finally{if($taskRequest){$taskRequest.Dispose()};if($taskInput){$taskInput.Dispose()};$taskClient.Dispose();$taskSecret=$null;$taskCredential=$null;$taskPasswordLine=$null}
