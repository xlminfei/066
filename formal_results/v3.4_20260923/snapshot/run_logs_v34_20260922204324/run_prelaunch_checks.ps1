param([Parameter(Mandatory=$true)][string]$VersionRoot,[Parameter(Mandatory=$true)][string]$LogDirectory,[Parameter(Mandatory=$true)][string]$ImageTag)
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
$containerRoot = '/project/v34'
function Invoke-CheckedDockerStep {
  param([string]$Step,[string[]]$DockerArguments)
  $stepStarted = [DateTimeOffset]::UtcNow.ToString('o')
  & docker @DockerArguments 2>&1 | Tee-Object -FilePath (Join-Path $LogDirectory ($Step + '.log'))
  $stepExit = $LASTEXITCODE
  [pscustomobject]@{step=$Step;arguments=$DockerArguments;startedAt=$stepStarted;finishedAt=[DateTimeOffset]::UtcNow.ToString('o');exitCode=$stepExit} | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $LogDirectory ($Step + '_exit.json')) -Encoding utf8
  if ($stepExit -ne 0) { throw ($Step + ' failed with exit code ' + $stepExit) }
}
Invoke-CheckedDockerStep -Step '01_build' -DockerArguments @('build','--progress=plain','-t',$ImageTag,$VersionRoot)
Invoke-CheckedDockerStep -Step '02_environment' -DockerArguments @('run','--rm','--mount',('type=bind,source='+$VersionRoot+',target='+$containerRoot+',readonly'),$ImageTag,'Rscript',($containerRoot+'/scripts/test_environment.R'))
Invoke-CheckedDockerStep -Step '03_regressions' -DockerArguments @('run','--rm','--mount',('type=bind,source='+$VersionRoot+',target='+$containerRoot),$ImageTag,'Rscript',($containerRoot+'/tests/run_v34_regressions.R'))
Invoke-CheckedDockerStep -Step '04_preflight' -DockerArguments @('run','--rm','--mount',('type=bind,source='+$VersionRoot+',target='+$containerRoot),$ImageTag,'Rscript',($containerRoot+'/src/v3_pipeline.R'),'--stage','preflight')
'PRELAUNCH_CHECKS_PASS'
