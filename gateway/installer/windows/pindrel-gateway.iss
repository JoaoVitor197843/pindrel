; Inno Setup script of the Windows installer (and uninstaller) of the Pindrel gateway. Built by
; .github/workflows/release-desktop.yml:
;   ISCC /DAppVersion=1.2.0 /DSourceDir=<folder with gateway.exe> /O<dir> /F<file name without .exe> pindrel-gateway.iss
; It asks where the API is, writes gateway.env (read with --config), and starts the gateway hidden (at logon if asked).
#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
#ifndef SourceDir
  #define SourceDir "..\..\target\release"
#endif

[Setup]
; NEVER change it: it is how an upgrade and "Apps & features" recognise this program.
AppId={{B7A25D0C-3E41-4D2B-9C1A-6F2E8D4A5B17}
AppName=Pindrel Gateway
AppVersion={#AppVersion}
AppVerName=Pindrel Gateway {#AppVersion}
AppPublisher=Pindrel
AppPublisherURL=https://github.com/JoaoVitor197843/pindrel
AppSupportURL=https://github.com/JoaoVitor197843/pindrel/issues
AppUpdatesURL=https://github.com/JoaoVitor197843/pindrel/releases
VersionInfoVersion={#AppVersion}
DefaultDirName={autopf}\Pindrel Gateway
DefaultGroupName=Pindrel Gateway
DisableProgramGroupPage=yes
; per user by default; the first dialog offers "all users" (then the data goes to ProgramData and the firewall can be set)
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
UninstallDisplayIcon={app}\gateway.exe
UninstallDisplayName=Pindrel Gateway
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
; a running gateway is stopped by PrepareToInstall; nothing else holds these files
CloseApplications=no

[Languages]
Name: "ptbr"; MessagesFile: "compiler:Languages\BrazilianPortuguese.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "autostart"; Description: "Iniciar o gateway quando eu entrar no Windows"
Name: "https"; Description: "Ativar HTTPS com certificado próprio (necessário para parear os apps do celular)"
Name: "firewall"; Description: "Liberar o gateway no Firewall do Windows (redes privadas)"; Check: IsAdminInstallMode

[Files]
Source: "{#SourceDir}\gateway.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "gateway.env.example"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{group}\Iniciar o gateway"; Filename: "powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""{app}\start-gateway.ps1"""; IconFilename: "{app}\gateway.exe"; Flags: runminimized
Name: "{group}\Parar o gateway"; Filename: "powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""{app}\stop-gateway.ps1"""; IconFilename: "{app}\gateway.exe"; Flags: runminimized
Name: "{group}\Configuração (gateway.env)"; Filename: "notepad.exe"; Parameters: """{code:DataDir}\gateway.env"""
Name: "{group}\Registro (gateway.log)"; Filename: "notepad.exe"; Parameters: """{code:DataDir}\gateway.log"""
Name: "{autostartup}\Pindrel Gateway"; Filename: "powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""{app}\start-gateway.ps1"""; IconFilename: "{app}\gateway.exe"; Flags: runminimized; Tasks: autostart

[Run]
Filename: "powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""{app}\start-gateway.ps1"""; Description: "Iniciar o gateway agora"; Flags: nowait postinstall skipifsilent runhidden

[Code]
var
  ConfigPage: TInputQueryWizardPage;

// Settings, identity, certificates and the log live here, apart from the program: an upgrade or an uninstall that keeps
// the data never touches them. Per user: %LOCALAPPDATA%; for all users: %ProgramData%.
function DataDir(Param: String): String;
begin
  if IsAdminInstallMode then
    Result := ExpandConstant('{commonappdata}\Pindrel Gateway')
  else
    Result := ExpandConstant('{localappdata}\Pindrel Gateway');
end;

function Quoted(S: String): String;
begin
  StringChangeEx(S, '''', '''''', True);
  Result := '''' + S + '''';
end;

procedure InitializeWizard;
begin
  ConfigPage := CreateInputQueryPage(wpSelectTasks, 'Configuração do gateway',
    'Como este servidor aparece na rede e onde está a API',
    'Você pode mudar isso depois, editando o arquivo gateway.env (atalho no menu Iniciar).');
  ConfigPage.Add('Nome do servidor na rede:', False);
  ConfigPage.Add('Porta do gateway:', False);
  ConfigPage.Add('Endereços da API (ip:porta ou ip:porta-porta, separados por vírgula):', False);
  ConfigPage.Values[0] := 'Pindrel';
  ConfigPage.Values[1] := '8080';
  ConfigPage.Values[2] := '127.0.0.1:9000-9099';
end;

// an upgrade keeps the settings that are already there
function ShouldSkipPage(PageID: Integer): Boolean;
begin
  Result := (PageID = ConfigPage.ID) and FileExists(DataDir('') + '\gateway.env');
end;

function AllIn(S, Allowed: String): Boolean;
var
  I: Integer;
begin
  Result := True;
  for I := 1 to Length(S) do
    if Pos(S[I], Allowed) = 0 then
    begin
      Result := False;
      Exit;
    end;
end;

function NextButtonClick(CurPageID: Integer): Boolean;
var
  Name, Upstreams: String;
  Port, I: Integer;
begin
  Result := True;
  if CurPageID <> ConfigPage.ID then Exit;
  Name := Trim(ConfigPage.Values[0]);
  Port := StrToIntDef(Trim(ConfigPage.Values[1]), -1);
  Upstreams := Trim(ConfigPage.Values[2]);
  if (Length(Name) < 1) or (Length(Name) > 64) then
  begin
    MsgBox('O nome deve ter de 1 a 64 caracteres.', mbError, MB_OK);
    Result := False;
    Exit;
  end;
  for I := 1 to Length(Name) do
    if (Ord(Name[I]) < 32) or (Pos(Name[I], '"''#\') > 0) then
    begin
      MsgBox('O nome não pode ter aspas, # nem barra invertida.', mbError, MB_OK);
      Result := False;
      Exit;
    end;
  if (Port < 1) or (Port > 65535) then
  begin
    MsgBox('A porta deve ser um número de 1 a 65535.', mbError, MB_OK);
    Result := False;
    Exit;
  end;
  if (Upstreams = '') or (not AllIn(Upstreams, '0123456789abcdefABCDEF.:,[]-')) then
  begin
    MsgBox('Informe os endereços da API, como 127.0.0.1:9000-9099 (separe vários por vírgula).', mbError, MB_OK);
    Result := False;
  end;
end;

procedure StopGateway;
var
  Rc: Integer;
begin
  // only the gateway of this folder, never another program that happens to be called gateway.exe
  Exec('powershell.exe', '-NoProfile -ExecutionPolicy Bypass -Command "Get-Process gateway -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq ' +
    Quoted(ExpandConstant('{app}\gateway.exe')) + ' } | Stop-Process -Force"', '', SW_HIDE, ewWaitUntilTerminated, Rc);
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
begin
  StopGateway;
  Result := '';
end;

procedure WriteScripts;
var
  App, Data: String;
  Start, Stop: TArrayOfString;
begin
  App := ExpandConstant('{app}');
  Data := DataDir('');
  SetArrayLength(Start, 5);
  Start[0] := '# Written by the installer. Starts the gateway hidden; its messages go to gateway.log (and gateway.out.log).';
  Start[1] := 'if (Get-Process gateway -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq ' + Quoted(App + '\gateway.exe') + ' }) { exit 0 }';
  Start[2] := 'Set-Location -LiteralPath ' + Quoted(Data);
  Start[3] := 'Start-Process -FilePath ' + Quoted(App + '\gateway.exe') + ' -ArgumentList ''--config'', ' + Quoted('"' + Data + '\gateway.env"') +
    ' -WindowStyle Hidden -Wait -RedirectStandardOutput ' + Quoted(Data + '\gateway.out.log') + ' -RedirectStandardError ' + Quoted(Data + '\gateway.log');
  Start[4] := '';
  SaveStringsToUTF8File(App + '\start-gateway.ps1', Start, False);
  SetArrayLength(Stop, 2);
  Stop[0] := '# Written by the installer. Stops the gateway of this folder.';
  Stop[1] := 'Get-Process gateway -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq ' + Quoted(App + '\gateway.exe') + ' } | Stop-Process -Force';
  SaveStringsToUTF8File(App + '\stop-gateway.ps1', Stop, False);
end;

procedure WriteConfig;
var
  Data, Conf: String;
  Lines: TArrayOfString;
  N: Integer;
begin
  Data := DataDir('');
  Conf := Data + '\gateway.env';
  if FileExists(Conf) then Exit;
  SetArrayLength(Lines, 10);
  Lines[0] := '# Configuração do gateway do Pindrel (gerado pelo instalador). Linhas "CHAVE=valor"; # comenta.';
  Lines[1] := '# Depois de editar, pare e inicie o gateway pelos atalhos do menu Iniciar. Veja gateway.env.example na pasta do programa.';
  Lines[2] := 'SERVER_NAME=' + Trim(ConfigPage.Values[0]);
  Lines[3] := 'GATEWAY_PORT=' + Trim(ConfigPage.Values[1]);
  Lines[4] := 'UPSTREAMS=' + Trim(ConfigPage.Values[2]);
  Lines[5] := 'SERVER_ID_FILE=' + Data + '\server.id';
  Lines[6] := 'KNOWN_SERVERS_FILE=' + Data + '\known-servers.pb';
  N := 7;
  if WizardIsTaskSelected('https') then
  begin
    Lines[N] := 'TLS_AUTO=true'; N := N + 1;
    Lines[N] := 'TLS_DIR=' + Data + '\tls'; N := N + 1;
    Lines[N] := 'TLS_PORT=8443'; N := N + 1;
  end;
  SetArrayLength(Lines, N);
  SaveStringsToUTF8File(Conf, Lines, False);
end;

procedure CurStepChanged(CurStep: TSetupStep);
var
  Rc: Integer;
begin
  if CurStep <> ssPostInstall then Exit;
  ForceDirectories(DataDir(''));
  WriteConfig;
  WriteScripts;
  if WizardIsTaskSelected('firewall') then
  begin
    Exec('netsh.exe', 'advfirewall firewall delete rule name="Pindrel Gateway"', '', SW_HIDE, ewWaitUntilTerminated, Rc);
    Exec('netsh.exe', 'advfirewall firewall add rule name="Pindrel Gateway" dir=in action=allow enable=yes profile=private program="' +
      ExpandConstant('{app}\gateway.exe') + '"', '', SW_HIDE, ewWaitUntilTerminated, Rc);
  end;
  // refuse silently to leave a broken setting: say so, and where to fix it
  if (not Exec(ExpandConstant('{app}\gateway.exe'), '--check --config "' + DataDir('') + '\gateway.env"', '', SW_HIDE, ewWaitUntilTerminated, Rc)) or (Rc <> 0) then
    MsgBox('O gateway foi instalado, mas a configuração tem um erro. Abra "Configuração (gateway.env)" no menu Iniciar e corrija antes de iniciar.', mbError, MB_OK);
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
    StopGateway;
    if IsAdminInstallMode then
      Exec('netsh.exe', 'advfirewall firewall delete rule name="Pindrel Gateway"', '', SW_HIDE, ewWaitUntilTerminated, Rc);
    // the scripts were written after the install, so the uninstaller does not know them
    DeleteFile(ExpandConstant('{app}\start-gateway.ps1'));
    DeleteFile(ExpandConstant('{app}\stop-gateway.ps1'));
    Exit;
  end;
  if CurUninstallStep <> usPostUninstall then Exit;
  if not DirExists(DataDir('')) then Exit;
  Erase := PurgeAsked;
  // a silent uninstall (an update, a script) never asks and keeps everything
  if (not Erase) and (not UninstallSilent) then
    Erase := MsgBox(
      'Apagar também a configuração e os dados do gateway?' + #13#10 + #13#10 +
      'Isso inclui a chave do certificado próprio: os aparelhos já pareados terão de ser pareados de novo. ' +
      'Se você escolher "Não", tudo continua guardado e volta se você instalar o gateway de novo.',
      mbConfirmation, MB_YESNO or MB_DEFBUTTON2) = IDYES;
  if Erase then DelTree(DataDir(''), True, True, True);
end;
