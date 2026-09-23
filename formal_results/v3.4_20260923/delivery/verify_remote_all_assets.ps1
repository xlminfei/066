#requires -Version 7.0
param([Parameter(Mandatory)][string]$PublicationDirectory,[Parameter(Mandatory)][string]$RepositoryDirectory,[Parameter(Mandatory)][long]$ReleaseId)
$ErrorActionPreference='Stop';$env:GIT_TERMINAL_PROMPT='0';$env:GCM_INTERACTIVE='Never'
$query=@('protocol=https','host=github.com','path=xlminfei/066.git','','')-join [char]10
$cred=@($query|git -C $RepositoryDirectory -c credential.interactive=never credential fill)
if($LASTEXITCODE-ne 0){throw 'Credential helper failed'}
$line=@($cred|Where-Object{$_.StartsWith('password=')});if($line.Count-ne 1){throw 'Credential unavailable'}
$secret=$line[0].Substring(9);$client=[Net.Http.HttpClient]::new();$client.Timeout=[TimeSpan]::FromMinutes(3)
$client.DefaultRequestHeaders.Authorization=[Net.Http.Headers.AuthenticationHeaderValue]::new('Bearer',$secret)
$client.DefaultRequestHeaders.UserAgent.ParseAdd('ratio-formal-release-verifier');$client.DefaultRequestHeaders.Accept.ParseAdd('application/vnd.github+json');$client.DefaultRequestHeaders.Add('X-GitHub-Api-Version','2022-11-28')
try {
 $assets=[Collections.Generic.List[object]]::new();$page=1
 do{$batch=@($client.GetStringAsync("https://api.github.com/repos/xlminfei/066/releases/$ReleaseId/assets?per_page=100&page=$page").GetAwaiter().GetResult()|ConvertFrom-Json);foreach($a in $batch){$assets.Add($a)};$page++}while($batch.Count-eq 100)
 $plan=Get-Content -LiteralPath (Join-Path $PublicationDirectory 'upload_plan_final.json') -Raw|ConvertFrom-Json
 $verified=[Collections.Generic.List[object]]::new();$issues=[Collections.Generic.List[string]]::new()
 foreach($expected in $plan.assets){$m=@($assets|Where-Object name -eq $expected.name);if($m.Count-ne 1){$issues.Add('Missing or duplicate '+$expected.name);continue};$a=$m[0];$pass=$a.state-eq 'uploaded'-and $a.size-eq $expected.bytes-and $a.digest-eq ('sha256:'+$expected.sha256);if(!$pass){$issues.Add('Metadata mismatch '+$expected.name)};$verified.Add([pscustomobject]@{name=$a.name;id=$a.id;state=$a.state;bytes=$a.size;sha256=$expected.sha256;server_digest=$a.digest;url=$a.browser_download_url;pass=$pass})}
 $unlisted=@($assets|Where-Object name -notin $plan.assets.name);if($unlisted.Count){$issues.Add('Unexpected release assets')}
 $release=$client.GetStringAsync("https://api.github.com/repos/xlminfei/066/releases/$ReleaseId").GetAwaiter().GetResult()|ConvertFrom-Json
 if($release.draft-or $release.tag_name-ne 'v3.4-formal-results'){$issues.Add('Release publication state mismatch')}
 $report=[ordered]@{status=$(if($issues.Count-eq 0){'PASS'}else{'FAIL'});release_id=$ReleaseId;expected_assets=$plan.assets.Count;verified=$verified.Count;issues=$issues.ToArray();checked_at=[DateTimeOffset]::UtcNow.ToString('o');assets=$verified.ToArray()}
 $report|ConvertTo-Json -Depth 6|Set-Content -LiteralPath (Join-Path $PublicationDirectory 'remote_delivery_verification.json') -Encoding utf8
 [pscustomobject]@{status=$report.status;verified=$verified.Count;expected=$plan.assets.Count;issues=$issues.ToArray()}|ConvertTo-Json -Depth 3
 if($issues.Count-ne 0){exit 1}
}finally{$client.Dispose();$secret=$null;$cred=$null;$line=$null}
