@echo off
rem Pindrel gateway, portatil: roda nesta pasta, sem instalar nada.
cd /d "%~dp0"
if not exist gateway.env (
  copy /y gateway.env.example gateway.env >nul
  echo Criei o arquivo gateway.env com valores de exemplo.
  echo Ajuste ao menos UPSTREAMS ^(onde esta a API^), salve e feche o Bloco de Notas.
  notepad gateway.env
)
echo Iniciando o gateway. Para parar, feche esta janela ou aperte Ctrl+C.
echo O codigo de pareamento ^(se o HTTPS estiver ligado^) aparece aqui.
gateway.exe --config gateway.env
echo.
echo O gateway parou.
pause
