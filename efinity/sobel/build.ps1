$ErrorActionPreference = 'Stop'
$projectDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = (Resolve-Path (Join-Path $projectDir '..\..')).Path
$efxRun = $env:EFINITY_EFX_RUN
if ([string]::IsNullOrWhiteSpace($efxRun)) {
    $efxRun = 'efx_run.bat'
}
Push-Location $projectDir
try {
    & $efxRun 'phase_camera_display_640x480_sobel.xml' --prj --flow compile
    if ($LASTEXITCODE -ne 0) { throw "Efinity flow failed with exit code $LASTEXITCODE" }
    $outflow = Join-Path $projectDir 'outflow'
    $release = Join-Path $repoRoot 'releases\v0.2-basic-sobel-edge-detection'
    New-Item -ItemType Directory -Force -Path (Join-Path $release 'bitstream') | Out-Null
    Copy-Item (Join-Path $outflow 'phase_camera_display_640x480_sobel.bit') `
        (Join-Path $release 'bitstream\ti60f225_basic_sobel_edge_detection.bit') -Force
    $hash = (Get-FileHash (Join-Path $release 'bitstream\ti60f225_basic_sobel_edge_detection.bit') -Algorithm SHA256).Hash
    Set-Content (Join-Path $release 'SHA256SUMS.txt') "$hash  bitstream/ti60f225_basic_sobel_edge_detection.bit"
    Write-Host "Candidate SHA-256: $hash"
}
finally { Pop-Location }
