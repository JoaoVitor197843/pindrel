@echo off
rem Pindrel Server, portatil: roda nesta pasta, sem instalar nada. Os dados ficam na pasta "dados".
cd /d "%~dp0"
echo Iniciando o servidor do Pindrel (banco de dados e pagina web)...
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0pindrel-server.ps1" -Action run -Data "%~dp0dados"
echo.
echo O servidor parou.
pause
