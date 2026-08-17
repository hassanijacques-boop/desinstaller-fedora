@echo off
title Desinstallation de Fedora
cd /d "%~dp0"
echo ============================================
echo  Outil de desinstallation de Fedora
echo  (ne touche jamais a Windows)
echo ============================================
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0desinstaller_fedora.ps1"
