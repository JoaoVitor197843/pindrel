; Inno Setup script of the Windows installer (and, with it, the uninstaller). Built by .github/workflows/release-desktop.yml:
;   ISCC /DAppVersion=1.2.0 /DSourceDir=<build\windows\x64\runner\Release> /O<dir> /F<file name without .exe> pindrel.iss
; The portable zip is the same folder, without this.
#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
#ifndef SourceDir
  #define SourceDir "..\..\build\windows\x64\runner\Release"
#endif

[Setup]
; Identifies the app for upgrades and for "Apps & features". NEVER change it: a new one would install side by side with the
; old version and leave the old uninstaller orphaned.
AppId={{D4E1145B-EF08-4C02-A1F9-DC21CD185461}
AppName=Pindrel
AppVersion={#AppVersion}
AppVerName=Pindrel {#AppVersion}
AppPublisher=Pindrel
AppPublisherURL=https://github.com/JoaoVitor197843/pindrel
AppSupportURL=https://github.com/JoaoVitor197843/pindrel/issues
AppUpdatesURL=https://github.com/JoaoVitor197843/pindrel/releases
VersionInfoVersion={#AppVersion}
DefaultDirName={autopf}\Pindrel
DisableProgramGroupPage=yes
DisableDirPage=auto
; per user by default (no administrator needed, lands in %LOCALAPPDATA%\Programs); the first dialog offers "all users"
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
SetupIconFile=..\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\Pindrel.exe
UninstallDisplayName=Pindrel
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
; an open Pindrel is closed (and restarted) by the installer instead of leaving files in use
CloseApplications=yes
RestartApplications=yes

[Languages]
Name: "ptbr"; MessagesFile: "compiler:Languages\BrazilianPortuguese.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\Pindrel"; Filename: "{app}\Pindrel.exe"
Name: "{autodesktop}\Pindrel"; Filename: "{app}\Pindrel.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\Pindrel.exe"; Description: "{cm:LaunchProgram,Pindrel}"; Flags: nowait postinstall skipifsilent

[Code]
// Where the app keeps what it writes: %APPDATA%\<company>\<product> (path_provider and flutter_secure_storage read both from
// windows\runner\Runner.rc, which says Pindrel twice). Notes, settings and the encrypted session are all in there.
function DataDir: String;
begin
  Result := ExpandConstant('{userappdata}\Pindrel\Pindrel');
end;

function PurgeAsked: Boolean;
var
  I: Integer;
begin
  Result := False;
  for I := 1 to ParamCount do
    if CompareText(ParamStr(I), '/PURGE') = 0 then Result := True;
end;

// Uninstalling keeps the notes unless the person says otherwise. A silent uninstall (updates, scripts) never asks and
// keeps them; /PURGE on the command line erases them without asking.
procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  Erase: Boolean;
begin
  if CurUninstallStep <> usPostUninstall then Exit;
  if not DirExists(DataDir) then Exit;
  Erase := PurgeAsked;
  if (not Erase) and (not UninstallSilent) then
    Erase := MsgBox(
      'Apagar também as suas notas e configurações deste computador?' + #13#10 + #13#10 +
      'Se você escolher "Não", elas continuam guardadas e voltam se você instalar o Pindrel de novo.' + #13#10 +
      'Nada é apagado nos servidores.',
      mbConfirmation, MB_YESNO or MB_DEFBUTTON2) = IDYES;
  if Erase then
  begin
    DelTree(DataDir, True, True, True);
    RemoveDir(ExpandConstant('{userappdata}\Pindrel')); // the company folder, once it is empty
  end;
end;
