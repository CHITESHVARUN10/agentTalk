; AgentTalk Windows installer — Inno Setup 6
; Produces dist/AgentTalk-0.1.0-x64-setup.exe (model NOT bundled; downloaded on first run)

#define MyAppName "AgentTalk"
#define MyAppVersion "0.1.0"
#define MyAppPublisher "AgentTalk"
#define MyAppURL "https://github.com/CHITESHVARUN10/agentTalk"
#define MyAppExe "AgentTalk.exe"

[Setup]
AppId={{8B2F1A2E-3C4D-4E5F-9A6B-7C8D9E0F1A2B}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
DefaultDirName={autopf}\{#MyAppName}
DisableDirPage=no
DefaultGroupName={#MyAppName}
AllowNoIcons=yes
OutputDir=..\..\dist
OutputBaseFilename=AgentTalk-{#MyAppVersion}-x64-setup
Compression=lzma
SolidCompression=yes
WizardStyle=modern
ArchitecturesInstallIn64BitMode=x64
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
CloseApplications=yes
RestartApplications=no
SetupIconFile=..\src-tauri\icons\icon.ico
UninstallDisplayIcon={app}\{#MyAppExe}

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked
Name: "autostart"; Description: "Launch at startup"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
; Tauri bundle output (adjust after first build; Inno wants the built exe + resources)
Source: "..\src-tauri\target\release\bundle\nsis\AgentTalk_*_x64-setup.exe"; DestDir: "{tmp}"; Flags: deleteafterinstall; Permissions: everyone-modify
Source: "..\src-tauri\target\release\AgentTalk.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\src-tauri\target\release\*.dll"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExe}"
Name: "{group}\{cm:UninstallProgram,{#MyAppName}}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExe}"; Tasks: desktopicon
Name: "{userstartup}\{#MyAppName}"; Filename: "{app}\{#MyAppExe}"; Tasks: autostart

[Run]
Filename: "{app}\{#MyAppExe}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent

; Model dir is %APPDATA%\AgentTalk\models — created by rust-core on first run via dirs::data_dir().
; No bundled ggml-large-v3-turbo.bin.

[Code]
function InitializeSetup(): Boolean;
begin
  Result := True;
end;
