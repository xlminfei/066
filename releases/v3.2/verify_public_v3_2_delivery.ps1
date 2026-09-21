#requires -Version 7.0
param([Parameter(Mandatory)][string]$DeliveryDirectory)
$ErrorActionPreference='Stop'
$client=[Net.Http.HttpClient]::new();$client.Timeout=[TimeSpan]::FromMinutes(5)
# Deliberately no credential: verify the user's public download path.
$client.DefaultRequestHeaders.UserAgent.ParseAdd('ratio-v3.2-public-readback')
try{
 $release=$client.GetStringAsync('https://api.github.com/repos/xlminfei/066/releases/tags/v3.2').GetAwaiter().GetResult()|ConvertFrom-Json
 if($release.draft -or $release.tag_name -ne 'v3.2' -or $release.id -ne 393166329){throw 'Public release identity/status mismatch'}
 $assets=@($client.GetStringAsync('https://api.github.com/repos/xlminfei/066/releases/393166329/assets?per_page=100').GetAwaiter().GetResult()|ConvertFrom-Json)
 $expected=@(Get-ChildItem -LiteralPath (Join-Path $DeliveryDirectory 'upload_receipts') -File|ForEach-Object{Get-Content -Raw -LiteralPath $_.FullName|ConvertFrom-Json})
 if($expected.Count -ne 80 -or $assets.Count -ne $expected.Count){throw 'Public asset count mismatch'}
 $verified=@(foreach($e in $expected){
  $a=@($assets|Where-Object name -eq $e.name)
  if($a.Count -ne 1 -or $a[0].state -ne 'uploaded' -or $a[0].size -ne $e.bytes -or $a[0].digest -ne ('sha256:'+$e.sha256)){throw ('Public asset mismatch: '+$e.name)}
  [pscustomobject]@{name=$e.name;bytes=$a[0].size;sha256=$e.sha256;server_digest=$a[0].digest;url=$a[0].browser_download_url}
 })
 $downloadChecks=@(foreach($name in @('v3.2-complete-evidence.zip.part001','v3.2-complete-evidence.zip.part061','v3.2-complete-evidence.parts.json')){
  $e=$verified|Where-Object name -eq $name
  $bytes=$client.GetByteArrayAsync($e.url).GetAwaiter().GetResult()
  $hash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant()
  if($bytes.Length -ne $e.bytes -or $hash -ne $e.sha256){throw ('Public byte download mismatch: '+$name)}
  [pscustomobject]@{name=$name;bytes=$bytes.Length;sha256=$hash;unauthenticated_download_verified=$true}
  Write-Host ('PUBLIC_DOWNLOAD_VERIFIED '+$name)
 })
 $receipt=[ordered]@{status='PUBLISHED_ALL80_ASSETS_PUBLICLY_VERIFIED';release_id=$release.id;tag='v3.2';url=$release.html_url;published_at=$release.published_at;code_commit='e7066c0dae21624cb7ac66cf9801163ed68b1593';assets_verified=$verified.Count;source_files=280;native_RDS_files=47;source_files_omitted=0;archive_bytes=1007573820;archive_sha256='51a577666046b0d667534485df6626a61bd59c35f589b46d7e0ddb553ce83c56';formal_research_fits=0;assets=$verified;public_download_checks=$downloadChecks;checked_at=(Get-Date).ToString('o')}
 $receipt|ConvertTo-Json -Depth 7|Set-Content -LiteralPath (Join-Path $DeliveryDirectory 'remote_delivery_verification.json') -Encoding utf8
 Write-Output ('PUBLIC_RELEASE_VERIFIED assets='+$verified.Count+'; actual downloaded samples='+$downloadChecks.Count)
}finally{$client.Dispose()}
