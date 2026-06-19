$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $PSCommandPath
$godotRoot = Split-Path -Parent (Split-Path -Parent $projectRoot)
$godotExe = Join-Path $godotRoot "Godot_v4.7-stable_win64_console.exe"
$javaHome = "C:\Program Files\Microsoft\jdk-17.0.19.10-hotspot"
$androidSdk = "C:\Users\Laur\AppData\Local\Android\Sdk"
$outputDir = Join-Path $projectRoot "build\android"
$outputApk = Join-Path $outputDir "TinyTroupe-debug.apk"

if (-not (Test-Path -LiteralPath $godotExe)) {
    throw "Godot console executable not found: $godotExe"
}

if (-not (Test-Path -LiteralPath (Join-Path $javaHome "bin\java.exe"))) {
    throw "JDK not found: $javaHome"
}

if (-not (Test-Path -LiteralPath (Join-Path $androidSdk "build-tools\36.0.0\apksigner.bat"))) {
    throw "Android SDK build-tools 36.0.0 not found: $androidSdk"
}

New-Item -ItemType Directory -Force -Path $outputDir | Out-Null

$env:JAVA_HOME = $javaHome
$env:ANDROID_HOME = $androidSdk
$env:ANDROID_SDK_ROOT = $androidSdk
$env:Path = "$javaHome\bin;$androidSdk\platform-tools;$env:Path"

& $godotExe --headless --path $projectRoot --export-debug Android $outputApk
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}

& (Join-Path $androidSdk "build-tools\36.0.0\apksigner.bat") verify --verbose $outputApk
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}

Write-Host "Android debug APK ready: $outputApk"
