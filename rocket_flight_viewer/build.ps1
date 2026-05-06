param(
    [switch]$clean
)

$projectDir = $PSScriptRoot

if ($clean) {
    Write-Host "Cleaning build folder..."
    Remove-Item -Recurse -Force -Path "$projectDir\build" -ErrorAction SilentlyContinue
}

# Flutter never creates this directory but cmake_install.cmake requires it.
# Must exist before flutter run or the cmake INSTALL step fails with exit code 1.
$nativeAssets = "$projectDir\build\native_assets\windows"
if (-not (Test-Path $nativeAssets)) {
    New-Item -ItemType Directory -Force -Path $nativeAssets | Out-Null
    Write-Host "Created build/native_assets/windows"
}

flutter run -d windows
