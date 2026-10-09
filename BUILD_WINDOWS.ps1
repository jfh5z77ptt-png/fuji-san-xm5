$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot
if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    Write-Host 'Flutter SDK and Visual Studio Desktop development with C++ are required.'
    Write-Host 'See XM5_GUIDE.md for the GitHub Actions option (no local SDK needed).'
    exit 1
}
flutter pub get
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
flutter analyze
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
flutter test
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
flutter build windows --release --dart-define=FUJI_DEFAULT_MODEL=X-M5
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
Write-Host 'Run build\windows\x64\runner\Release\fuji_san.exe. Keep the entire Release folder.'
