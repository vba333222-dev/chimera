<#
.SYNOPSIS
Builds a highly secure, obfuscated release APK for Chimera.

.DESCRIPTION
This script compiles the Flutter application with maximum security flags:
1. --release: Enables Dart AOT compilation and tree shaking.
2. --obfuscate: Renames classes, methods, and variables to prevent reverse engineering.
3. --split-debug-info: Extracts debug symbols to a separate directory, significantly hindering de-anonymization of crash dumps by malicious actors.
4. --split-per-abi: Generates separate APKs for different CPU architectures (arm64-v8a, armeabi-v7a, x86_64), reducing the surface area and payload size.

.EXAMPLE
.\build_secure_release.ps1
#>

$ErrorActionPreference = "Stop"

$ProjectRoot = "c:\Users\USER\Documents\Chimera 1.2\chimera\secure_chat"
$SymbolDir = "build\app\outputs\symbols"

Write-Host "[*] Chimera Security Build Pipeline Initiated..." -ForegroundColor Cyan

# 1. Clean previous builds to prevent leftover artifacts
Write-Host "[*] Cleaning project workspace..." -ForegroundColor Yellow
cd $ProjectRoot
flutter clean

# 2. Re-fetch dependencies
Write-Host "[*] Fetching dependencies..." -ForegroundColor Yellow
flutter pub get

# 3. Ensure Envied code generation is up to date
Write-Host "[*] Regenerating obfuscated environment maps..." -ForegroundColor Yellow
dart run build_runner build -d

# 4. Compile the APK
Write-Host "[*] Starting obfuscated AOT compilation..." -ForegroundColor Yellow
# Creates the debug symbols directory if it doesn't exist
if (-Not (Test-Path -Path $SymbolDir)) {
    New-Item -ItemType Directory -Path $SymbolDir | Out-Null
}

$BuildArgs = @(
    "build", "apk",
    "--release",
    "--obfuscate",
    "--split-debug-info=$SymbolDir",
    "--split-per-abi"
)

# Run the build
Write-Host "> flutter" $BuildArgs -ForegroundColor DarkGray
flutter @BuildArgs

if ($LASTEXITCODE -eq 0) {
    Write-Host "[+] SUCCESS: Secure APKs built successfully." -ForegroundColor Green
    Write-Host "[info] APKs are located at: build\app\outputs\apk\release\" -ForegroundColor Gray
    Write-Host "[info] Obfuscation symbols are located at: $SymbolDir" -ForegroundColor Gray
    Write-Host "[!] WARNING: Keep the symbol map private. Never distribute it." -ForegroundColor Red
} else {
    Write-Host "[-] FATAL: Build pipeline failed." -ForegroundColor Red
    exit 1
}
