#define MyAppName "Wallet APS Design"
#define MyAppVersion "0.7.8"
#define MyAppPublisher "Wallet APS"
#define MyAppExeName "wallet_aps.exe"

[Setup]
AppId={{A48D2FEA-EA47-49EF-A311-60C3761EA817}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL=https://github.com/lc200333-cmyk/Wallet-APS-Design
AppSupportURL=https://github.com/lc200333-cmyk/Wallet-APS-Design/issues
AppUpdatesURL=https://github.com/lc200333-cmyk/Wallet-APS-Design/releases
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
OutputDir=..\..\dist
OutputBaseFilename=Wallet-APS-Setup-{#MyAppVersion}
Compression=lzma
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=lowest
SetupIconFile=..\..\app\windows\runner\resources\app_icon.ico
Uninstallable=yes
UninstallFilesDir={app}\Uninstall
UninstallDisplayName=Uninstall Wallet APS Design
UninstallDisplayIcon={uninstallexe}

[Languages]
Name: "russian"; MessagesFile: "compiler:Languages\Russian.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "..\..\app\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon
Name: "{app}\Uninstall Wallet APS Design"; Filename: "{uninstallexe}"; IconFilename: "{sys}\shell32.dll"; IconIndex: 31

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent
