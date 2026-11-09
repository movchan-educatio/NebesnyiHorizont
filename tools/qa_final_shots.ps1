# Final vegetation + systems QA screenshots.  Runs one game instance at a time.
$ErrorActionPreference = "Continue"
$proj = Split-Path $PSScriptRoot -Parent
$root = Split-Path $proj -Parent
$g = Join-Path $root "Godot_v4.6.1-stable_win64_console.exe"
$outV = Join-Path $root "qa_shots\vegetation"
$outF = Join-Path $root "qa_shots\final"

Get-Process | Where-Object { $_.ProcessName -like "*Godot*" } | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

$env:DRONE_QUALITY = "ufds"
$env:SHOT_DELAY = "4"
foreach ($m in @("village", "industrial", "steppe", "wetlands")) {
    Remove-Item Env:CAM_POS -ErrorAction SilentlyContinue
    Remove-Item Env:CAM_TARGET -ErrorAction SilentlyContinue
    Remove-Item Env:AERIAL -ErrorAction SilentlyContinue
    Remove-Item Env:VEG_DEBUG -ErrorAction SilentlyContinue
    Remove-Item Env:DESTROY_DEMO -ErrorAction SilentlyContinue
    $env:MAP = $m
    $env:AERIAL = "1"
    $env:SHOT_PATH = Join-Path $outV "aerial_$m.png"
    & $g --path $proj --resolution 1280x720 res://test/test_terrain_preview.tscn 2>&1 | Select-String -Pattern "SHOT"
    Start-Sleep -Seconds 2
}

Remove-Item Env:AERIAL -ErrorAction SilentlyContinue
Remove-Item Env:VEG_DEBUG -ErrorAction SilentlyContinue
$env:MAP = "village"
$env:CAM_POS = "215,4.5,-60"
$env:CAM_TARGET = "200,5.5,-75"
$env:SHOT_PATH = Join-Path $outV "tree_close.png"
& $g --path $proj --resolution 1280x720 res://test/test_terrain_preview.tscn 2>&1 | Select-String -Pattern "SHOT"
Start-Sleep -Seconds 2

# Destruction demo: the village hospital is hit by a payload, rubble/smoke/crater.
Remove-Item Env:CAM_POS -ErrorAction SilentlyContinue
Remove-Item Env:CAM_TARGET -ErrorAction SilentlyContinue
$env:DESTROY_DEMO = "1"
$env:CAM_POS = "-150,18,150"
$env:CAM_TARGET = "-210,6,90"
$env:SHOT_DELAY = "5"
$env:SHOT_PATH = Join-Path $outV "destruction.png"
& $g --path $proj --resolution 1280x720 res://test/test_terrain_preview.tscn 2>&1 | Select-String -Pattern "SHOT|DEMO"
Start-Sleep -Seconds 2
Remove-Item Env:DESTROY_DEMO -ErrorAction SilentlyContinue

# Hero oak sway pair.
$env:VEG_DEBUG = "1"
$env:CAM_POS = "56,5,-40"
$env:CAM_TARGET = "48,4.5,-48"
$env:SHOT_DELAY = "3"
$env:SHOT_PATH = Join-Path $outV "hero_oak_sway_a.png"
& $g --path $proj --resolution 1280x720 res://test/test_terrain_preview.tscn 2>&1 | Select-String -Pattern "SHOT|FrontlineAssets"
Start-Sleep -Seconds 1
$env:SHOT_DELAY = "5.2"
$env:SHOT_PATH = Join-Path $outV "hero_oak_sway_b.png"
& $g --path $proj --resolution 1280x720 res://test/test_terrain_preview.tscn 2>&1 | Select-String -Pattern "SHOT"
Start-Sleep -Seconds 2

Remove-Item Env:MAP -ErrorAction SilentlyContinue
Remove-Item Env:CAM_POS -ErrorAction SilentlyContinue
Remove-Item Env:CAM_TARGET -ErrorAction SilentlyContinue
Remove-Item Env:VEG_DEBUG -ErrorAction SilentlyContinue
$env:SHOT_DELAY = "5"
foreach ($m in @("Village", "Industrial", "Steppe", "Wetlands")) {
    $env:DRONE_QUALITY = "ufds"
    $env:SHOT_PATH = Join-Path $outF "${m}Level.png"
    & $g --path $proj --resolution 1280x720 "res://sceneries/${m}Level.tscn" 2>&1 | Select-String -Pattern "SHOT"
    Start-Sleep -Seconds 2
}
$env:DRONE_QUALITY = "low"
$env:SHOT_PATH = Join-Path $outF "VillageLevel_LOW.png"
& $g --path $proj --resolution 1280x720 "res://sceneries/VillageLevel.tscn" 2>&1 | Select-String -Pattern "SHOT"
