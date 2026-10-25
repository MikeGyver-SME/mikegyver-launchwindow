# Pushes Launch Window v1.0.0 to GitHub and tags it so the TestFlight
# workflow runs.
#
# 1. Create an EMPTY repo on GitHub first: MikeGyver-SME/mikegyver-launchwindow
#    (no README, no .gitignore — this script supplies both).
# 2. Save this script AND launchwindow-v1.0.0.zip in E:\Downloads.
# 3. Run: powershell -ExecutionPolicy Bypass -File E:\Downloads\push-launchwindow.ps1
#
# If the repo folder already exists with a .git folder, the script overlays
# the zip onto it instead of re-initialising. Either way it tags v1.0.0.
# If v1.0.0 already exists, stop: bump CURRENT_PROJECT_VERSION in
# project.yml and re-zip before tagging again (TestFlight rejects a
# duplicate version/build pair).

$ErrorActionPreference = 'Stop'

$downloads = if (Test-Path 'E:\Downloads') { 'E:\Downloads' } else { "$env:USERPROFILE\Downloads" }
$zip  = Join-Path $downloads 'launchwindow-v1.0.0.zip'
$repo = if ($args.Count -ge 1) { $args[0] } else { Join-Path $downloads 'mikegyver-launchwindow' }

if (-not (Test-Path $zip)) { throw "Zip not found: $zip" }

$isNew = -not (Test-Path (Join-Path $repo '.git'))
if ($isNew) {
    New-Item -ItemType Directory -Force -Path $repo | Out-Null
    Expand-Archive -Path $zip -DestinationPath $repo -Force
    Set-Location $repo
    git init -b main
    git remote add origin https://github.com/MikeGyver-SME/mikegyver-launchwindow.git
} else {
    Expand-Archive -Path $zip -DestinationPath $repo -Force
    Set-Location $repo
}

$status = git status --porcelain
if (-not $status -and -not $isNew) { Write-Host "Nothing changed - working tree already has v1.0.0."; exit 0 }

if (git tag --list 'v1.0.0') { throw "Tag v1.0.0 already exists. Bump CURRENT_PROJECT_VERSION in project.yml and re-zip first." }

git add -A
git commit -m "Launch Window v1.0.0: launch countdown app + widgets + Live Activity" | Out-Null
if ($isNew) { git push -u origin main } else { git push }
git tag v1.0.0
git push origin v1.0.0

Write-Host ""
Write-Host "Pushed v1.0.0 - the TestFlight workflow should start now."
Write-Host "Watch it at: https://github.com/MikeGyver-SME/mikegyver-launchwindow/actions"
Write-Host "Before that workflow can succeed, set the repo secrets ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_P8, TEAM_ID,"
Write-Host "and create the App IDs + App Group in the Apple Developer portal (see README.md section 3)."
