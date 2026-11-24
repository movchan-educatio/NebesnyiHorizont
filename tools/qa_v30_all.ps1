param(
    [string]$Godot = ".\Godot_v4.6.1-stable_win64_console.exe",
    [string]$Project = ".",
    [string]$OutDir = "qa_shots\v30_all"
)

$ErrorActionPreference = "Continue"
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$tests = @(
    "res://test/qa_v30_systems.tscn",
    "res://test/qa_v30_maps.tscn",
    "res://test/qa_v30_water.tscn",
    "res://test/qa_v30_drone_colors.tscn",
    "res://test/qa_v30_oilrig_materials.tscn",
    "res://test/qa_airport_missions.tscn",
    "res://test/test_special_missions.tscn",
    "res://test/qa_all20_fixes.tscn",
    "res://test/qa_mobile_mission_completion.tscn",
    "res://test/qa_all_drones_flight.tscn",
    "res://test/qa_prop_animation.tscn",
    "res://test/test_release_readiness.tscn"
)

$failed = @()
foreach ($t in $tests) {
    $name = [IO.Path]::GetFileNameWithoutExtension($t)
    $log = Join-Path $OutDir ($name + ".log")
    Write-Host "==> $name"
    & $Godot --headless --path $Project --quit-after 20000 $t *>&1 |
        Tee-Object -FilePath $log | Out-Null
    $code = $LASTEXITCODE
    $text = Get-Content $log -Raw
    $bad = $text -match 'SCRIPT ERROR|USER ERROR|Parse Error'
    $fail = $text -match 'failures?=[1-9]|\[FAIL\]| FAIL |RESULT FAIL'
    if ($code -ne 0 -or $bad -or $fail) {
        $failed += $name
        Write-Host "    FAIL (exit $code)" -ForegroundColor Red
    } else {
        Write-Host "    PASS" -ForegroundColor Green
    }
}

if ($failed.Count -gt 0) {
    Write-Host "FAILED: $($failed -join ', ')" -ForegroundColor Red
    exit 1
}
Write-Host "ALL V30 QA PASSED" -ForegroundColor Green
exit 0
