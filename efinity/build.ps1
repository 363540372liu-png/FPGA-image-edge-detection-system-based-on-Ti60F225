$ErrorActionPreference = 'Stop'
$projectDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$efxRun = if ($env:EFINITY_RUN) { $env:EFINITY_RUN } else { 'efx_run.bat' }
Push-Location $projectDir
try {
    & $efxRun 'ti60f225_camera_display_baseline.xml' --prj --flow compile
    if ($LASTEXITCODE -ne 0) {
        throw "Efinity flow failed with exit code $LASTEXITCODE"
    }
}
finally {
    Pop-Location
}

