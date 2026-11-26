; Inno Setup script of the Windows installer (and uninstaller) of the Pindrel server: the API, the web page it serves and,
; by default, its own PostgreSQL. Built by .github/workflows/release-desktop.yml:
;   ISCC /DAppVersion=1.2.0 /DSourceDir=<folder with pindrel-server.exe, public\ and pgsql\> /O<dir> /F<name> pindrel-server.iss
; The wizard asks the server's name and port, whether to use the bundled PostgreSQL or one that already exists (and tests
; that one before going on), whether to keep uploaded files and whether a Pindrel Gateway on this machine is the front
; door. It writes server.env (read with --config) into the data folder, and starts everything through pindrel-server.ps1,
; the same script the portable zip uses. The database itself is created on the first start, by the person who runs it:
; PostgreSQL refuses to run with administrator rights, and files made by an elevated installer would not be theirs.
#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
#ifndef SourceDir
  #define SourceDir "stage"
#endif

[Setup]
; NEVER change it: it is how an upgrade and "Apps & features" recognise this program.
AppId={{E29E252B-ABAC-42A4-AADB-7860C5EA2FF2}
AppName=Pindrel Server
AppVersion={#AppVersion}
AppVerName=Pindrel Server {#AppVersion}
AppPublisher=Pindrel
AppPublisherURL=https://github.com/JoaoVitor197843/pindrel
AppSupportURL=https://github.com/JoaoVitor197843/pindrel/issues
AppUpdatesURL=https://github.com/JoaoVitor197843/pindrel/releases
VersionInfoVersion={#AppVersion}
DefaultDirName={autopf}\Pindrel Server
DefaultGroupName=Pindrel Server
DisableProgramGroupPage=yes
; per user by default; the first dialog offers "all users" (then the data goes to ProgramData and the firewall can be set)
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
SetupIconFile=..\..\..\mobile\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\pindrel-server.ico
UninstallDisplayName=Pindrel Server
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
; the installer writes its own log (in %TEMP%, "Setup Log ... .txt"): it is what to send when something unexpected happens
SetupLogging=yes
; a running server and its database are stopped by PrepareToInstall; nothing else holds these files
CloseApplications=no

[Languages]
Name: "ptbr"; MessagesFile: "compiler:Languages\BrazilianPortuguese.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "startnow"; Description: "Iniciar o servidor agora (e confirmar que ele subiu)"
Name: "autostart"; Description: "Iniciar o servidor quando eu entrar no Windows"
; the next three only shape a new server.env: an upgrade keeps the one it finds
Name: "files"; Description: "Guardar neste computador as imagens, vídeos e PDFs enviados nas notas"; Check: ConfigMissing
Name: "registration"; Description: "Permitir que pessoas novas criem conta neste servidor"; Check: ConfigMissing
Name: "gateway"; Description: "Vou usar o Pindrel Gateway neste computador, na frente do servidor (o servidor fica acessível só por este computador, na porta 9000)"; Flags: unchecked; Check: ConfigMissing
Name: "firewall"; Description: "Liberar o servidor no Firewall do Windows (redes privadas)"; Check: IsAdminInstallMode

[InstallDelete]
; an upgrade brings a whole new web build (its files are named by their content) and maybe a new PostgreSQL: the old ones go
Type: filesandordirs; Name: "{app}\public"
Type: filesandordirs; Name: "{app}\pgsql"

[Files]
Source: "{#SourceDir}\pindrel-server.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#SourceDir}\public\*"; DestDir: "{app}\public"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "{#SourceDir}\pgsql\*"; DestDir: "{app}\pgsql"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "pindrel-server.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "server.env.example"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\..\..\mobile\windows\runner\resources\app_icon.ico"; DestDir: "{app}"; DestName: "pindrel-server.ico"; Flags: ignoreversion

[Icons]
Name: "{group}\Abrir o Pindrel no navegador"; Filename: "{app}\abrir-pindrel.url"; IconFilename: "{app}\pindrel-server.ico"
Name: "{group}\Iniciar o servidor"; Filename: "powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""{app}\pindrel-server.ps1"" -Action start -Data ""{code:DataDir}"""; IconFilename: "{app}\pindrel-server.ico"; Flags: runminimized
Name: "{group}\Parar o servidor"; Filename: "powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""{app}\pindrel-server.ps1"" -Action stop -Data ""{code:DataDir}"""; IconFilename: "{app}\pindrel-server.ico"; Flags: runminimized
Name: "{group}\Configuração (server.env)"; Filename: "notepad.exe"; Parameters: """{code:DataDir}\server.env"""
Name: "{group}\Registro do servidor (server.log)"; Filename: "notepad.exe"; Parameters: """{code:DataDir}\server.log"""
Name: "{group}\Registro do banco de dados (postgres.log)"; Filename: "notepad.exe"; Parameters: """{code:DataDir}\postgres.log"""
Name: "{group}\Pasta dos dados"; Filename: "{code:DataDir}"
Name: "{autostartup}\Pindrel Server"; Filename: "powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""{app}\pindrel-server.ps1"" -Action start -Data ""{code:DataDir}"""; IconFilename: "{app}\pindrel-server.ico"; Flags: runminimized; Tasks: autostart

; there is no [Run]: "start now" is the `startnow` task, run (and checked) by CurStepChanged, so a server that does not
; come up is reported instead of failing silently in a hidden window.

[Code]
const
  SupportUrl = 'https://github.com/JoaoVitor197843/pindrel/issues';
  GatewayPort = 9000;

var
  ConfigPage: TInputQueryWizardPage;
  DbChoicePage: TInputOptionWizardPage;
  DbPage: TInputQueryWizardPage;
  PortSuggested: Boolean;

// Settings, the database, uploaded files and the logs live here, apart from the program: an upgrade or an uninstall that
// keeps the data never touches them. Per user: %LOCALAPPDATA%; for all users: %ProgramData%.
function DataDir(Param: String): String;
begin
  if IsAdminInstallMode then
    Result := ExpandConstant('{commonappdata}\Pindrel Server')
  else
    Result := ExpandConstant('{localappdata}\Pindrel Server');
end;

function ConfigFile: String;
begin
  Result := DataDir('') + '\server.env';
end;

function ConfigMissing: Boolean;
begin
  Result := not FileExists(ConfigFile);
end;

// What server.env says for a setting ('' when it is not set): the last line for a key wins, as in the server.
function ConfiguredValue(Key: String): String;
var
  Lines: TArrayOfString;
  I: Integer;
  L: String;
begin
  Result := '';
  if not LoadStringsFromFile(ConfigFile, Lines) then Exit;
  for I := 0 to GetArrayLength(Lines) - 1 do
  begin
    L := Trim(Lines[I]);
    // the byte order mark the installer writes, read as text or not
    while (Length(L) > 0) and (Ord(L[1]) > 127) do L := Copy(L, 2, Length(L));
    if Pos('export ', L) = 1 then L := Trim(Copy(L, 8, Length(L)));
    if Pos(Key + '=', L) = 1 then
    begin
      L := Trim(Copy(L, Length(Key) + 2, Length(L)));
      if (Length(L) >= 2) and ((L[1] = '"') or (L[1] = '''')) and (L[Length(L)] = L[1]) then L := Copy(L, 2, Length(L) - 2);
      Result := L;
    end;
  end;
end;

function ConfiguredPort: Integer;
begin
  Result := StrToIntDef(ConfiguredValue('PORT'), 8080);
end;

function Quoted(S: String): String;
begin
  StringChangeEx(S, '''', '''''', True);
  Result := '''' + S + '''';
end;

function ScriptCommand(Action: String): String;
begin
  Result := '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + ExpandConstant('{app}\pindrel-server.ps1') +
    '" -Action ' + Action + ' -Data "' + DataDir('') + '"';
end;

// The text for a failure nobody planned for: what failed, the detail, where the logs are and who to tell.
function UnexpectedText(Step, Detail: String): String;
begin
  Result := 'Ocorreu um erro inesperado ao ' + Step + '.' + #13#10 + #13#10 +
    'Detalhe: ' + Detail + #13#10 + #13#10 +
    'Onde olhar:' + #13#10 +
    '  • registros do servidor: ' + DataDir('') + ' (server.log, postgres.log)' + #13#10 +
    '  • registro do instalador: a pasta ' + GetEnv('TEMP') + ' (arquivos "Setup Log ... .txt")' + #13#10 + #13#10 +
    'Se o erro continuar, fale com quem mantém o projeto e anexe esses registros:' + #13#10 + SupportUrl;
end;

// Small scripts the wizard runs from its temporary folder (none of them opens a socket: that would make the Windows
// Firewall ask whether to let "Windows PowerShell" in).
//  probe-port.ps1 <port> <own exe> <out file>: exit 0 = free (or held by this very server, which the install stops);
//    1 = taken (the name of the program holding it goes to <out file>, empty when it is a range Windows reserved).
//  wait-up.ps1 <port> <own exe> <seconds>: exit 0 as soon as this server listens on the port.
procedure WriteHelpers;
var
  P, W: TArrayOfString;
  Ok: Boolean;
begin
  SetArrayLength(P, 14);
  P[0] := 'param([int]$Port, [string]$Own, [string]$Out)';
  P[1] := '$c = Get-NetTCPConnection -State Listen -LocalPort $Port -ErrorAction SilentlyContinue | Select-Object -First 1';
  P[2] := 'if ($c) {';
  P[3] := '  $p = Get-Process -Id $c.OwningProcess -ErrorAction SilentlyContinue';
  P[4] := '  if ($p -and $p.Path -eq $Own) { exit 0 }';
  P[5] := '  $n = ""; if ($p) { $n = $p.ProcessName }';
  P[6] := '  Set-Content -LiteralPath $Out -Value $n -Encoding ASCII; exit 1';
  P[7] := '}';
  P[8] := 'foreach ($l in (netsh interface ipv4 show excludedportrange protocol=tcp)) {';
  P[9] := '  if ($l -match "^\s*(\d+)\s+(\d+)") {';
  P[10] := '    if ($Port -ge [int]$Matches[1] -and $Port -le [int]$Matches[2]) { Set-Content -LiteralPath $Out -Value "" -Encoding ASCII; exit 1 }';
  P[11] := '  }';
  P[12] := '}';
  P[13] := 'exit 0';
  Ok := SaveStringsToUTF8File(ExpandConstant('{tmp}\probe-port.ps1'), P, False);

  SetArrayLength(W, 8);
  W[0] := 'param([int]$Port, [string]$Own, [int]$Secs)';
  W[1] := '$end = (Get-Date).AddSeconds($Secs)';
  W[2] := 'while ((Get-Date) -lt $end) {';
  W[3] := '  $c = Get-NetTCPConnection -State Listen -LocalPort $Port -ErrorAction SilentlyContinue | Select-Object -First 1';
  W[4] := '  if ($c) { $p = Get-Process -Id $c.OwningProcess -ErrorAction SilentlyContinue; if ($p -and $p.Path -eq $Own) { exit 0 } }';
  W[5] := '  Start-Sleep -Milliseconds 500';
  W[6] := '}';
  W[7] := 'exit 1';
  Ok := SaveStringsToUTF8File(ExpandConstant('{tmp}\wait-up.ps1'), W, False) and Ok;
  if not Ok then
    RaiseException('não foi possível gravar os scripts de verificação em ' + ExpandConstant('{tmp}'));
end;

// True when something else already holds the port; Who is its name ('' when unknown or reserved by Windows).
function PortBusy(Port: Integer; var Who: String): Boolean;
var
  Rc: Integer;
  OutFile: String;
  S: TArrayOfString;
begin
  Who := '';
  OutFile := ExpandConstant('{tmp}\port-owner.txt');
  DeleteFile(OutFile);
  Result := Exec('powershell.exe', '-NoProfile -ExecutionPolicy Bypass -File "' + ExpandConstant('{tmp}\probe-port.ps1') + '" ' +
    IntToStr(Port) + ' "' + ExpandConstant('{app}\pindrel-server.exe') + '" "' + OutFile + '"', '', SW_HIDE, ewWaitUntilTerminated, Rc) and (Rc = 1);
  if Result and LoadStringsFromFile(OutFile, S) and (GetArrayLength(S) > 0) then Who := Trim(S[0]);
end;

function PortText(Port: Integer; Who: String): String;
begin
  if Who <> '' then
    Result := 'A porta ' + IntToStr(Port) + ' já está em uso pelo programa "' + Who + '". Escolha outra porta.'
  else
    Result := 'A porta ' + IntToStr(Port) + ' não está disponível (reservada pelo Windows ou usada por um serviço do sistema). Escolha outra porta.';
end;

// The first free port from From on, skipping Avoid; 0 when none of the next Count is free.
function FreePort(From, Count, Avoid: Integer): Integer;
var
  P: Integer;
  Who: String;
begin
  Result := 0;
  for P := From to From + Count - 1 do
    if (P <> Avoid) and (not PortBusy(P, Who)) then
    begin
      Result := P;
      Exit;
    end;
end;

// Runs a program with its output captured in a file and returns that output (its exit code in Rc; -1 if it did not run).
function RunCaptured(Exe, Params: String; var Rc: Integer): String;
var
  OutFile: String;
  Lines: TArrayOfString;
  I: Integer;
begin
  Result := '';
  OutFile := ExpandConstant('{tmp}\captured.txt');
  DeleteFile(OutFile);
  if not Exec(ExpandConstant('{cmd}'), '/C ""' + Exe + '" ' + Params + ' > "' + OutFile + '" 2>&1"', '', SW_HIDE, ewWaitUntilTerminated, Rc) then
  begin
    Rc := -1;
    Exit;
  end;
  if LoadStringsFromFile(OutFile, Lines) then
    for I := 0 to GetArrayLength(Lines) - 1 do
      if Trim(Lines[I]) <> '' then Result := Result + Trim(Lines[I]) + #13#10;
  DeleteFile(OutFile);
end;

// A new random secret from the server itself (crypto/rand; the Pascal Random of the installer is not one).
function NewSecret: String;
var
  Rc: Integer;
begin
  Result := Trim(RunCaptured(ExpandConstant('{app}\pindrel-server.exe'), '--new-secret', Rc));
  if (Rc <> 0) or (Length(Result) < 32) then
    RaiseException('pindrel-server.exe --new-secret falhou (código ' + IntToStr(Rc) + '): ' + Result);
end;

function EmbeddedChosen: Boolean;
begin
  Result := DbChoicePage.Values[0];
end;

procedure InitializeWizard;
begin
  WriteHelpers;
  ConfigPage := CreateInputQueryPage(wpSelectTasks, 'Configuração do servidor',
    'Como este servidor aparece para os aparelhos',
    'Você pode mudar tudo depois, editando o arquivo server.env (atalho no menu Iniciar).');
  ConfigPage.Add('Nome do servidor:', False);
  ConfigPage.Add('Porta da página e da API (os aparelhos acessam http://este-computador:porta):', False);
  ConfigPage.Values[0] := 'Pindrel';
  ConfigPage.Values[1] := '8080';

  DbChoicePage := CreateInputOptionPage(ConfigPage.ID, 'Banco de dados',
    'Onde o servidor guarda as contas e as notas',
    'O servidor precisa de um PostgreSQL.', True, False);
  DbChoicePage.Add('Usar o PostgreSQL que vem com o servidor (recomendado: não precisa configurar nada; ele só aceita conexões deste computador)');
  DbChoicePage.Add('Usar um PostgreSQL que já existe (neste computador ou em outro)');
  DbChoicePage.Values[0] := True;

  DbPage := CreateInputQueryPage(DbChoicePage.ID, 'PostgreSQL existente',
    'Onde está o banco de dados',
    'O usuário precisa poder criar tabelas na base escolhida. O instalador testa a conexão antes de seguir.');
  DbPage.Add('Endereço (host):', False);
  DbPage.Add('Porta:', False);
  DbPage.Add('Usuário:', False);
  DbPage.Add('Senha:', True);
  DbPage.Add('Nome da base:', False);
  DbPage.Values[0] := 'localhost';
  DbPage.Values[1] := '5432';
  DbPage.Values[2] := 'postgres';
  DbPage.Values[4] := 'pindrel';
end;

// an upgrade keeps the settings that are already there
function ShouldSkipPage(PageID: Integer): Boolean;
begin
  Result := False;
  if (PageID = ConfigPage.ID) or (PageID = DbChoicePage.ID) or (PageID = DbPage.ID) then
    Result := not ConfigMissing;
  if (PageID = DbPage.ID) and EmbeddedChosen then
    Result := True;
end;

// The first time the page opens: the gateway's default upstream is port 9000, and a busy port (8080 is a common one) gets
// the first free one offered right away.
procedure CurPageChanged(CurPageID: Integer);
var
  Port, P: Integer;
  Who, Owner: String;
begin
  if (ConfigPage = nil) or (CurPageID <> ConfigPage.ID) or PortSuggested then Exit;
  PortSuggested := True;
  if WizardIsTaskSelected('gateway') then ConfigPage.Values[1] := IntToStr(GatewayPort);
  Port := StrToIntDef(Trim(ConfigPage.Values[1]), -1);
  if (Port < 1) or (not PortBusy(Port, Who)) then Exit;
  Owner := Who;
  P := FreePort(Port + 1, 20, 0);
  if P = 0 then Exit;
  // a silent install asks nobody: it just takes the free port
  if not WizardSilent then
    MsgBox(PortText(Port, Owner) + #13#10 + #13#10 + 'Sugeri a porta ' + IntToStr(P) + ', que está livre; você pode mudar.', mbInformation, MB_OK);
  ConfigPage.Values[1] := IntToStr(P);
end;

// The settings of an existing PostgreSQL, as the server reads them (the password between single quotes: the reader only
// strips the outer pair, so any quote inside stays).
procedure ExternalDbLines(var Lines: TArrayOfString; var N: Integer);
begin
  Lines[N] := 'EMBEDDED_POSTGRES=false'; N := N + 1;
  Lines[N] := 'DB_HOST=' + Trim(DbPage.Values[0]); N := N + 1;
  Lines[N] := 'DB_PORT=' + IntToStr(StrToInt(Trim(DbPage.Values[1]))); N := N + 1;
  Lines[N] := 'DB_USER=' + Trim(DbPage.Values[2]); N := N + 1;
  Lines[N] := 'DB_PASSWORD=''' + DbPage.Values[3] + ''''; N := N + 1;
  Lines[N] := 'DB_NAME=' + Trim(DbPage.Values[4]); N := N + 1;
  Lines[N] := 'SSL_MODE=prefer'; N := N + 1;
end;

// Tries the database typed in, with the server itself (--check-db): '' when it answered, otherwise what went wrong.
function TestExternalDb: String;
var
  Lines: TArrayOfString;
  N, Rc: Integer;
  Conf: String;
begin
  if not FileExists(ExpandConstant('{tmp}\pindrel-server.exe')) then ExtractTemporaryFile('pindrel-server.exe');
  SetArrayLength(Lines, 16);
  N := 0;
  // the other required settings, with values that only let --check-db read the file
  Lines[N] := 'PORT=8080'; N := N + 1;
  Lines[N] := 'JWT_SECRET=check'; N := N + 1;
  Lines[N] := 'JWT_ACCESS_EXPIRY=15m'; N := N + 1;
  Lines[N] := 'JWT_REFRESH_EXPIRY=720h'; N := N + 1;
  ExternalDbLines(Lines, N);
  SetArrayLength(Lines, N);
  Conf := ExpandConstant('{tmp}\check-db.env');
  if not SaveStringsToUTF8File(Conf, Lines, False) then
  begin
    Result := 'não foi possível gravar ' + Conf;
    Exit;
  end;
  Result := RunCaptured(ExpandConstant('{tmp}\pindrel-server.exe'), '--check-db --config "' + Conf + '"', Rc);
  DeleteFile(Conf);
  if Rc = 0 then Result := ''
  else if Result = '' then Result := 'o teste terminou com o código ' + IntToStr(Rc) + '.';
end;

function NextButtonClick(CurPageID: Integer): Boolean;
var
  Name, Who, Problem: String;
  Port, I: Integer;
begin
  Result := True;
  if CurPageID = ConfigPage.ID then
  begin
    Result := False;
    Name := Trim(ConfigPage.Values[0]);
    Port := StrToIntDef(Trim(ConfigPage.Values[1]), -1);
    if (Length(Name) < 1) or (Length(Name) > 64) then
    begin
      MsgBox('O nome do servidor deve ter de 1 a 64 caracteres (agora tem ' + IntToStr(Length(Name)) + ').', mbError, MB_OK);
      Exit;
    end;
    for I := 1 to Length(Name) do
      if (Ord(Name[I]) < 32) or (Pos(Name[I], '"''#\') > 0) then
      begin
        MsgBox('O nome do servidor não pode ter aspas, # nem barra invertida (o caractere "' + Name[I] + '" está na posição ' + IntToStr(I) + ').', mbError, MB_OK);
        Exit;
      end;
    // the server refuses the ports below 1024 (they need administrator rights on other systems)
    if (Port < 1024) or (Port > 65535) then
    begin
      MsgBox('A porta deve ser um número de 1024 a 65535. Você digitou "' + Trim(ConfigPage.Values[1]) + '".', mbError, MB_OK);
      Exit;
    end;
    if PortBusy(Port, Who) then
    begin
      MsgBox(PortText(Port, Who), mbError, MB_OK);
      Exit;
    end;
    Result := True;
  end
  else if CurPageID = DbPage.ID then
  begin
    Result := False;
    if Trim(DbPage.Values[0]) = '' then
    begin
      MsgBox('Informe o endereço do PostgreSQL (por exemplo localhost ou 192.168.1.20).', mbError, MB_OK);
      Exit;
    end;
    Port := StrToIntDef(Trim(DbPage.Values[1]), -1);
    if (Port < 1) or (Port > 65535) then
    begin
      MsgBox('A porta do PostgreSQL deve ser um número de 1 a 65535 (a de costume é 5432).', mbError, MB_OK);
      Exit;
    end;
    if (Trim(DbPage.Values[2]) = '') or (Trim(DbPage.Values[4]) = '') then
    begin
      MsgBox('Informe o usuário e o nome da base.', mbError, MB_OK);
      Exit;
    end;
    for I := 0 to 4 do
      if (Pos(#13, DbPage.Values[I]) > 0) or (Pos(#10, DbPage.Values[I]) > 0) then
      begin
        MsgBox('Os campos não podem ter quebras de linha.', mbError, MB_OK);
        Exit;
      end;
    WizardForm.NextButton.Enabled := False;
    try
      Problem := TestExternalDb;
    finally
      WizardForm.NextButton.Enabled := True;
    end;
    if Problem <> '' then
    begin
      if WizardSilent then
        Log('PostgreSQL check failed: ' + Problem)
      else if MsgBox('Não consegui conectar a esse PostgreSQL:' + #13#10 + #13#10 + Problem + #13#10 +
        'Confira o endereço, a porta, o usuário e a senha, e se a base existe. Continuar mesmo assim?', mbConfirmation, MB_YESNO or MB_DEFBUTTON2) = IDNO then
        Exit;
    end;
    Result := True;
  end;
end;

procedure StopProgram(Exe: String);
var
  Rc: Integer;
begin
  // only the programs of this folder, never others that happen to have the same file name
  Exec('powershell.exe', '-NoProfile -ExecutionPolicy Bypass -Command "Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq ' +
    Quoted(Exe) + ' } | Stop-Process -Force"', '', SW_HIDE, ewWaitUntilTerminated, Rc);
end;

// Stops the server and its database (cleanly, through the script, when there is one) before files are replaced or removed.
procedure StopServer;
var
  Rc: Integer;
begin
  if FileExists(ExpandConstant('{app}\pindrel-server.ps1')) and FileExists(ConfigFile) then
    Exec('powershell.exe', ScriptCommand('stop') + ' -Quiet', '', SW_HIDE, ewWaitUntilTerminated, Rc);
  StopProgram(ExpandConstant('{app}\pindrel-server.exe'));
  StopProgram(ExpandConstant('{app}\pgsql\bin\postgres.exe'));
  StopProgram(ExpandConstant('{app}\pgsql\bin\pg_ctl.exe'));
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
begin
  StopServer;
  Result := '';
end;

procedure WriteConfig;
var
  Data: String;
  Lines: TArrayOfString;
  N, Port, PgPort: Integer;
begin
  if not ConfigMissing then Exit;
  Data := DataDir('');
  Port := StrToInt(Trim(ConfigPage.Values[1]));
  SetArrayLength(Lines, 32);
  N := 0;
  Lines[N] := '# Configuração do servidor do Pindrel (gerada pelo instalador). Linhas "CHAVE=valor"; # comenta.'; N := N + 1;
  Lines[N] := '# Depois de editar, pare e inicie o servidor pelos atalhos do menu Iniciar. Veja server.env.example na pasta do programa.'; N := N + 1;
  Lines[N] := 'SERVER_NAME=' + Trim(ConfigPage.Values[0]); N := N + 1;
  Lines[N] := 'PORT=' + IntToStr(Port); N := N + 1;
  Lines[N] := 'WEB_DIR=' + ExpandConstant('{app}\public'); N := N + 1;
  if WizardIsTaskSelected('gateway') then
  begin
    Lines[N] := '# o Pindrel Gateway deste computador é a porta de entrada: ele limita os pedidos e o servidor só o atende'; N := N + 1;
    Lines[N] := 'LISTEN_HOST=127.0.0.1'; N := N + 1;
    Lines[N] := 'IN_APP_RATE_LIMIT=false'; N := N + 1;
  end;
  if WizardIsTaskSelected('files') then
  begin
    Lines[N] := 'FILES_DIR=' + Data + '\files'; N := N + 1;
    Lines[N] := 'FILES_MIN_FREE_BYTES=2147483648'; N := N + 1;
  end
  else
  begin
    Lines[N] := 'FILES_DIR='; N := N + 1;
  end;
  if WizardIsTaskSelected('registration') then Lines[N] := 'REGISTRATION_ENABLED=true' else Lines[N] := 'REGISTRATION_ENABLED=false';
  N := N + 1;
  Lines[N] := 'JWT_SECRET=' + NewSecret; N := N + 1;
  Lines[N] := 'JWT_ACCESS_EXPIRY=15m'; N := N + 1;
  Lines[N] := 'JWT_REFRESH_EXPIRY=720h'; N := N + 1;
  if EmbeddedChosen then
  begin
    PgPort := FreePort(5433, 60, Port);
    if PgPort = 0 then RaiseException('nenhuma porta livre entre 5433 e 5492 para o banco de dados');
    Lines[N] := 'EMBEDDED_POSTGRES=true'; N := N + 1;
    Lines[N] := 'DB_HOST=127.0.0.1'; N := N + 1;
    Lines[N] := 'DB_PORT=' + IntToStr(PgPort); N := N + 1;
    Lines[N] := 'DB_USER=pindrel'; N := N + 1;
    Lines[N] := 'DB_PASSWORD=' + NewSecret; N := N + 1;
    Lines[N] := 'DB_NAME=pindrel'; N := N + 1;
    Lines[N] := 'SSL_MODE=disable'; N := N + 1;
  end
  else
    ExternalDbLines(Lines, N);
  SetArrayLength(Lines, N);
  if not SaveStringsToUTF8File(ConfigFile, Lines, False) then
    RaiseException('não foi possível gravar ' + ConfigFile);
end;

// The "open in the browser" shortcut points at the port in server.env (a kept one on an upgrade).
procedure WriteBrowserShortcut;
var
  Lines: TArrayOfString;
begin
  SetArrayLength(Lines, 2);
  Lines[0] := '[InternetShortcut]';
  Lines[1] := 'URL=http://localhost:' + IntToStr(ConfiguredPort) + '/';
  SaveStringsToFile(ExpandConstant('{app}\abrir-pindrel.url'), Lines, False);
end;

// What `pindrel-server --check` says about the settings ('' when they are fine).
function CheckConfig: String;
var
  Rc: Integer;
begin
  Result := RunCaptured(ExpandConstant('{app}\pindrel-server.exe'), '--check --config "' + ConfigFile + '"', Rc);
  if Rc = 0 then Result := ''
  else if Rc = -1 then Result := 'não foi possível executar o pindrel-server.exe para validar a configuração.'
  else if Result = '' then Result := 'o servidor recusou a configuração (código ' + IntToStr(Rc) + ').';
end;

// First lines of the logs, to say why it did not start.
function LastLogLines: String;
var
  Lines: TArrayOfString;
  I, N: Integer;
  F: String;
begin
  Result := '';
  F := DataDir('') + '\server.log';
  if not LoadStringsFromFile(F, Lines) then Exit;
  N := GetArrayLength(Lines);
  for I := N - 4 to N - 1 do
    if (I >= 0) and (Trim(Lines[I]) <> '') then Result := Result + Trim(Lines[I]) + #13#10;
end;

// Starts the server like the menu shortcut does (as the person who ran the installer, never with its administrator
// rights), waits for it to listen and says what happened. The first start also creates the database.
procedure StartAndReport;
var
  Rc, Port: Integer;
  Up: Boolean;
begin
  Port := ConfiguredPort;
  WizardForm.StatusLabel.Caption := 'Iniciando o servidor (na primeira vez ele também cria o banco de dados)...';
  ExecAsOriginalUser('powershell.exe', ScriptCommand('start'), '', SW_HIDE, ewNoWait, Rc);
  Up := Exec('powershell.exe', '-NoProfile -ExecutionPolicy Bypass -File "' + ExpandConstant('{tmp}\wait-up.ps1') + '" ' + IntToStr(Port) +
    ' "' + ExpandConstant('{app}\pindrel-server.exe') + '" 150', '', SW_HIDE, ewWaitUntilTerminated, Rc) and (Rc = 0);
  if Up then
    MsgBox('O servidor está rodando na porta ' + IntToStr(Port) + '.' + #13#10 + #13#10 +
      'Abra no navegador: http://localhost:' + IntToStr(Port) + '/ (atalho "Abrir o Pindrel no navegador" no menu Iniciar).' + #13#10 +
      'Ele não tem janela: roda escondido. Para pará-lo, use "Parar o servidor" no menu Iniciar.' + #13#10 + #13#10 +
      'Os dados (configuração, banco de dados e arquivos) ficam em: ' + DataDir(''), mbInformation, MB_OK)
  else
    MsgBox('O servidor foi instalado, mas ainda não respondeu na porta ' + IntToStr(Port) + '.' + #13#10 + #13#10 + LastLogLines + #13#10 +
      'Ele continua tentando em segundo plano e vai avisar na tela se não conseguir.' + #13#10 +
      'Registros: ' + DataDir('') + ' (server.log, postgres.log)' + #13#10 +
      'Se o problema continuar, fale com quem mantém o projeto: ' + SupportUrl,
      mbError, MB_OK);
end;

procedure CurStepChanged(CurStep: TSetupStep);
var
  Rc: Integer;
  Problem: String;
begin
  if CurStep <> ssPostInstall then Exit;
  try
    if not ForceDirectories(DataDir('')) then
      RaiseException('não foi possível criar a pasta dos dados ' + DataDir(''));
    // For all users the folder is in ProgramData, where people can read but not change what the installer made. The
    // database is created and run by whoever starts the server (PostgreSQL refuses administrator rights), so the local
    // users may change this folder; its settings were readable by them anyway, as everything in ProgramData.
    if IsAdminInstallMode then
      Exec('icacls.exe', '"' + DataDir('') + '" /grant *S-1-5-32-545:(OI)(CI)M', '', SW_HIDE, ewWaitUntilTerminated, Rc);
    WriteConfig;
    WriteBrowserShortcut;
    if WizardIsTaskSelected('firewall') then
    begin
      Exec('netsh.exe', 'advfirewall firewall delete rule name="Pindrel Server"', '', SW_HIDE, ewWaitUntilTerminated, Rc);
      // a server that only this computer reaches (behind the gateway) needs no door in the firewall
      if ConfiguredValue('LISTEN_HOST') <> '127.0.0.1' then
        if (not Exec('netsh.exe', 'advfirewall firewall add rule name="Pindrel Server" dir=in action=allow enable=yes profile=private program="' +
          ExpandConstant('{app}\pindrel-server.exe') + '"', '', SW_HIDE, ewWaitUntilTerminated, Rc)) or (Rc <> 0) then
          MsgBox('O servidor foi instalado, mas não consegui criar a regra no Firewall do Windows (código ' + IntToStr(Rc) + ').' + #13#10 +
            'Os aparelhos da rede só vão alcançá-lo depois de você liberar o pindrel-server.exe no Firewall.', mbError, MB_OK);
    end;
    // refuse to leave a broken setting: say exactly what is wrong, and where to fix it
    Problem := CheckConfig;
    if Problem <> '' then
      MsgBox('O servidor foi instalado, mas a configuração tem um erro:' + #13#10 + #13#10 + Problem + #13#10 +
        'Abra "Configuração (server.env)" no menu Iniciar, corrija e inicie o servidor de novo.' + #13#10 +
        'Arquivo: ' + ConfigFile, mbError, MB_OK)
    else if WizardIsTaskSelected('startnow') and (not WizardSilent) then
      StartAndReport;
  except
    MsgBox(UnexpectedText('concluir a instalação', GetExceptionMessage), mbError, MB_OK);
  end;
end;

function PurgeAsked: Boolean;
var
  I: Integer;
begin
  Result := False;
  for I := 1 to ParamCount do
    if CompareText(ParamStr(I), '/PURGE') = 0 then Result := True;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  Erase: Boolean;
  Rc: Integer;
begin
  if CurUninstallStep = usUninstall then
  begin
    StopServer;
    if IsAdminInstallMode then
      Exec('netsh.exe', 'advfirewall firewall delete rule name="Pindrel Server"', '', SW_HIDE, ewWaitUntilTerminated, Rc);
    // written after the install, so the uninstaller does not know it
    DeleteFile(ExpandConstant('{app}\abrir-pindrel.url'));
    Exit;
  end;
  if CurUninstallStep <> usPostUninstall then Exit;
  if not DirExists(DataDir('')) then Exit;
  Erase := PurgeAsked;
  // a silent uninstall (an update, a script) never asks and keeps everything
  if (not Erase) and (not UninstallSilent) then
    Erase := MsgBox(
      'Apagar também os dados do servidor?' + #13#10 + #13#10 +
      'Isso apaga o banco de dados (todas as contas e notas guardadas neste servidor), os arquivos enviados e a configuração, ' +
      'e não tem volta. Se você escolher "Não", tudo continua em ' + DataDir('') + ' e volta se você instalar o servidor de novo.',
      mbConfirmation, MB_YESNO or MB_DEFBUTTON2) = IDYES;
  if Erase then DelTree(DataDir(''), True, True, True);
end;
