#requires -Version 7.0
param([Parameter(Mandatory)][string]$VersionDirectory,[Parameter(Mandatory)][string]$OutputDirectory)
$ErrorActionPreference='Stop'
$taskRoots=[ordered]@{'v3.2'=(Resolve-Path -LiteralPath $VersionDirectory).Path}
$taskOutput=[IO.Path]::GetFullPath($OutputDirectory)
foreach($taskSource in $taskRoots.Values){if($taskOutput.StartsWith($taskSource.TrimEnd([char]92)+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'Archive output must be outside the captured roots'}}
New-Item -ItemType Directory -Path $taskOutput -Force | Out-Null
$taskZip=Join-Path $taskOutput 'v3.2-complete-evidence.zip'
if(Test-Path -LiteralPath $taskZip){throw 'Refusing to replace an existing archive'}
$taskFiles=[Collections.Generic.List[object]]::new()
foreach($taskNs in $taskRoots.Keys){
 foreach($taskFile in (Get-ChildItem -LiteralPath $taskRoots[$taskNs] -File -Recurse -Force | Sort-Object FullName)){
  if($taskFile.LinkTarget){throw "Linked file requires explicit review: $($taskFile.FullName)"}
  $taskRel=[IO.Path]::GetRelativePath($taskRoots[$taskNs],$taskFile.FullName).Replace([char]92,[char]47)
  $taskFiles.Add([pscustomobject]@{Namespace=$taskNs;RelativePath=$taskRel;ArchivePath="$taskNs/$taskRel";Bytes=$taskFile.Length;SHA256=(Get-FileHash -LiteralPath $taskFile.FullName -Algorithm SHA256).Hash.ToLowerInvariant();SourcePath=$taskFile.FullName})
 }
}
$taskManifest=Join-Path $taskOutput 'v3.2-complete-evidence.files.csv'
$taskFiles | Select-Object Namespace,RelativePath,ArchivePath,Bytes,SHA256 | Export-Csv -LiteralPath $taskManifest -Encoding utf8 -NoTypeInformation
$taskReadme=Join-Path $taskOutput 'README_archive_zh.md'
@'
# v3.2 完整源码与测试证据快照

v3.2/ 包含本次交付目录的全部现存文件，未按扩展名或文件大小省略。包括全部原始合成 fit.rds、Beta编译对象、成功和失败尝试、中间目录、源码、说明与测试表。

review/ 内是测试/历史材料，不能当作真实研究结果。短链合成拟合允许记录诊断失败以验收接口；正式256项研究拟合保持未运行。

_archive/CONTENTS.csv逐文件列出路径、大小、SHA-256。归档完成后逐文件读回并比对源文件。归档后的压缩包收据、分片清单、远端上传收据与Git提交补丁独立发布，避免递归自包含。
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
"$taskZipHash  v3.2-complete-evidence.zip" | Set-Content -LiteralPath (Join-Path $taskOutput 'v3.2-complete-evidence.zip.sha256') -Encoding ascii
$taskReceipt=[ordered]@{status='LOCAL_ARCHIVE_VERIFIED';source_files=$taskFiles.Count;verified_files=$taskChecked;omitted_source_files=0;version_files=$taskFiles.Count;source_bytes=($taskFiles|Measure-Object Bytes -Sum).Sum;archive_bytes=(Get-Item -LiteralPath $taskZip).Length;archive_sha256=$taskZipHash;manifest_sha256=(Get-FileHash -LiteralPath $taskManifest -Algorithm SHA256).Hash.ToLowerInvariant()}
$taskReceipt | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $taskOutput 'v3.2-complete-evidence.build.json') -Encoding utf8
$taskReceipt | ConvertTo-Json
