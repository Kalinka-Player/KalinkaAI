; Inno Setup script for the Kalinka Windows installer.
; Built in CI (release.yml) with:
;   iscc kalinka.iss /DAppVersion=X.Y.Z /DSourceDir=<Release bundle> \
;        /DOutputDir=<dist> /DOutputBaseFilename=kalinka-X.Y.Z-windows-x64-setup
; Defaults below allow a local build from the repo root: iscc packaging\windows\kalinka.iss

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
#ifndef SourceDir
  #define SourceDir "..\..\build\windows\x64\runner\Release"
#endif
#ifndef OutputDir
  #define OutputDir "..\..\dist"
#endif
#ifndef OutputBaseFilename
  #define OutputBaseFilename "kalinka-windows-x64-setup"
#endif

[Setup]
AppId={{B7C4D9E2-5A31-4F68-9D0C-1E8A72F3B654}
AppName=Kalinka
AppVersion={#AppVersion}
AppPublisher=Kalinka
AppPublisherURL=https://kalinkaplayer.com
AppSupportURL=https://github.com/Kalinka-Player/KalinkaAI/issues
DefaultDirName={autopf}\Kalinka
DisableProgramGroupPage=yes
; Per-user install by default (no UAC prompt); machine-wide offered via dialog.
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
LicenseFile=..\..\LICENSE
SetupIconFile=..\..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\kalinka.exe
WizardStyle=modern
Compression=lzma2/max
SolidCompression=yes
OutputDir={#OutputDir}
OutputBaseFilename={#OutputBaseFilename}

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\Kalinka"; Filename: "{app}\kalinka.exe"
Name: "{autodesktop}\Kalinka"; Filename: "{app}\kalinka.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\kalinka.exe"; Description: "{cm:LaunchProgram,Kalinka}"; Flags: nowait postinstall skipifsilent
