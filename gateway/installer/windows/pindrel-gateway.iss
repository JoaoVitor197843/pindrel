; Inno Setup script of the Windows installer (and uninstaller) of the Pindrel gateway. Built by
; .github/workflows/release-desktop.yml:
;   ISCC /DAppVersion=1.2.0 /DSourceDir=<folder with gateway.exe and pindrel-gateway-tray.exe> /O<dir> /F<file name without .exe> pindrel-gateway.iss
; It asks where the API is (address and range of ports), checks that the ports are free, writes gateway.env (read with
; --config), starts the gateway hidden (at logon if asked) and says whether it came up. The tray icon (src/tray.rs) is
; optional and shows the state, stops/starts the gateway and opens the settings and the log.
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
SetupIconFile=gateway.ico
UninstallDisplayIcon={app}\gateway.ico
UninstallDisplayName=Pindrel Gateway
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
; the installer writes its own log (in %TEMP%, "Setup Log ... .txt"): it is what to send when something unexpected happens
SetupLogging=yes
; a running gateway and tray icon are stopped by PrepareToInstall; nothing else holds these files
CloseApplications=no

[Languages]
Name: "ptbr"; MessagesFile: "compiler:Languages\BrazilianPortuguese.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "startnow"; Description: "Iniciar o gateway agora (e confirmar que ele subiu)"
Name: "autostart"; Description: "Iniciar o gateway quando eu entrar no Windows"
Name: "tray"; Description: "Mostrar o ícone do gateway na bandeja do Windows (parar, iniciar, abrir a configuração e o registro)"
; hidden on an upgrade whose settings already have HTTPS: there is nothing left for it to do
Name: "https"; Description: "Ativar HTTPS com certificado próprio (necessário para parear os apps do celular)"; Check: HttpsMissing
Name: "firewall"; Description: "Liberar o gateway no Firewall do Windows (redes privadas)"; Check: IsAdminInstallMode

[Files]
Source: "{#SourceDir}\gateway.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#SourceDir}\pindrel-gateway-tray.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "gateway.ico"; DestDir: "{app}"; Flags: ignoreversion
Source: "gateway-off.ico"; DestDir: "{app}"; Flags: ignoreversion
Source: "gateway.env.example"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{group}\Iniciar o gateway"; Filename: "powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""{app}\start-gateway.ps1"""; IconFilename: "{app}\gateway.ico"; Flags: runminimized
Name: "{group}\Parar o gateway"; Filename: "powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""{app}\stop-gateway.ps1"""; IconFilename: "{app}\gateway-off.ico"; Flags: runminimized
Name: "{group}\Ícone na bandeja"; Filename: "{app}\pindrel-gateway-tray.exe"; Parameters: "--data ""{code:DataDir}"""; IconFilename: "{app}\gateway.ico"
Name: "{group}\Configuração (gateway.env)"; Filename: "notepad.exe"; Parameters: """{code:DataDir}\gateway.env"""
Name: "{group}\Registro (gateway.log)"; Filename: "notepad.exe"; Parameters: """{code:DataDir}\gateway.log"""
Name: "{group}\Pasta dos dados"; Filename: "{code:DataDir}"
Name: "{autostartup}\Pindrel Gateway"; Filename: "powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""{app}\start-gateway.ps1"""; IconFilename: "{app}\gateway.ico"; Flags: runminimized; Tasks: autostart
Name: "{autostartup}\Pindrel Gateway (ícone)"; Filename: "{app}\pindrel-gateway-tray.exe"; Parameters: "--data ""{code:DataDir}"""; IconFilename: "{app}\gateway.ico"; Tasks: tray

; there is no [Run]: "start now" is the `startnow` task, run (and checked) by CurStepChanged, so a gateway that does not
; come up is reported instead of failing silently in a hidden window.

[Code]
const
  TlsPort = 8443;
  // the gateway checks each port of the range every few seconds: a range this big is a mistake, not a setting
  MaxRange = 1000;
  SupportUrl = 'https://github.com/JoaoVitor197843/pindrel/issues';

