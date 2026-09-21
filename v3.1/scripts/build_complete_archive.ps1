#requires -Version 7.0
param([Parameter(Mandatory)][string]$WorkingDirectory,[Parameter(Mandatory)][string]$VersionDirectory,[Parameter(Mandatory)][string]$OutputDirectory)
$ErrorActionPreference='Stop'
$taskRoots=[ordered]@{'working-v3'=(Resolve-Path -LiteralPath $WorkingDirectory).Path;'published-v3.1'=(Resolve-Path -LiteralPath $VersionDirectory).Path}
$taskOutput=[IO.Path]::GetFullPath($OutputDirectory)
foreach($taskSource in $taskRoots.Values){if($taskOutput.StartsWith($taskSource.TrimEnd([char]92)+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'Archive output must be outside the captured roots'}}
New-Item -ItemType Directory -Path $taskOutput -Force | Out-Null
$taskZip=Join-Path $taskOutput 'v3.1-complete-evidence.zip'
if(Test-Path -LiteralPath $taskZip){throw 'Refusing to replace an existing archive'}
$taskFiles=[Collections.Generic.List[object]]::new()
foreach($taskNs in $taskRoots.Keys){
 foreach($taskFile in (Get-ChildItem -LiteralPath $taskRoots[$taskNs] -File -Recurse -Force | Sort-Object FullName)){
  if($taskFile.LinkTarget){throw "Linked file requires explicit review: $($taskFile.FullName)"}
  $taskRel=[IO.Path]::GetRelativePath($taskRoots[$taskNs],$taskFile.FullName).Replace([char]92,[char]47)
  $taskFiles.Add([pscustomobject]@{Namespace=$taskNs;RelativePath=$taskRel;ArchivePath="$taskNs/$taskRel";Bytes=$taskFile.Length;SHA256=(Get-FileHash -LiteralPath $taskFile.FullName -Algorithm SHA256).Hash.ToLowerInvariant();SourcePath=$taskFile.FullName})
 }
}
$taskManifest=Join-Path $taskOutput 'v3.1-complete-evidence.files.csv'
$taskFiles | Select-Object Namespace,RelativePath,ArchivePath,Bytes,SHA256 | Export-Csv -LiteralPath $taskManifest -Encoding utf8 -NoTypeInformation
$taskReadme=Join-Path $taskOutput 'README_archive_zh.md'
@'
# v3.1 完整资料快照

working-v3/ 是本次工作原始目录的全部现存文件，包括原始fit.rds、早期smoke、调试日志和修改前代码快照。
published-v3.1/ 是补充说明时的当前发行目录，包含当前代码、逐项修改说明、明确标识的绘图夹具与测试证据。

这些目录中的历史/中间文件不是全部有效的生产结果。目录名含visual_fixture的图片是合成布局测试；早期等值图不是真实物种预测；正式研究的256项拟合尚未启动。

_archive/CONTENTS.csv列出每个源文件的相对路径、大小和SHA-256。归档构建后逐项读回校验；没有按扩展名或大小省略源文件。
Github上传收据和此快照完成之后形成的提交差异附件独立发布，不递归包含在本ZIP中。
'@ | Set-Content -LiteralPath $taskReadme -Encoding utf8
$taskStream=[IO.File]::Open($taskZip,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
$taskArchive=[IO.Compression.ZipArchive]::new($taskStream,[IO.Compression.ZipArchiveMode]::Create,$false)
$taskDone=0
try {
 foreach($taskRow in $taskFiles){
  $taskEntry=$taskArchive.CreateEntry($taskRow.ArchivePath,[IO.Compression.CompressionLevel]::Optimal)
  $taskInput=[IO.File]::OpenRead($taskRow.SourcePath);$taskDest=$taskEntry.Open()
  try{$taskInput.CopyTo($taskDest)}finally{$taskDest.Dispose();$taskInput.Dispose()}
  $taskDone++
  if($taskDone%25 -eq 0){Write-Output "PACK $taskDone / $($taskFiles.Count)"}
 }
 foreach($taskPair in @(@($taskManifest,'_archive/CONTENTS.csv'),@($taskReadme,'_archive/README.md'))){
  $taskEntry=$taskArchive.CreateEntry($taskPair[1],[IO.Compression.CompressionLevel]::Optimal)
  $taskInput=[IO.File]::OpenRead($taskPair[0]);$taskDest=$taskEntry.Open()
  try{$taskInput.CopyTo($taskDest)}finally{$taskDest.Dispose();$taskInput.Dispose()}
 }
}finally{$taskArchive.Dispose()}
$taskArchive=[IO.Compression.ZipFile]::OpenRead($taskZip)
$taskChecked=0
try {
 if($taskArchive.Entries.Count -ne $taskFiles.Count+2){throw 'Archive entry count mismatch'}
 foreach($taskRow in $taskFiles){
  $taskEntry=$taskArchive.GetEntry($taskRow.ArchivePath)
  if(!$taskEntry -or $taskEntry.Length -ne $taskRow.Bytes){throw "Missing/wrong-size archive entry: $($taskRow.ArchivePath)"}
  $taskInput=$taskEntry.Open()
  try{$taskHash=(Get-FileHash -InputStream $taskInput -Algorithm SHA256).Hash.ToLowerInvariant()}finally{$taskInput.Dispose()}
  if($taskHash -ne $taskRow.SHA256){throw "Archive checksum mismatch: $($taskRow.ArchivePath)"}
  if((Get-FileHash -LiteralPath $taskRow.SourcePath -Algorithm SHA256).Hash.ToLowerInvariant() -ne $taskRow.SHA256){throw "Source changed while packaging: $($taskRow.ArchivePath)"}
  $taskChecked++
 }
}finally{$taskArchive.Dispose()}
$taskZipHash=(Get-FileHash -LiteralPath $taskZip -Algorithm SHA256).Hash.ToLowerInvariant()
"$taskZipHash  v3.1-complete-evidence.zip" | Set-Content -LiteralPath (Join-Path $taskOutput 'v3.1-complete-evidence.zip.sha256') -Encoding ascii
$taskReceipt=[ordered]@{status='LOCAL_ARCHIVE_VERIFIED';source_files=$taskFiles.Count;verified_files=$taskChecked;omitted_source_files=0;working_files=@($taskFiles|Where-Object Namespace -eq 'working-v3').Count;published_files=@($taskFiles|Where-Object Namespace -eq 'published-v3.1').Count;source_bytes=($taskFiles|Measure-Object Bytes -Sum).Sum;archive_bytes=(Get-Item -LiteralPath $taskZip).Length;archive_sha256=$taskZipHash;manifest_sha256=(Get-FileHash -LiteralPath $taskManifest -Algorithm SHA256).Hash.ToLowerInvariant()}
$taskReceipt | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $taskOutput 'v3.1-complete-evidence.build.json') -Encoding utf8
$taskReceipt | ConvertTo-Json
