# Loads backend/.env into the process environment, then starts the Spring Boot
# server. Spring Boot does not read .env files itself, so this launcher bridges
# the gap. Usage (from the backend/ folder):   .\run-with-mail.ps1

$ErrorActionPreference = 'Stop'
$envFile = Join-Path $PSScriptRoot '.env'

if (-not (Test-Path $envFile)) {
    Write-Error "No .env file found at $envFile. Copy the template and fill in your SMTP values."
    exit 1
}

Get-Content $envFile | ForEach-Object {
    $line = $_.Trim()
    if ($line -eq '' -or $line.StartsWith('#')) { return }
    $idx = $line.IndexOf('=')
    if ($idx -lt 1) { return }
    $key = $line.Substring(0, $idx).Trim()
    $val = $line.Substring($idx + 1).Trim()
    # strip optional surrounding quotes
    if ($val.Length -ge 2 -and (($val.StartsWith('"') -and $val.EndsWith('"')) -or ($val.StartsWith("'") -and $val.EndsWith("'")))) {
        $val = $val.Substring(1, $val.Length - 2)
    }
    Set-Item -Path "Env:$key" -Value $val
    Write-Host ("  set {0}" -f $key)
}

Write-Host "Starting backend with mail settings from .env ..." -ForegroundColor Green
& (Join-Path $PSScriptRoot 'gradlew.bat') bootRun
