$ErrorActionPreference = 'Stop'
$efxRun = $env:EFINITY_EFX_RUN
if ([string]::IsNullOrWhiteSpace($efxRun)) { $efxRun = 'efx_run.bat' }
$projectDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectPrefix = [System.IO.Path]::GetFullPath($projectDir).TrimEnd('\') + '\'

# Efinity appends some logs when an existing outflow directory is reused.
# Remove only this independent project's generated work directories so every
# archived warning/timing report belongs to exactly one reproducible build.
foreach ($generatedName in @('outflow', 'work_syn', 'work_pnr')) {
    $generatedPath = [System.IO.Path]::GetFullPath(
        (Join-Path $projectDir $generatedName)
    )
    if (-not $generatedPath.StartsWith(
        $projectPrefix, [System.StringComparison]::OrdinalIgnoreCase
    )) {
        throw "Refusing to clean generated path outside project: $generatedPath"
    }
    if (Test-Path -LiteralPath $generatedPath) {
        Remove-Item -LiteralPath $generatedPath -Recurse -Force
    }
}

Push-Location $projectDir
try {
    & $efxRun phase_camera_display_640x480_stability_fix.xml --prj --flow compile
    if ($LASTEXITCODE -ne 0) {
        throw "Efinity flow failed with exit code $LASTEXITCODE"
    }

    $outflow = Join-Path $projectDir 'outflow'
    $bitDir = Join-Path $projectDir 'bitstream'
    $reportDir = Join-Path $projectDir 'reports'
    New-Item -ItemType Directory -Force -Path $bitDir, $reportDir | Out-Null

    $candidate = Join-Path $bitDir 'phase_camera_display_640x480_stability_fix.bit'
    Copy-Item -LiteralPath (Join-Path $outflow 'phase_camera_display_640x480_stability_fix.bit') `
        -Destination $candidate -Force

    foreach ($name in @(
        'phase_camera_display_640x480_stability_fix.timing.rpt',
        'phase_camera_display_640x480_stability_fix.map.rpt',
        'phase_camera_display_640x480_stability_fix.pt.rpt',
        'phase_camera_display_640x480_stability_fix.pt_timing.rpt',
        'phase_camera_display_640x480_stability_fix.pinout.rpt',
        'phase_camera_display_640x480_stability_fix.pinout.csv',
        'phase_camera_display_640x480_stability_fix.cdc.rpt',
        'phase_camera_display_640x480_stability_fix.warn.log',
        'phase_camera_display_640x480_stability_fix.err.log',
        'phase_camera_display_640x480_stability_fix.route.rpt',
        'phase_camera_display_640x480_stability_fix.place.rpt',
        'phase_camera_display_640x480_stability_fix.hier_util.rpt',
        'phase_camera_display_640x480_stability_fix.res.csv'
    )) {
        Copy-Item -LiteralPath (Join-Path $outflow $name) `
            -Destination (Join-Path $reportDir $name) -Force
    }

    $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $candidate).Hash
    Set-Content -LiteralPath (Join-Path $bitDir 'SHA256.txt') `
        -Value "$hash  phase_camera_display_640x480_stability_fix.bit"
    @"
PowerShell command:
  & .\build.ps1

Efinity command executed by build.ps1:
  $efxRun phase_camera_display_640x480_stability_fix.xml --prj --flow compile

Result: synthesis PASS, interface PASS, place-and-route PASS, bitstream generation PASS.
Bitstream SHA-256: $hash
"@ | Set-Content -LiteralPath (Join-Path $reportDir 'build_command.txt')
    Write-Host "Candidate SHA-256: $hash"
}
finally {
    Pop-Location
}
