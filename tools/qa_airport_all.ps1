param(
    [string]$Godot = ".\Godot_v4.6.1-stable_win64_console.exe",
    [string]$Project = ".",
    [string]$OutDir = "qa_shots"
)

$ErrorActionPreference = "Continue"
$tests = @(
    @{ Scene = "res://test/qa_airport_missions.tscn";       Name = "airport-missions" },
    @{ Scene = "res://test/qa_mobile_missions_audit.tscn";  Name = "mobile-missions-audit" },
    @{ Scene = "res://test/qa_convoy_recovery.tscn";        Name = "convoy-recovery" },
    @{ Scene = "res://test/qa_vehicle_watchdog.tscn";       Name = "vehicle-watchdog" },
    @{ Scene = "res://test/qa_air_kill.tscn";               Name = "air-kill" },
    @{ Scene = "res://test/test_special_missions.tscn";     Name = "special-missions" },
    @{ Scene = "res://test/qa_structure_avoidance.tscn";    Name = "structure-avoidance" },
    @{ Scene = "res://test/qa_milestone2_visuals_and_missions.tscn"; Name = "milestone2-visuals-missions" },
    @{ Scene = "res://test/qa_respawn_fpv_view.tscn";       Name = "respawn-fpv-view" }
)

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$failed = @()
foreach ($t in $tests) {
    $log = Join-Path $OutDir ("qa_" + $t.Name + ".log")
    Write-Host "==> $($t.Name): $($t.Scene)"
    # --quit-after is a hard safety net: no QA can ever hang the session.
    & $Godot --headless --path $Project --quit-after 420000 $t.Scene *>&1 |
        Tee-Object -FilePath $log | Out-Null
    $code = $LASTEXITCODE
    $text = Get-Content $log -Raw
    $hasError = $text -match 'SCRIPT ERROR|USER ERROR|Parse Error'
    $clean = ($text -match '(failures?=0|RESULT PASS|ALL QA PASSED)') -and (-not $hasError)
    if ($code -ne 0 -or -not $clean) {
        $failed += $t.Name
        Write-Host "    FAIL (exit $code) -- see $log" -ForegroundColor Red
    } else {
        Write-Host "    PASS" -ForegroundColor Green
    }
}
if ($failed.Count -gt 0) {
    Write-Host "FAILED: $($failed -join ', ')" -ForegroundColor Red
    exit 1
}
Write-Host "ALL QA PASSED" -ForegroundColor Green
exit 0
