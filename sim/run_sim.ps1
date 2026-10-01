$ErrorActionPreference = 'Stop'
$sim = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $sim
$ivl = if ($env:EFINITY_IVL) { $env:EFINITY_IVL } else { 'iverilog' }
$vvp = if ($env:EFINITY_VVP) { $env:EFINITY_VVP } else { 'vvp' }
$ramModel = if ($env:EFINITY_SIM_RAM_MODEL) { $env:EFINITY_SIM_RAM_MODEL } else { throw 'Set EFINITY_SIM_RAM_MODEL to Efinity sim_models/verilog/efx_ram10.v before running this regression.' }
New-Item -ItemType Directory -Force -Path $sim | Out-Null

function Run-Test($name, $sources) {
    $compileLog = Join-Path $sim ($name + '_compile.log')
    $runLog = Join-Path $sim ($name + '_run.log')
    & $ivl -g2012 -Wall -s $name -o (Join-Path $sim ($name + '.vvp')) @sources 2>&1 |
        Tee-Object -FilePath $compileLog
    if ($LASTEXITCODE -ne 0) { throw "$name compile failed ($LASTEXITCODE)" }
    & $vvp (Join-Path $sim ($name + '.vvp')) 2>&1 | Tee-Object -FilePath $runLog
    if ($LASTEXITCODE -ne 0) { throw "$name run failed ($LASTEXITCODE)" }
}

Run-Test 'tb_dvp_capture' @(
    (Join-Path $root 'rtl\dvp_rgb565_capture.sv'),
    (Join-Path $root 'rtl\camera_frame_monitor.sv'),
    (Join-Path $sim 'tb\tb_dvp_capture.sv')
)

Run-Test 'tb_dvp_to_framebuffer_recovery' @(
    (Join-Path $root 'rtl\dvp_rgb565_capture.sv'),
    (Join-Path $root 'rtl\camera_frame_monitor.sv'),
    (Join-Path $root 'rtl\frame_ram20.sv'),
    (Join-Path $root 'rtl\packed_pingpong_framebuffer.sv'),
    (Join-Path $sim 'tb\tb_dvp_to_framebuffer_recovery.sv')
)

Run-Test 'tb_snapshot_cdc' @(
    (Join-Path $root 'rtl\snapshot_cdc.sv'),
    (Join-Path $sim 'tb\tb_snapshot_cdc.sv')
)

Run-Test 'tb_packed_pingpong_framebuffer' @(
    $ramModel,
    (Join-Path $root 'rtl\frame_ram20.sv'),
    (Join-Path $root 'rtl\packed_pingpong_framebuffer.sv'),
    (Join-Path $sim 'tb\tb_packed_pingpong_framebuffer.sv')
)

Run-Test 'tb_full_frame_commit' @(
    (Join-Path $root 'rtl\packed_pingpong_framebuffer.sv'),
    (Join-Path $sim 'tb\tb_full_frame_commit.sv')
)

Run-Test 'tb_display_diagnostic_overlay' @(
    (Join-Path $root 'rtl\display_diagnostic_overlay.sv'),
    (Join-Path $sim 'tb\tb_display_diagnostic_overlay.sv')
)

Run-Test 'tb_official_ov5640_rom' @(
    (Join-Path $root 'rtl\vendor\I2C_OV5640_1280720_Config.v'),
    (Join-Path $sim 'tb\tb_official_ov5640_rom.sv')
)

$rtl = Get-ChildItem -LiteralPath (Join-Path $root 'rtl') -Recurse -File |
    Where-Object { $_.FullName -notmatch '\\rtl\\rtl\\' -and $_.Extension -in '.sv', '.v' -and $_.Name -ne 'phase_camera_display_passthrough.sv' -and $_.Name -ne 'ov5640_init_rom.sv' } |
    ForEach-Object FullName
$topLog = Join-Path $sim 'top_syntax_compile.log'
& $ivl -g2012 -Wall -s phase_camera_display_official_waveshare `
    -o (Join-Path $sim 'top_syntax.vvp') `
    $ramModel @rtl 2>&1 | Tee-Object -FilePath $topLog
if ($LASTEXITCODE -ne 0) { throw "top syntax compile failed ($LASTEXITCODE)" }

Write-Host 'ALL OFFICIAL-CAMERA WAVESHARE OFFLINE TESTS PASSED'
