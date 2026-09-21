#requires -Version 7.0
param([Parameter(Mandatory)][string]$RepositoryDirectory,[Parameter(Mandatory)][string]$DeliveryDirectory,[switch]$Publish)
$ErrorActionPreference='Stop'
$env:GIT_TERMINAL_PROMPT='0';$env:GCM_INTERACTIVE='Never'
$q=@('protocol=https','host=github.com','path=xlminfei/066.git','','') -join [char]10
$credential=@($q | git -C $RepositoryDirectory -c credential.interactive=never credential fill)
if($LASTEXITCODE -ne 0){throw 'Credential helper failed'}
$passwordLine=@($credential|Where-Object { $_.StartsWith('password=') })
if($passwordLine.Count -ne 1){throw 'No GitHub credential'}
$client=[Net.Http.HttpClient]::new();$client.Timeout=[TimeSpan]::FromMinutes(3)
$client.DefaultRequestHeaders.Authorization=[Net.Http.Headers.AuthenticationHeaderValue]::new('Bearer',$passwordLine[0].Substring(9))
$client.DefaultRequestHeaders.UserAgent.ParseAdd('ratio-v3.2-release')
$client.DefaultRequestHeaders.Accept.ParseAdd('application/vnd.github+json')
$client.DefaultRequestHeaders.Add('X-GitHub-Api-Version','2022-11-28')
try {
 $resp=$client.GetAsync('https://api.github.com/repos/xlminfei/066/releases/393166329').GetAwaiter().GetResult()
 if($resp.IsSuccessStatusCode){$release=$resp.Content.ReadAsStringAsync().GetAwaiter().GetResult()|ConvertFrom-Json}
 elseif([int]$resp.StatusCode -eq 404 -and !$Publish){
  $body=@{tag_name='v3.2';target_commitish='e7066c0dae21624cb7ac66cf9801163ed68b1593';name='v3.2 - numerical and audit fixes with complete synthetic evidence';body=(Get-Content -Raw -LiteralPath (Join-Path $DeliveryDirectory 'RELEASE_NOTES_v3_2.md'));draft=$true;prerelease=$false;make_latest='false'}|ConvertTo-Json -Depth 10
  $content=[Net.Http.StringContent]::new($body,[Text.Encoding]::UTF8,'application/json')
  $created=$client.PostAsync('https://api.github.com/repos/xlminfei/066/releases',$content).GetAwaiter().GetResult()
  if(!$created.IsSuccessStatusCode){throw ('Create failed '+[int]$created.StatusCode)}
  $release=$created.Content.ReadAsStringAsync().GetAwaiter().GetResult()|ConvertFrom-Json
 }else{throw ('Release lookup failed '+[int]$resp.StatusCode)}
 if($release.tag_name -ne 'v3.2'){throw 'Release identity mismatch'}
 if($Publish -and $release.draft){
  $body=@{draft=$false;make_latest='true'}|ConvertTo-Json
  $request=[Net.Http.HttpRequestMessage]::new([Net.Http.HttpMethod]::Patch,('https://api.github.com/repos/xlminfei/066/releases/'+$release.id))
  $request.Content=[Net.Http.StringContent]::new($body,[Text.Encoding]::UTF8,'application/json')
  $published=$client.SendAsync($request).GetAwaiter().GetResult()
  if(!$published.IsSuccessStatusCode){throw ('Publish failed '+[int]$published.StatusCode)}
  $release=$published.Content.ReadAsStringAsync().GetAwaiter().GetResult()|ConvertFrom-Json
 }
 $receipt=@{id=$release.id;tag=$release.tag_name;draft=$release.draft;url=$release.html_url;target_commitish=$release.target_commitish;published_at=$release.published_at}
 $receipt|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $DeliveryDirectory 'release_state.json') -Encoding utf8
 $receipt|ConvertTo-Json
}finally{$client.Dispose();$credential=$null;$passwordLine=$null}
