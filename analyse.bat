@echo off
:: Film-Qualitaetsanalyse - Launcher fuer analyse.ps1
:: Verwendung: analyse.bat "C:\Filme\movie.mkv"
:: Oder: Drag & Drop einer Videodatei auf diese .bat

setlocal

if "%~1"=="" (
    echo Verwendung: analyse.bat "Pfad\zur\Datei.mkv"
    echo.
    echo Oder ziehe eine Videodatei auf diese .bat-Datei.
    pause
    exit /b 1
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0analyse.ps1" -InputPath %1

pause
