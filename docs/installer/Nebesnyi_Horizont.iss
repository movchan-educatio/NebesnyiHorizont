; Inno Setup 6 template for «Небесний Горизонт»
; Build:
;   "C:\Program Files (x86)\Inno Setup 6\ISCC.exe" docs\installer\Nebesnyi_Horizont.iss
;
; Before building:
;   1. Export the release EXE to build\Nebesnyi_Horizont_v10.exe
;   2. Copy EXE + README.md + LICENSE + CREDITS.md into dist_v10\
;   3. Adjust MyAppVersion / MyAppExeName / SourceDir below.

#define MyAppName "Небесний Горизонт"
#define MyAppVersion "10.0"
#define MyAppPublisher "Nebesnyi Horizont"
#define MyAppExeName "Nebesnyi_Horizont_v10.exe"
#define MyAppDirName "Nebesnyi Horizont"
#define MySourceDir "..\..\dist_v10"
#define MyOutputDir "..\..\installer_output"
#define MyIconFile "..\..\icon.ico"

[Setup]
AppId={{B7E7B8A2-6B7F-4E7A-9A5E-2C4B5C2E4F10}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} {#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\{#MyAppDirName}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
OutputDir={#MyOutputDir}
OutputBaseFilename=Nebesnyi_Horizont_Setup
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=admin
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
; SetupIconFile={#MyIconFile}
UninstallDisplayIcon={app}\{#MyAppExeName}
LicenseFile={#MySourceDir}\LICENSE
VersionInfoVersion={#MyAppVersion}
VersionInfoCompany={#MyAppPublisher}
VersionInfoDescription={#MyAppName} installer
VersionInfoProductName={#MyAppName}
VersionInfoProductVersion={#MyAppVersion}
; Optional code signing:
; SignTool=signtool sign /fd SHA256 /tr http://timestamp.digicert.com /td SHA256 $f
; SignedUninstaller=yes

[Languages]
Name: "ukrainian"; MessagesFile: "compiler:Languages\Ukrainian.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
; The whole dist folder: EXE + README + LICENSE + CREDITS.
Source: "{#MySourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\{cm:UninstallProgram,{#MyAppName}}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
; Settings live in %LOCALAPPDATA%; keep them by default. Uncomment only if the
; player explicitly wants a full wipe.
; Type: filesandordirs; Name: "{localappdata}\Godot\app_userdata\{#MyAppName}"

#if !FileExists(AddBackslash(SourcePath) + MySourceDir + "\" + MyAppExeName)
  #error "Не знайдено dist_v10\Nebesnyi_Horizont_v10.exe. Спочатку зберіть реліз і скопіюйте файли в dist_v10."
#endif

[Code]
function InitializeSetup(): Boolean;
begin
  Result := True;
end;
