@echo off
REM Loads backend\.env into the environment, then starts the Spring Boot server.
REM Spring Boot does not read .env files itself, so this launcher bridges the gap.
REM Usage (from Command Prompt):   run-with-mail.bat
setlocal enabledelayedexpansion

cd /d "%~dp0"

if not exist ".env" (
    echo No .env file found in "%cd%". Fill in your SMTP values first.
    exit /b 1
)

REM Read KEY=VALUE lines, skipping blank lines and comments (lines starting with #).
for /f "usebackq eol=# tokens=1,* delims==" %%A in (".env") do (
    if not "%%A"=="" (
        set "%%A=%%B"
        echo   set %%A
    )
)

echo Starting backend with mail settings from .env ...
call gradlew.bat bootRun
