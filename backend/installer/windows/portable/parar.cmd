@echo off
rem Para o servidor e o banco de dados desta pasta (por exemplo, depois de fechar a janela do iniciar.cmd).
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0pindrel-server.ps1" -Action stop -Data "%~dp0dados"
echo O servidor do Pindrel esta parado.
pause
