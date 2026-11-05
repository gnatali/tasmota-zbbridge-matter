# Compile Tasmota Zigbee (EZSP) + Matter pour la passerelle eWeLink ZB-GW03.
# Prerequis : Git et Python 3 dans le PATH.
# Usage : powershell -ExecutionPolicy Bypass -File .\build-zbbridge-matter.ps1 [-WorkDir C:\tasmota-build]

param(
    # Chemin court conseille : les chemins longs font echouer la compilation ESP-IDF sous Windows
    [string]$WorkDir = "C:\tasmota-build",
    [string]$Branch = "development"
)

$ErrorActionPreference = "Stop"
$pioEnv = "tasmota32-zbbrdgpro-matter"
$repo = Join-Path $WorkDir "Tasmota"
$venv = Join-Path $WorkDir "venv"

New-Item -ItemType Directory -Force $WorkDir | Out-Null

# Cache du gestionnaire de composants ESP-IDF dans un chemin court : avec le cache
# par defaut (AppData), "git init --bare" y echoue ("unable to get current working directory")
$env:IDF_COMPONENT_CACHE_PATH = Join-Path $WorkDir "idf-cache"
New-Item -ItemType Directory -Force $env:IDF_COMPONENT_CACHE_PATH | Out-Null

if (-not (Test-Path $repo)) {
    git clone --depth 1 --branch $Branch https://github.com/arendst/Tasmota.git $repo
} else {
    git -C $repo pull --ff-only
}
if ($LASTEXITCODE -ne 0) { throw "git a echoue" }

Copy-Item (Join-Path $PSScriptRoot "platformio_override.ini") (Join-Path $repo "platformio_override.ini") -Force
# Zigbee en EZSP (EFR32MG21 du ZB-GW03) au lieu de ZNP
Copy-Item (Join-Path $PSScriptRoot "user_config_override.h") (Join-Path $repo "tasmota\user_config_override.h") -Force

if (-not (Test-Path $venv)) {
    python -m venv $venv
    & "$venv\Scripts\python.exe" -m pip install --upgrade pip platformio
    if ($LASTEXITCODE -ne 0) { throw "installation de PlatformIO echouee" }
}

# Premier build long (telechargement de la chaine ESP32 et recompilation des
# bibliotheques Arduino a cause de custom_sdkconfig) : compter 20 a 40 minutes
Push-Location $repo
try {
    & "$venv\Scripts\pio.exe" run -e $pioEnv
    if ($LASTEXITCODE -ne 0) { throw "la compilation a echoue" }
} finally {
    Pop-Location
}

$bin = Join-Path $repo "build_output\firmware\$pioEnv.bin"
if (-not (Test-Path $bin)) { $bin = Join-Path $repo ".pio\build\$pioEnv\firmware.bin" }
$kb = [math]::Round((Get-Item $bin).Length / 1KB)
Write-Host ""
Write-Host "Firmware : $bin ($kb Ko, maximum 2880 Ko)"
