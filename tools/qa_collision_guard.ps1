# Ground-guard + terrain collision audit.
$proj = Split-Path $PSScriptRoot -Parent
$root = Split-Path $proj -Parent
$g = Join-Path $root "Godot_v4.6.1-stable_win64_console.exe"

$env:DRONE_GROUND_GUARD_TEST = "1"
foreach ($m in @("Village", "Industrial", "Steppe", "Wetlands")) {
    & $g --path $proj --resolution 640x360 "res://sceneries/${m}Level.tscn" 2>&1 | Select-String -Pattern "GUARD"
}
Remove-Item Env:DRONE_GROUND_GUARD_TEST -ErrorAction SilentlyContinue

& $g --headless --path $proj res://test/test_terrain_collision.tscn 2>&1 | Select-String -Pattern "\[COL\]|RESULT"
