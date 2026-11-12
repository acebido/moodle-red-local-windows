@echo off
REM =============================================================================
REM  Abre PowerShell como administrador YA COLOCADO en esta carpeta.
REM  Moodle en la red local sobre Windows 11 - Acebido - Jose Luis Diaz
REM =============================================================================
REM  Doble clic aqui: no hay que escribir ni copiar ninguna ruta. Deja el
REM  script desbloqueado y permitido solo en esa ventana.
REM =============================================================================
powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process powershell -Verb RunAs -ArgumentList '-NoExit -ExecutionPolicy Bypass -Command \"Set-Location ''%~dp0''; Unblock-File *.ps1; Write-Host ''Listo. Escribe .\activar_red_local.ps1 y pulsa Intro (volver a https://localhost: .\activar_red_local.ps1 -Deshacer)'' -ForegroundColor Green\"'"
