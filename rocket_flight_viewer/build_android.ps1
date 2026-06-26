param(
    [switch]$install,
    [switch]$clean
)

$projectDir  = $PSScriptRoot
$adb         = "C:\Program Files (x86)\Android\android-sdk\platform-tools\adb.exe"
$apk         = "$projectDir\build\app\outputs\flutter-apk\app-debug.apk"

if ($clean) {
    Write-Host "Cleaning full build folder..."
    Remove-Item -Recurse -Force -Path "$projectDir\build" -ErrorAction SilentlyContinue
}

# Always wipe build\app — stale Gradle intermediates cause java.io.IOException on Windows
# (Gradle can't delete its own locked files; starting clean avoids the issue entirely)
Write-Host "Clearing build\app intermediates..."
Remove-Item -Recurse -Force -Path "$projectDir\build\app" -ErrorAction SilentlyContinue

Write-Host "Building Android debug APK..."
Set-Location $projectDir
flutter build apk --debug
if ($LASTEXITCODE -ne 0) {
    Write-Host "Build FAILED." -ForegroundColor Red
    exit 1
}

Write-Host "APK: $apk" -ForegroundColor Green

if ($install) {
    Write-Host "Installing on connected device..."
    & $adb install -r $apk
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Install FAILED. Check that the phone is connected and USB debugging is enabled." -ForegroundColor Red
        exit 1
    }
    Write-Host "Installed successfully." -ForegroundColor Green
}
