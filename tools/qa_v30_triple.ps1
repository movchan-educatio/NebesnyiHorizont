param(
    [int]$Runs = 3,
    [string]$OutDir = "qa_shots\v30_triple"
)

$ErrorActionPreference = "Continue"
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$failed = @()

foreach ($suite in @("qa_v30_all", "qa_all_maps_deep", "qa_airport_all")) {
    for ($run = 1; $run -le $Runs; $run++) {
        $tag = "${suite}_run$run"
        $log = Join-Path $OutDir "$tag.log"
        Write-Host "===== $tag ====="
        $subOut = Join-Path $OutDir "${tag}_sub"
        if ($suite -eq "qa_all_maps_deep" -or $suite -eq "qa_v30_all") {
            powershell -File "tools\$suite.ps1" -OutDir $subOut 2>&1 | Out-File -FilePath $log -Encoding utf8
        } else {
            powershell -File "tools\$suite.ps1" 2>&1 | Out-File -FilePath $log -Encoding utf8
        }
        $code = $LASTEXITCODE
        $text = Get-Content $log -Raw
        $ok = ($code -eq 0) -and ($text -match 'ALL .*PASSED')
        if (-not $ok) {
            $failed += $tag
            Write-Host "FAIL $tag (exit $code)" -ForegroundColor Red
        } else {
            Write-Host "PASS $tag" -ForegroundColor Green
        }
    }
}

if ($failed.Count -gt 0) {
    Write-Host "FAILED RUNS: $($failed -join ', ')" -ForegroundColor Red
    exit 1
}
Write-Host "ALL 3x REGRESSION SUITES PASSED" -ForegroundColor Green
exit 0
