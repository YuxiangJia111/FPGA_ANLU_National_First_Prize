param(
    [string]$ModelSimBin = 'D:\ModelSim\modelsim_ase\win32aloem',
    [string]$AnlogicSimRoot = 'D:\Anlogic\sim_release'
)
$ErrorActionPreference = 'Stop'
$repoPath = Split-Path -Parent $PSScriptRoot
Push-Location -LiteralPath $repoPath
try {
    $workPath = 'sim/.tracking_work'
    if (!(Test-Path -LiteralPath "$workPath/_info")) {
        & "$ModelSimBin/vlib.exe" $workPath
        if ($LASTEXITCODE -ne 0) { throw 'vlib failed' }
    }
    $sources = @(
        'user_source/hdl_source/digit_motion_tracker.v',
        'user_source/hdl_source/digit_motion_arrow_osd.v',
        'user_source/hdl_source/digit_track_osd.v',
        'user_source/hdl_source/digit_multi_bbox.v',
        'user_source/hdl_source/frame_diff_motion.v',
        'user_source/hdl_source/motion_block_osd.v',
        'user_source/hdl_source/osd_char_lib.v',
        'user_source/hdl_source/key_remove_shakes.v',
        'user_source/hdl_source/control_top.v',
        'user_source/hdl_source/display_top.v',
        'user_source/hdl_source/hdmi_mixer.v',
        'user_source/hdl_source/anlogic_logo_rom.v',
        'user_source/hdl_source/design_top_wrapper.v',
        'user_source/hdl_source/lcd_mode_display.v',
        'user_source/hdl_source/lcd_hw_test.v',
        'sim/digit_motion_tracker_tb.sv',
        'sim/digit_motion_direction_tb.sv',
        'sim/digit_motion_fusion_tb.sv',
        'sim/digit_motion_arrow_osd_tb.sv',
        'sim/digit_motion_arrow_mixer_tb.sv',
        'sim/hdmi_mixer_pixel_stream_tb.sv',
        'sim/digit_tracker_eram_equivalence_tb.sv',
        'sim/digit_tracker_vtc_tb.sv',
        'user_source/hdl_source/vtc/uivtc.v',
        'sim/reference/digit_motion_tracker_legacy.v',
        'sim/reference/hdmi_mixer_pre_counter_pipeline.v',
        'sim/digit_track_ui_tb.sv',
        'sim/frame_diff_motion_tb.sv',
        'sim/frame_diff_fullsize_tb.sv',
        'sim/motion_block_osd_tb.sv',
        'sim/motion_gray_reuse_tb.sv',
        "$AnlogicSimRoot/ph1p/ph1p_logic_eram.v",
        "$AnlogicSimRoot/ph1p/ph1p_phy_gsr.v",
        'td_project/al_ip/bbox_gray_frame_ram_ip/bbox_gray_frame_ram_ip.v',
        'td_project/al_ip/bbox_gray_frame_ram_ip/RTL/ram_e78534da668e.v',
        'td_project/al_ip/bbox_bitmap_ram/bbox_bitmap_ram.v',
        'td_project/al_ip/bbox_bitmap_ram/RTL/ram_dfdc807800d8.v'
    )
    $trackerIpPath = 'td_project/al_ip/digit_tracker_state_ram_adapter/digit_tracker_state_ram_adapter.v'
    if (Test-Path -LiteralPath $trackerIpPath) {
        Write-Output 'Tracker tests use the user-generated TD IP.'
        $sources += $trackerIpPath
        $sources += @(Get-ChildItem -LiteralPath 'td_project/al_ip/digit_tracker_state_ram_adapter/RTL' `
            -Recurse -Filter '*.v' | ForEach-Object { $_.FullName })
    } else {
        Write-Output 'Tracker tests use a simulation-only vendor binding; generate the TD IP before synthesis.'
        $sources += 'sim/digit_tracker_state_ram_ip_sim.v'
    }
    & "$ModelSimBin/vlog.exe" -sv -work $workPath @sources
    if ($LASTEXITCODE -ne 0) { throw 'RTL compilation failed' }
    foreach ($testName in @('digit_motion_tracker_tb', 'digit_track_ui_tb',
            'frame_diff_motion_tb', 'frame_diff_fullsize_tb', 'motion_block_osd_tb', 'motion_gray_reuse_tb',
            'digit_tracker_eram_equivalence_tb', 'digit_tracker_vtc_tb',
            'digit_motion_direction_tb', 'digit_motion_fusion_tb', 'digit_motion_arrow_osd_tb', 'digit_motion_arrow_mixer_tb', 'hdmi_mixer_pixel_stream_tb')) {
        $logPath = "$workPath/$testName.log"
        $extraTops = @()
        if ($testName -in @('motion_gray_reuse_tb', 'digit_tracker_eram_equivalence_tb',
                'digit_tracker_vtc_tb', 'digit_motion_direction_tb', 'digit_motion_fusion_tb')) {
            $extraTops = @('PH1P_PHY_GSR')
        }
        $runCommands = 'run -all; quit -f'
        if ($testName -eq 'hdmi_mixer_pixel_stream_tb') {
            # The real logo ROM loads its checked-in memory relative to cwd.
            $runCommands = 'cd user_source/hdl_source; run -all; quit -f'
        }
        # -batch avoids this installation's interactive FileWatch startup error.
        & "$ModelSimBin/vsim.exe" -batch -onfinish stop -lib $workPath $testName @extraTops `
            -do $runCommands -l $logPath
        if ($LASTEXITCODE -ne 0) { throw "$testName failed to run" }
        $logText = Get-Content -LiteralPath $logPath -Raw
        if ($logText -notmatch 'PASS:' -or $logText -match '\*\* (Fatal|Error):') {
            throw "$testName did not pass; see $logPath"
        }
    }
    $logPath = "$workPath/motion_gray_reuse_model.log"
    & "$ModelSimBin/vsim.exe" -batch -onfinish stop -lib $workPath -gUSE_ERAM=0 motion_gray_reuse_tb PH1P_PHY_GSR `
        -do 'run -all; quit -f' -l $logPath
    if ($LASTEXITCODE -ne 0) { throw 'RAM fallback test failed to run' }
    $logText = Get-Content -LiteralPath $logPath -Raw
    if ($logText -notmatch 'PASS:' -or $logText -match '\*\* (Fatal|Error):') {
        throw 'RAM fallback test did not pass'
    }
    foreach ($testCase in @(
        @{ Name='digit_motion_tracker_tb'; Param='-gUSE_ERAM=1'; Log='tracker_eram_vendor' },
        @{ Name='digit_tracker_eram_equivalence_tb'; Param='-gUSE_ERAM=0'; Log='tracker_equivalence_model' },
        @{ Name='digit_motion_direction_tb'; Param='-gUSE_ERAM=0'; Log='direction_model' },
        @{ Name='digit_motion_fusion_tb'; Param='-gUSE_ERAM=0'; Log='fusion_model' }
    )) {
        $logPath = "$workPath/$($testCase.Log).log"
        & "$ModelSimBin/vsim.exe" -batch -onfinish stop -lib $workPath $testCase.Param $testCase.Name PH1P_PHY_GSR `
            -do 'run -all; quit -f' -l $logPath
        if ($LASTEXITCODE -ne 0) { throw "$($testCase.Name) failed to run" }
        $logText = Get-Content -LiteralPath $logPath -Raw
        if ($logText -notmatch 'PASS:' -or $logText -match '\*\* (Fatal|Error):') {
            throw "$($testCase.Name) did not pass"
        }
    }
    Write-Output 'PASS: tracking/motion RTL compilation and all eighteen behavioral runs'
} finally {
    Pop-Location
}