var
  ConfigPage: TInputQueryWizardPage;
  PortSuggested: Boolean;

// Settings, identity, certificates and the log live here, apart from the program: an upgrade or an uninstall that keeps
// the data never touches them. Per user: %LOCALAPPDATA%; for all users: %ProgramData%.
function DataDir(Param: String): String;
begin
  if IsAdminInstallMode then
    Result := ExpandConstant('{commonappdata}\Pindrel Gateway')
  else
    Result := ExpandConstant('{localappdata}\Pindrel Gateway');
end;

// What gateway.env says for a setting ('' when it is not set): the last line for a key wins, as in the gateway.
function ConfiguredValue(Key: String): String;
var
  Lines: TArrayOfString;
  I: Integer;
  L: String;
begin
  Result := '';
  if not LoadStringsFromFile(DataDir('') + '\gateway.env', Lines) then Exit;
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

// True unless the kept settings of an earlier install already serve HTTPS (TLS_PORT is what turns it on).
function HttpsMissing: Boolean;
begin
  Result := ConfiguredValue('TLS_PORT') = '';
end;

function Quoted(S: String): String;
begin
  StringChangeEx(S, '''', '''''', True);
  Result := '''' + S + '''';
end;

// The text for a failure nobody planned for: what failed, the detail, where the logs are and who to tell.
function UnexpectedText(Step, Detail: String): String;
begin
  Result := 'Ocorreu um erro inesperado ao ' + Step + '.' + #13#10 + #13#10 +
    'Detalhe: ' + Detail + #13#10 + #13#10 +
    'Onde olhar:' + #13#10 +
    '  • registro do gateway: ' + DataDir('') + '\gateway.log' + #13#10 +
    '  • registro do instalador: a pasta ' + GetEnv('TEMP') + ' (arquivos "Setup Log ... .txt")' + #13#10 + #13#10 +
    'Se o erro continuar, fale com quem mantém o projeto e anexe esses registros:' + #13#10 + SupportUrl;
end;

// Small scripts the wizard runs from its temporary folder (none of them opens a socket: that would make the Windows
// Firewall ask whether to let "Windows PowerShell" in).
//  probe-port.ps1 <port> <own gateway.exe> <out file>: exit 0 = free (or held by this very gateway, which the install
//    stops); 1 = taken (the name of the program holding it goes to <out file>, empty when no program listens there: a
//    range Windows reserved for Hyper-V/WSL/Docker).
//  probe-range.ps1 <first> <last> <own gateway.exe> <out file>: exit 0 = every port of the range is free; 1 = some are taken
//    (<out file> lists them, one per line, with the program or the reserved range).
//  wait-up.ps1 <port> <own gateway.exe> <seconds>: exit 0 as soon as this gateway listens on the port.
procedure WriteHelpers;
var
  P, R, W: TArrayOfString;
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

  SetArrayLength(R, 15);
  R[0] := 'param([int]$Lo, [int]$Hi, [string]$Own, [string]$Out)';
  R[1] := '$rows = @()';
  R[2] := '$seen = @{}';
  R[3] := 'foreach ($c in (Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue)) {';
  R[4] := '  if ($c.LocalPort -lt $Lo -or $c.LocalPort -gt $Hi -or $seen.ContainsKey($c.LocalPort)) { continue }';
  R[5] := '  $seen[$c.LocalPort] = 1';
  R[6] := '  $p = Get-Process -Id $c.OwningProcess -ErrorAction SilentlyContinue';
  R[7] := '  if ($p -and $p.Path -eq $Own) { continue }';
  R[8] := '  $n = "?"; if ($p) { $n = $p.ProcessName }';
  R[9] := '  $rows += ("porta {0} (programa {1})" -f $c.LocalPort, $n)';
  R[10] := '}';
  R[11] := 'foreach ($l in (netsh interface ipv4 show excludedportrange protocol=tcp)) {';
  R[12] := '  if ($l -match "^\s*(\d+)\s+(\d+)") { if ([int]$Matches[1] -le $Hi -and [int]$Matches[2] -ge $Lo) { $rows += ("portas {0} a {1} (reservadas pelo Windows)" -f $Matches[1], $Matches[2]) } }';
  R[13] := '}';
  R[14] := 'Set-Content -LiteralPath $Out -Value ($rows | Sort-Object) -Encoding UTF8; if ($rows.Count) { exit 1 } else { exit 0 }';
  Ok := SaveStringsToUTF8File(ExpandConstant('{tmp}\probe-range.ps1'), R, False) and Ok;

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
    IntToStr(Port) + ' "' + ExpandConstant('{app}\gateway.exe') + '" "' + OutFile + '"', '', SW_HIDE, ewWaitUntilTerminated, Rc) and (Rc = 1);
  if Result and LoadStringsFromFile(OutFile, S) and (GetArrayLength(S) > 0) then Who := Trim(S[0]);
end;

// The ports of the range that something else holds, as text ready for a message ('' when all are free).
function RangeBusy(Lo, Hi: Integer): String;
var
  Rc, I, N: Integer;
  OutFile: String;
  S: TArrayOfString;
begin
  Result := '';
  OutFile := ExpandConstant('{tmp}\range-busy.txt');
  DeleteFile(OutFile);
  if not (Exec('powershell.exe', '-NoProfile -ExecutionPolicy Bypass -File "' + ExpandConstant('{tmp}\probe-range.ps1') + '" ' +
    IntToStr(Lo) + ' ' + IntToStr(Hi) + ' "' + ExpandConstant('{app}\gateway.exe') + '" "' + OutFile + '"', '', SW_HIDE, ewWaitUntilTerminated, Rc) and (Rc = 1)) then Exit;
  if not LoadStringsFromFile(OutFile, S) then Exit;
  N := GetArrayLength(S);
  for I := 0 to N - 1 do
  begin
    if Trim(S[I]) = '' then Continue;
    if I >= 8 then
    begin
      Result := Result + '  … e mais ' + IntToStr(N - I) + #13#10;
      Break;
    end;
    Result := Result + '  • ' + Trim(S[I]) + #13#10;
  end;
end;

function PortText(Port: Integer; Who: String): String;
begin
  if Who <> '' then
    Result := 'A porta ' + IntToStr(Port) + ' já está em uso pelo programa "' + Who + '". Escolha outra porta.'
  else
    Result := 'A porta ' + IntToStr(Port) + ' não está disponível (reservada pelo Windows ou usada por um serviço do sistema). Escolha outra porta.';
end;

// four numbers from 0 to 255 separated by dots
function ValidIPv4(S: String): Boolean;
var
  I, Part, Digits, Dots, V: Integer;
  C: String;
begin
  Result := False;
  Part := 0; Digits := 0; Dots := 0; V := 0;
  for I := 1 to Length(S) do
  begin
    C := Copy(S, I, 1);
    if (C >= '0') and (C <= '9') then
    begin
      V := V * 10 + StrToInt(C);
      Digits := Digits + 1;
      if (Digits > 3) or (V > 255) then Exit;
    end
    else if C = '.' then
    begin
      if Digits = 0 then Exit;
      Dots := Dots + 1;
      Digits := 0; V := 0;
    end
    else
      Exit;
  end;
  Result := (Dots = 3) and (Digits > 0);
end;

procedure InitializeWizard;
begin
  WriteHelpers;
  ConfigPage := CreateInputQueryPage(wpSelectTasks, 'Configuração do gateway',
    'Como este servidor aparece na rede e onde está a API',
    'A API roda em várias cópias, cada uma numa porta do intervalo abaixo; o gateway reparte os pedidos entre elas. ' +
    'Você pode mudar tudo depois, editando o arquivo gateway.env (atalho no menu Iniciar).');
  ConfigPage.Add('Nome do servidor na rede:', False);
  ConfigPage.Add('Porta do gateway (a que os aparelhos acessam):', False);
  ConfigPage.Add('Endereço IP da API (127.0.0.1 se ela roda neste computador):', False);
  ConfigPage.Add('Porta inicial da API:', False);
  ConfigPage.Add('Porta final da API:', False);
  ConfigPage.Values[0] := 'Pindrel';
  ConfigPage.Values[1] := '8080';
  ConfigPage.Values[2] := '127.0.0.1';
  ConfigPage.Values[3] := '9000';
  ConfigPage.Values[4] := '9099';
end;

// The port written in gateway.env (a kept config on an upgrade is not what the wizard page holds).
function ConfiguredPort: Integer;
begin
  Result := StrToIntDef(ConfiguredValue('GATEWAY_PORT'), 8080);
end;

// An upgrade keeps gateway.env and skips its page, so HTTPS asked for now is checked here: its port must be free.
function UpgradeHttpsOk: Boolean;
var
  Who: String;
begin
  Result := False;
  if ConfiguredPort = TlsPort then
  begin
    MsgBox('O gateway já usa a porta ' + IntToStr(TlsPort) + ' (GATEWAY_PORT no gateway.env), que é a do HTTPS.' + #13#10 + #13#10 +
      'Mude a porta no gateway.env, ou desmarque o HTTPS.', mbError, MB_OK);
    Exit;
  end;
  if PortBusy(TlsPort, Who) then
  begin
    MsgBox(PortText(TlsPort, Who) + #13#10 + #13#10 + 'Ela é a porta do HTTPS: libere-a, ou desmarque o HTTPS.', mbError, MB_OK);
    Exit;
  end;
  Result := True;
end;

// an upgrade keeps the settings that are already there
function ShouldSkipPage(PageID: Integer): Boolean;
begin
  Result := (PageID = ConfigPage.ID) and FileExists(DataDir('') + '\gateway.env');
end;

function NextButtonClick(CurPageID: Integer): Boolean;
var
  Name, Ip, Who, Busy: String;
  Port, Lo, Hi, I: Integer;
begin
  Result := True;
  if (CurPageID = wpSelectTasks) and WizardIsTaskSelected('https') and FileExists(DataDir('') + '\gateway.env') then
  begin
    Result := UpgradeHttpsOk;
    Exit;
  end;
  if CurPageID <> ConfigPage.ID then Exit;
  Name := Trim(ConfigPage.Values[0]);
  Ip := Trim(ConfigPage.Values[2]);
  Port := StrToIntDef(Trim(ConfigPage.Values[1]), -1);
  Lo := StrToIntDef(Trim(ConfigPage.Values[3]), -1);
  Hi := StrToIntDef(Trim(ConfigPage.Values[4]), -1);
  Result := False;

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
  if (Port < 1) or (Port > 65535) then
  begin
    MsgBox('A porta do gateway deve ser um número de 1 a 65535. Você digitou "' + Trim(ConfigPage.Values[1]) + '".', mbError, MB_OK);
    Exit;
  end;
  if not ValidIPv4(Ip) then
  begin
    MsgBox('O endereço IP da API deve ter quatro números de 0 a 255 separados por ponto, como 127.0.0.1. Você digitou "' + Ip + '".' + #13#10 + #13#10 +
      'Use 127.0.0.1 se a API roda neste computador. Para outro tipo de endereço (IPv6, vários servidores), edite o gateway.env depois.', mbError, MB_OK);
    Exit;
  end;
  if (Lo < 1) or (Lo > 65535) then
  begin
    MsgBox('A porta inicial da API deve ser um número de 1 a 65535. Você digitou "' + Trim(ConfigPage.Values[3]) + '".', mbError, MB_OK);
    Exit;
  end;
  if (Hi < 1) or (Hi > 65535) then
  begin
    MsgBox('A porta final da API deve ser um número de 1 a 65535. Você digitou "' + Trim(ConfigPage.Values[4]) + '".', mbError, MB_OK);
    Exit;
  end;
  if Hi < Lo then
  begin
    MsgBox('A porta final (' + IntToStr(Hi) + ') não pode ser menor que a inicial (' + IntToStr(Lo) + '). Para uma só porta, repita o mesmo número.', mbError, MB_OK);
    Exit;
  end;
  if Hi - Lo + 1 > MaxRange then
  begin
    MsgBox('O intervalo da API tem ' + IntToStr(Hi - Lo + 1) + ' portas; o máximo é ' + IntToStr(MaxRange) + '. O gateway verifica cada porta a cada poucos segundos.', mbError, MB_OK);
    Exit;
  end;
  // a gateway whose own port is in the range of the API would send the requests to itself
  if (Copy(Ip, 1, 4) = '127.') and (Port >= Lo) and (Port <= Hi) then
  begin
    MsgBox('A porta do gateway (' + IntToStr(Port) + ') está dentro do intervalo da API (' + IntToStr(Lo) + ' a ' + IntToStr(Hi) + '): ' +
      'o gateway mandaria os pedidos para ele mesmo. Escolha uma porta fora do intervalo.', mbError, MB_OK);
    Exit;
  end;
  if WizardIsTaskSelected('https') and (Port = TlsPort) then
  begin
    MsgBox('A porta ' + IntToStr(TlsPort) + ' é a do HTTPS. Escolha outra porta para o gateway.', mbError, MB_OK);
    Exit;
  end;
  // before accepting anything: the ports must be free, or the gateway would die at start with "address in use"
  if PortBusy(Port, Who) then
  begin
    MsgBox(PortText(Port, Who), mbError, MB_OK);
    Exit;
  end;
  if WizardIsTaskSelected('https') and PortBusy(TlsPort, Who) then
  begin
    MsgBox(PortText(TlsPort, Who) + #13#10 + #13#10 + 'Ela é a porta do HTTPS: libere-a, ou volte e desmarque o HTTPS.', mbError, MB_OK);
    Exit;
  end;
  // the range is where the API will run: warn (the API could not use those ports), but let the person decide
  if Copy(Ip, 1, 4) = '127.' then
  begin
    Busy := RangeBusy(Lo, Hi);
    // only a warning: a silent install goes on (the API just cannot use those ports)
    if (Busy <> '') and (not WizardSilent) then
      if MsgBox('Estas portas do intervalo da API (' + IntToStr(Lo) + ' a ' + IntToStr(Hi) + ') já estão em uso:' + #13#10 + #13#10 + Busy + #13#10 +
        'A API não poderá usar essas portas. Continuar mesmo assim?', mbConfirmation, MB_YESNO or MB_DEFBUTTON2) = IDNO then
        Exit;
  end;
  Result := True;
end;

// the first time the page opens with a busy port (8080 is a common one), offer the first free one right away
procedure CurPageChanged(CurPageID: Integer);
var
  Port, P: Integer;
  Who, Owner: String;
begin
  if (ConfigPage = nil) or (CurPageID <> ConfigPage.ID) or PortSuggested then Exit;
  PortSuggested := True;
  Port := StrToIntDef(Trim(ConfigPage.Values[1]), -1);
  if (Port < 1) or (not PortBusy(Port, Who)) then Exit;
  Owner := Who;
  for P := Port + 1 to Port + 9 do
    if (not PortBusy(P, Who)) and (not (WizardIsTaskSelected('https') and (P = TlsPort))) then
    begin
      // a silent install asks nobody: it just takes the free port
      if not WizardSilent then
        MsgBox(PortText(Port, Owner) + #13#10 + #13#10 + 'Sugeri a porta ' + IntToStr(P) + ', que está livre; você pode mudar.', mbInformation, MB_OK);
      ConfigPage.Values[1] := IntToStr(P);
      Exit;
    end;
end;

procedure StopProgram(Exe: String);
var
  Rc: Integer;
begin
  // only the program of this folder, never another one that happens to have the same file name
  Exec('powershell.exe', '-NoProfile -ExecutionPolicy Bypass -Command "Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq ' +
    Quoted(ExpandConstant('{app}\') + Exe) + ' } | Stop-Process -Force"', '', SW_HIDE, ewWaitUntilTerminated, Rc);
end;

procedure StopGateway;
begin
  // the start script retries a gateway that dies; this file tells it that this stop is on purpose
  if DirExists(DataDir('')) then SaveStringsToFile(DataDir('') + '\stopped.flag', ['stop'], False);
  StopProgram('gateway.exe');
  StopProgram('pindrel-gateway-tray.exe');
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
  SetArrayLength(Start, 24);
  Start[0] := '# Written by the installer. Starts the gateway hidden; its messages go to gateway.log (and gateway.out.log).';
  Start[1] := '# If the gateway dies right away (a port that is still busy, say) it is tried again a few times; if it never comes up, a message says so.';
  Start[2] := '$exe = ' + Quoted(App + '\gateway.exe');
  Start[3] := '$data = ' + Quoted(Data);
  Start[4] := '$flag = "$data\stopped.flag"';
  Start[5] := '# the Windows Forms library (tens of MB) is loaded only when there is a message to show';
  Start[6] := 'function Say($text) { Add-Type -AssemblyName System.Windows.Forms; [void][System.Windows.Forms.MessageBox]::Show($text + [Environment]::NewLine + [Environment]::NewLine + "Registro: $data\gateway.log" + [Environment]::NewLine + "Se o problema continuar, fale com quem mantém o projeto: ' + SupportUrl + '", "Pindrel Gateway") }';
  Start[7] := 'try {';
  Start[8] := '  if (Get-Process gateway -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $exe }) { exit 0 }';
  Start[9] := '  Remove-Item -LiteralPath $flag -ErrorAction SilentlyContinue';
  Start[10] := '  Set-Location -LiteralPath $data';
  Start[11] := '  for ($i = 1; $i -le 6; $i++) {';
  Start[12] := '    if (-not (Test-Path -LiteralPath $exe)) { exit 0 }';
  Start[13] := '    # no -Wait: a gateway that stays up for 20 s has started, and this script leaves (a PowerShell left waiting would hold ~80 MB beside a gateway of ~9 MB)';
  Start[14] := '    $p = Start-Process -FilePath $exe -ArgumentList "--config", "`"$data\gateway.env`"" -WindowStyle Hidden -PassThru -RedirectStandardOutput "$data\gateway.out.log" -RedirectStandardError "$data\gateway.log"';
  Start[15] := '    if (-not $p.WaitForExit(20000)) { exit 0 }';
  Start[16] := '    if (Test-Path -LiteralPath $flag) { exit 0 }';
  Start[17] := '    Start-Sleep -Seconds 4';
  Start[18] := '  }';
  Start[19] := '  $why = ""; if (Test-Path -LiteralPath "$data\gateway.log") { $why = (Get-Content -LiteralPath "$data\gateway.log" -Encoding UTF8 -TotalCount 3) -join [Environment]::NewLine }';
  Start[20] := '  Say ("O gateway do Pindrel não conseguiu iniciar." + [Environment]::NewLine + [Environment]::NewLine + $why)';
  Start[21] := '} catch {';
  Start[22] := '  Say ("Erro inesperado ao iniciar o gateway: " + $_.Exception.Message)';
  Start[23] := '}';
  if not SaveStringsToUTF8File(App + '\start-gateway.ps1', Start, False) then
    RaiseException('não foi possível gravar ' + App + '\start-gateway.ps1');
  SetArrayLength(Stop, 4);
  Stop[0] := '# Written by the installer. Stops the gateway of this folder.';
  Stop[1] := '# The stopped.flag file tells start-gateway.ps1 that this stop is on purpose, so it does not start the gateway again.';
  Stop[2] := 'New-Item -ItemType File -Force -Path ' + Quoted(Data + '\stopped.flag') + ' | Out-Null';
  Stop[3] := 'Get-Process gateway -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq ' + Quoted(App + '\gateway.exe') + ' } | Stop-Process -Force';
  if not SaveStringsToUTF8File(App + '\stop-gateway.ps1', Stop, False) then
    RaiseException('não foi possível gravar ' + App + '\stop-gateway.ps1');
end;

// An upgrade keeps gateway.env as it is, but HTTPS asked for now must still turn on: the lines go at the end, where they
// win over anything above them. Certificates somebody else manages (TLS_CERT_FILE) stay theirs: only the port is added.
procedure AddHttps(Conf, Data: String);
var
  Lines: TArrayOfString;
  N: Integer;
begin
  SetArrayLength(Lines, 5);
  // ends a last line that has no line break (the gateway skips a line without "=")
  Lines[0] := '';
  Lines[1] := '# HTTPS ligado pelo instalador numa atualização';
  N := 2;
  if ConfiguredValue('TLS_CERT_FILE') = '' then
  begin
    Lines[N] := 'TLS_AUTO=true'; N := N + 1;
    if ConfiguredValue('TLS_DIR') = '' then
    begin
      Lines[N] := 'TLS_DIR=' + Data + '\tls'; N := N + 1;
    end;
  end;
  Lines[N] := 'TLS_PORT=' + IntToStr(TlsPort); N := N + 1;
  SetArrayLength(Lines, N);
  if not SaveStringsToUTF8File(Conf, Lines, True) then
    RaiseException('não foi possível acrescentar o HTTPS a ' + Conf);
end;

procedure WriteConfig;
var
  Data, Conf, Ip, Lo, Hi, Upstreams: String;
  Lines: TArrayOfString;
  N: Integer;
begin
  Data := DataDir('');
  Conf := Data + '\gateway.env';
  if FileExists(Conf) then
  begin
    if WizardIsTaskSelected('https') and HttpsMissing then AddHttps(Conf, Data);
    Exit;
  end;
  Ip := Trim(ConfigPage.Values[2]);
  Lo := IntToStr(StrToInt(Trim(ConfigPage.Values[3])));
  Hi := IntToStr(StrToInt(Trim(ConfigPage.Values[4])));
  if Lo = Hi then Upstreams := Ip + ':' + Lo else Upstreams := Ip + ':' + Lo + '-' + Hi;
  SetArrayLength(Lines, 10);
  Lines[0] := '# Configuração do gateway do Pindrel (gerado pelo instalador). Linhas "CHAVE=valor"; # comenta.';
  Lines[1] := '# Depois de editar, pare e inicie o gateway pelo ícone da bandeja ou pelos atalhos do menu Iniciar. Veja gateway.env.example na pasta do programa.';
  Lines[2] := 'SERVER_NAME=' + Trim(ConfigPage.Values[0]);
  Lines[3] := 'GATEWAY_PORT=' + IntToStr(StrToInt(Trim(ConfigPage.Values[1])));
  Lines[4] := 'UPSTREAMS=' + Upstreams;
  Lines[5] := 'SERVER_ID_FILE=' + Data + '\server.id';
  Lines[6] := 'KNOWN_SERVERS_FILE=' + Data + '\known-servers.pb';
  N := 7;
  if WizardIsTaskSelected('https') then
  begin
    Lines[N] := 'TLS_AUTO=true'; N := N + 1;
    Lines[N] := 'TLS_DIR=' + Data + '\tls'; N := N + 1;
    Lines[N] := 'TLS_PORT=' + IntToStr(TlsPort); N := N + 1;
  end;
  SetArrayLength(Lines, N);
  if not SaveStringsToUTF8File(Conf, Lines, False) then
    RaiseException('não foi possível gravar ' + Conf);
end;

// First lines of the gateway log, to say why it did not start.
function LastLogLines: String;
var
  Lines: TArrayOfString;
  I: Integer;
begin
  Result := '';
  if not LoadStringsFromFile(DataDir('') + '\gateway.log', Lines) then Exit;
  for I := 0 to GetArrayLength(Lines) - 1 do
    if (I < 3) and (Trim(Lines[I]) <> '') then Result := Result + Trim(Lines[I]) + #13#10;
end;

// What `gateway --check` says about the settings ('' when they are fine).
function CheckConfig: String;
var
  Rc: Integer;
  OutFile: String;
  Lines: TArrayOfString;
  I: Integer;
begin
  Result := '';
  OutFile := ExpandConstant('{tmp}\check.txt');
  DeleteFile(OutFile);
  if not Exec('cmd.exe', '/C ""' + ExpandConstant('{app}\gateway.exe') + '" --check --config "' + DataDir('') + '\gateway.env" > "' + OutFile + '" 2>&1"',
    '', SW_HIDE, ewWaitUntilTerminated, Rc) then
  begin
    Result := 'não foi possível executar o gateway.exe para validar a configuração.';
    Exit;
  end;
  if Rc = 0 then Exit;
  Result := 'o gateway recusou a configuração (código ' + IntToStr(Rc) + ').';
  if LoadStringsFromFile(OutFile, Lines) then
  begin
    Result := '';
    for I := 0 to GetArrayLength(Lines) - 1 do
      if Trim(Lines[I]) <> '' then Result := Result + Trim(Lines[I]) + #13#10;
  end;
end;

// Starts the gateway like the menu shortcut does, waits for it to listen and says what happened.
procedure StartAndReport;
var
  Rc, Port: Integer;
  Up: Boolean;
begin
  Port := ConfiguredPort;
  Exec('powershell.exe', '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + ExpandConstant('{app}\start-gateway.ps1') + '"',
    '', SW_HIDE, ewNoWait, Rc);
  Up := Exec('powershell.exe', '-NoProfile -ExecutionPolicy Bypass -File "' + ExpandConstant('{tmp}\wait-up.ps1') + '" ' + IntToStr(Port) +
    ' "' + ExpandConstant('{app}\gateway.exe') + '" 15', '', SW_HIDE, ewWaitUntilTerminated, Rc) and (Rc = 0);
  if Up then
    MsgBox('O gateway está rodando na porta ' + IntToStr(Port) + '.' + #13#10 + #13#10 +
      'Ele não tem janela: roda escondido. ' +
      'Para ver o que ele diz (e o código de pareamento), abra "Registro (gateway.log)" no menu Iniciar; para pará-lo, use "Parar o gateway" ou o ícone da bandeja.' + #13#10 + #13#10 +
      'Os dados ficam em: ' + DataDir(''), mbInformation, MB_OK)
  else
    MsgBox('O gateway foi instalado, mas ainda não respondeu na porta ' + IntToStr(Port) + '.' + #13#10 + #13#10 + LastLogLines + #13#10 +
      'Ele continua tentando em segundo plano e vai avisar na tela se não conseguir.' + #13#10 +
      'Registro: ' + DataDir('') + '\gateway.log' + #13#10 +
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
    WriteConfig;
    WriteScripts;
    if WizardIsTaskSelected('firewall') then
    begin
      Exec('netsh.exe', 'advfirewall firewall delete rule name="Pindrel Gateway"', '', SW_HIDE, ewWaitUntilTerminated, Rc);
      if (not Exec('netsh.exe', 'advfirewall firewall add rule name="Pindrel Gateway" dir=in action=allow enable=yes profile=private program="' +
        ExpandConstant('{app}\gateway.exe') + '"', '', SW_HIDE, ewWaitUntilTerminated, Rc)) or (Rc <> 0) then
        MsgBox('O gateway foi instalado, mas não consegui criar a regra no Firewall do Windows (código ' + IntToStr(Rc) + ').' + #13#10 +
          'Os aparelhos da rede só vão alcançá-lo depois de você liberar o gateway.exe no Firewall.', mbError, MB_OK);
    end;
    // refuse to leave a broken setting: say exactly what is wrong, and where to fix it
    Problem := CheckConfig;
    if Problem <> '' then
      MsgBox('O gateway foi instalado, mas a configuração tem um erro:' + #13#10 + #13#10 + Problem + #13#10 +
        'Abra "Configuração (gateway.env)" no menu Iniciar, corrija e inicie o gateway de novo.' + #13#10 +
        'Arquivo: ' + DataDir('') + '\gateway.env', mbError, MB_OK)
    else
    begin
      if WizardIsTaskSelected('tray') and (not WizardSilent) then
        Exec(ExpandConstant('{app}\pindrel-gateway-tray.exe'), '--data "' + DataDir('') + '"', '', SW_SHOW, ewNoWait, Rc);
      if WizardIsTaskSelected('startnow') and (not WizardSilent) then
        StartAndReport;
    end;
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
