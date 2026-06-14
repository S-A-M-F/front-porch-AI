; Inno Setup Script for Front Porch AI
; Produces a Windows installer with AGPL V3 license acceptance

#define MyAppName "Front Porch AI"
#define MyAppPublisher "linux4life1"
#define MyAppURL "https://github.com/linux4life1/front-porch-AI"
#define MyAppExeName "front_porch_ai.exe"

[Setup]
AppId={{B7E2F8A1-4D3C-4E5B-9F1A-2C8D6E0F3B9A}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}/issues
; Use user-local install directory so no elevation is needed
DefaultDirName={#if PRE_RELEASE == 1}{localappdata}\{#MyAppName} Beta{#else}{localappdata}\{#MyAppName}{#endif}
DefaultGroupName={#if NIGHTLY == 1}Front Porch AI Nightly{#else}{#MyAppName}{#endif}
LicenseFile={#MyAppLicenseFile}
OutputBaseFilename={#if PRE_RELEASE == 1}Front_Porch_AI_Beta_Setup{#else}Front_Porch_AI_Setup{#endif}
OutputDir=.
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
SetupIconFile={#MyAppIconFile}
UninstallDisplayIcon={app}\{#MyAppExeName}
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
; Install per-user — avoids UAC elevation requirement and install failures
; Users can opt-in to a machine-wide install via the dialog
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
CloseApplications=yes
RestartApplications=yes
AppMutex=FrontPorchAI_{{B7E2F8A1-4D3C-4E5B-9F1A-2C8D6E0F3B9A}
; Require Windows 10 or later (Flutter + ANGLE requires it)
MinVersion=10.0

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[InstallDelete]
; Clean up bad desktop shortcuts created by the buggy 0.9.9 stable installer.
; That installer (due to a packaging bug when porting from the Rawhide nightly
; build script) created shortcuts named "Front Porch AI" (the stable name)
; but installed the app into the Beta location and made the .lnk point there.
; We only target the stable-named desktop shortcut so that legitimate Rawhide
; "Front Porch AI Nightly" shortcuts are left completely alone.
; This section runs early during install, before new shortcuts are created.
Type: files; Name: "{autodesktop}\Front Porch AI.lnk"

[Files]
; Main application files
Source: "{#MyAppBuildDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
; Bundle VC++ 2015-2022 Redistributable alongside the installer
; Downloaded by the CI build step before calling ISCC
Source: "{#MyAppBuildDir}\..\vc_redist.x64.exe"; DestDir: "{tmp}"; Flags: deleteafterinstall

[INI]
; Marker file so the app knows it was installed (not from zip)
; Self-update is disabled without this file
Filename: "{app}\.installed"; Section: "install"; Key: "method"; String: "innosetup"

[Icons]
Name: "{group}\{#if NIGHTLY == 1}Front Porch AI Nightly{#else}{#MyAppName}{#endif}"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\Uninstall {#if NIGHTLY == 1}Front Porch AI Nightly{#else}{#MyAppName}{#endif}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#if NIGHTLY == 1}Front Porch AI Nightly{#else}{#MyAppName}{#endif}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
; Install Visual C++ 2015-2022 Redistributable silently first.
; /install /quiet /norestart — suppresses all UI and reboot prompts.
; The check flag ensures we skip this if it's already installed at the required version.
Filename: "{tmp}\vc_redist.x64.exe"; Parameters: "/install /quiet /norestart"; \
  StatusMsg: "Installing Visual C++ Runtime (required)..."; \
  Check: VCRedistNeedsInstall; Flags: waituntilterminated

; Launch the app after install (user can uncheck this)
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent

[Code]
// Returns true if VC++ 2015-2022 x64 Redistributable is NOT already installed.
// Checks the registry key that Microsoft documents as the canonical detection method.
// See: https://learn.microsoft.com/en-us/cpp/windows/redistributing-visual-cpp-files
function VCRedistNeedsInstall: Boolean;
var
  Installed: Cardinal;
begin
  // The "Installed" DWORD under this key is set to 1 when VC++ 2022 x64 is present
  Result := not RegQueryDWordValue(
    HKLM,
    'SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\X64',
    'Installed',
    Installed
  ) or (Installed <> 1);
end;
