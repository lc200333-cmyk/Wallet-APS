#define MyAppName "Wallet APS"
#define MyAppVersion "0.4.3"
#define MyAppPublisher "Wallet APS"
#define MyAppExeName "wallet_aps.exe"

[Setup]
AppId={{94F89A42-1716-4D1F-8752-A3A3F89B1123}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL=https://github.com/lc200333-cmyk/Wallet-APS
AppSupportURL=https://github.com/lc200333-cmyk/Wallet-APS/issues
AppUpdatesURL=https://github.com/lc200333-cmyk/Wallet-APS/releases
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
UninstallDisplayName=Uninstall Wallet APS
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
Name: "{app}\Uninstall Wallet APS"; Filename: "{uninstallexe}"; IconFilename: "{sys}\shell32.dll"; IconIndex: 31

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent
