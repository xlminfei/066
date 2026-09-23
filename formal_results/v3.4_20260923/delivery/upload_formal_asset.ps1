#requires -Version 7.0
param([Parameter(Mandatory)][string]$RepositoryDirectory,[Parameter(Mandatory)][long]$ReleaseId,[Parameter(Mandatory)][string]$File,[Parameter(Mandatory)][string]$ReceiptPath)
$ErrorActionPreference='Stop'
$env:GIT_TERMINAL_PROMPT='0';$env:GCM_INTERACTIVE='Never'
$uploadFile=(Resolve-Path -LiteralPath $File).Path;$uploadName=[IO.Path]::GetFileName($uploadFile)
$uploadSize=(Get-Item -LiteralPath $uploadFile).Length;$uploadSha=(Get-FileHash -LiteralPath $uploadFile -Algorithm SHA256).Hash.ToLowerInvariant()
$uploadQuery=@('protocol=https','host=github.com','path=xlminfei/066.git','','') -join [char]10
$uploadCredential=@($uploadQuery|git -C $RepositoryDirectory -c credential.interactive=never credential fill)
if($LASTEXITCODE-ne 0){throw 'Credential helper failed'}
$uploadTokenLine=@($uploadCredential|Where-Object{$_.StartsWith('password=')});if($uploadTokenLine.Count-ne 1){throw 'No existing GitHub credential'}
$uploadSecret=$uploadTokenLine[0].Substring(9)
$uploadClient=[Net.Http.HttpClient]::new();$uploadClient.Timeout=[TimeSpan]::FromMinutes(30)
$uploadClient.DefaultRequestHeaders.Authorization=[Net.Http.Headers.AuthenticationHeaderValue]::new('Bearer',$uploadSecret)
$uploadClient.DefaultRequestHeaders.UserAgent.ParseAdd('ratio-v34-formal-results-uploader')
$uploadClient.DefaultRequestHeaders.Accept.ParseAdd('application/vnd.github+json')
$uploadClient.DefaultRequestHeaders.Add('X-GitHub-Api-Version','2022-11-28')
$receiptParent=Split-Path -Parent $ReceiptPath;New-Item -ItemType Directory -Path $receiptParent -Force|Out-Null
function Read-AllAssets {
 $all=[Collections.Generic.List[object]]::new();$page=1
 do {
  $json=$uploadClient.GetStringAsync("https://api.github.com/repos/xlminfei/066/releases/$ReleaseId/assets?per_page=100&page=$page").GetAwaiter().GetResult()
  $batch=@($json|ConvertFrom-Json);foreach($a in $batch){$all.Add($a)};$page++
 } while($batch.Count-eq 100)
 return $all.ToArray()
}
$uploadStarted=[DateTimeOffset]::UtcNow;$completed=$false
try {
 for($attempt=1;$attempt-le 3;$attempt++) {
  $inputStream=$null;$request=$null;$response=$null
  try {
   $existing=@(Read-AllAssets|Where-Object name -eq $uploadName)
   if($existing.Count-gt 1){throw 'Duplicate release asset names'}
   if($existing.Count-eq 1-and $existing[0].state-eq 'starter'-and $existing[0].size-eq 0-and $attempt-gt 1) {
    $orphan=$existing[0];[ordered]@{name=$uploadName;asset_id=$orphan.id;reason='zero-byte starter from this failed upload retry';attempt=$attempt}|ConvertTo-Json|Set-Content -LiteralPath ($ReceiptPath+".cleanup-$attempt.json") -Encoding utf8
    $deleted=$uploadClient.DeleteAsync("https://api.github.com/repos/xlminfei/066/releases/assets/$($orphan.id)").GetAwaiter().GetResult();$deleted.EnsureSuccessStatusCode()|Out-Null;$deleted.Dispose();$existing=@()
   }
   if($existing.Count-eq 1) {
    if($existing[0].state-ne 'uploaded'-or $existing[0].size-ne $uploadSize-or $existing[0].digest-ne "sha256:$uploadSha"){throw 'Existing asset differs; no overwrite performed'}
    $asset=$existing[0]
   } else {
    $url="https://uploads.github.com/repos/xlminfei/066/releases/$ReleaseId/assets?name=$([Uri]::EscapeDataString($uploadName))"
    $inputStream=[IO.File]::OpenRead($uploadFile);$request=[Net.Http.HttpRequestMessage]::new([Net.Http.HttpMethod]::Post,$url)
    $request.Content=[Net.Http.StreamContent]::new($inputStream);$request.Content.Headers.ContentType=[Net.Http.Headers.MediaTypeHeaderValue]::new('application/octet-stream');$request.Content.Headers.ContentLength=$uploadSize
    $pending=$uploadClient.SendAsync($request,[Net.Http.HttpCompletionOption]::ResponseHeadersRead);$lastProgress=[DateTimeOffset]::UtcNow
    while(!$pending.IsCompleted){Start-Sleep -Seconds 2;if(([DateTimeOffset]::UtcNow-$lastProgress).TotalSeconds-ge 30){Write-Output ("PROGRESS {0} attempt={1} local_stream_read={2:N1}%"-f $uploadName,$attempt,(100*$inputStream.Position/$uploadSize));$lastProgress=[DateTimeOffset]::UtcNow}}
    $response=$pending.GetAwaiter().GetResult();$body=$response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
    if(!$response.IsSuccessStatusCode){throw "Upload HTTP $([int]$response.StatusCode): $body"};$asset=$body|ConvertFrom-Json
   }
   $verified=$uploadClient.GetStringAsync("https://api.github.com/repos/xlminfei/066/releases/assets/$($asset.id)").GetAwaiter().GetResult()|ConvertFrom-Json
   if($verified.state-ne 'uploaded'-or $verified.size-ne $uploadSize-or $verified.digest-ne "sha256:$uploadSha"){throw 'Server size/digest verification failed'}
   $receipt=[ordered]@{status='REMOTE_SHA256_AND_SIZE_VERIFIED';release_id=$ReleaseId;asset_id=$verified.id;name=$uploadName;bytes=$uploadSize;sha256=$uploadSha;server_digest=$verified.digest;url=$verified.browser_download_url;attempt=$attempt;started_at=$uploadStarted.ToString('o');completed_at=[DateTimeOffset]::UtcNow.ToString('o');elapsed_seconds=([DateTimeOffset]::UtcNow-$uploadStarted).TotalSeconds}
   $receipt|ConvertTo-Json|Set-Content -LiteralPath $ReceiptPath -Encoding utf8;$receipt|ConvertTo-Json -Compress;$completed=$true;break
  } catch {
   [ordered]@{name=$uploadName;attempt=$attempt;at=[DateTimeOffset]::UtcNow.ToString('o');error=$_.Exception.Message}|ConvertTo-Json|Set-Content -LiteralPath ($ReceiptPath+".attempt-$attempt-error.json") -Encoding utf8
   if($attempt-eq 3){throw};Start-Sleep -Seconds (5*$attempt)
  } finally {if($response){$response.Dispose()};if($request){$request.Dispose()};if($inputStream){$inputStream.Dispose()}}
 }
 if(!$completed){throw 'Upload did not complete'}
} finally {$uploadClient.Dispose();$uploadSecret=$null;$uploadCredential=$null;$uploadTokenLine=$null}
