param(
    [string]$Godot = ".\Godot_v4.6.1-stable_win64_console.exe",
    [string]$Project = ".",
    [string]$OutDir = "qa_shots/deep_all_maps",
    [string[]]$Maps = @("steppe", "village", "industrial", "wetlands", "airport", "lis_forest_freestyle")
)

$ErrorActionPreference = "Continue"
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$failed = @()
foreach ($map in $Maps) {
    $env:QA_MAP = $map
    foreach ($suite in @(
        @{ Scene = "res://test/qa_airport_missions.tscn"; Name = "missions" },
        @{ Scene = "res://test/qa_mobile_missions_audit.tscn"; Name = "mobile-audit" }
    )) {
        $tag = "$($map)_$($suite.Name)"
        $log = Join-Path $OutDir ($tag + ".log")
        Write-Host "==> $tag"
        & $Godot --headless --path $Project --quit-after 420000 $suite.Scene *>&1 |
            Tee-Object -FilePath $log | Out-Null
        $code = $LASTEXITCODE
        $text = Get-Content $log -Raw
        $hasError = $text -match 'SCRIPT ERROR|USER ERROR|Parse Error'
        $clean = ($text -match 'failures=0') -and ($text -notmatch '\[MAP-QA:[^\]]+\] FAIL|\[MOB-QA:[^\]]+\] FAIL') -and (-not $hasError)
        if ($code -ne 0 -or -not $clean) {
            $failed += $tag
            Write-Host "    FAIL (exit $code) -- see $log" -ForegroundColor Red
        } else {
            Write-Host "    PASS" -ForegroundColor Green
        }
    }
}
Remove-Item Env:QA_MAP -ErrorAction SilentlyContinue
if ($failed.Count -gt 0) {
    Write-Host "FAILED: $($failed -join ', ')" -ForegroundColor Red
    exit 1
}
Write-Host "ALL MAPS / ALL MISSIONS PASSED" -ForegroundColor Green
exit 0
