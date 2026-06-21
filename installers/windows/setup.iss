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
; Use user-local install directory so no elevation is needed.
;
; NOTE: These conditionals MUST be line-based (#ifdef ... #else ... #endif),
; NOT the inline form ({#ifdef ...}...{#else}...{#endif}). The inline form
; breaks when a branch contains nested braces such as {localappdata} or the
; inline emit {#MyAppName}: ISPP's inline brace-matcher mis-parses where the
; branches end, and the Beta branch leaks through even on a stable build
; (PRE_RELEASE undefined). That caused stable releases to install into
; "{localappdata}\Front Porch AI Beta". OutputBaseFilename happened to work
; only because its branches were plain text with no nested braces.
#ifdef PRE_RELEASE
; Beta AND Rawhide Nightly builds both live here (both are built with PRE_RELEASE).
DefaultDirName={localappdata}\{#MyAppName} Beta
#else
; Stable channel. v0.9.9.0.1 shipped with the inline-conditional brace bug above,
; which recorded the WRONG "...\Front Porch AI Beta" directory for stable installs.
; Because Inno remembers the previous install location by AppId, a normal /VERYSILENT
; auto-update would silently reinstall right back into that wrong folder forever.
; So for stable we take charge of the directory ourselves:
;   * UsePreviousAppDir=no    -> don't blindly reuse the recorded (bugged) path
;   * DefaultDirName via code  -> force the correct stable folder, while still
;                                honoring a genuine user-chosen custom location.
; The stray Beta folder is cleaned up in [Code] (CurStepChanged) ONLY when no
; Rawhide Nightly is present, because Nightly/Beta legitimately share that folder.
UsePreviousAppDir=no
DefaultDirName={code:GetStableInstallDir}
#endif
#ifdef NIGHTLY
DefaultGroupName=Front Porch AI Nightly
#else
DefaultGroupName={#MyAppName}
#endif
LicenseFile={#MyAppLicenseFile}
#ifdef PRE_RELEASE
OutputBaseFilename=Front_Porch_AI_Beta_Setup
#else
OutputBaseFilename=Front_Porch_AI_Setup
#endif
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
; Line-based conditionals (see DefaultDirName note above) — the inline form
; mis-parses because each branch contains nested braces ({group}, {app},
; {#MyAppName}, {#MyAppExeName}).
#ifdef NIGHTLY
Name: "{group}\Front Porch AI Nightly"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\Uninstall Front Porch AI Nightly"; Filename: "{uninstallexe}"
Name: "{autodesktop}\Front Porch AI Nightly"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon
#else
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\Uninstall {#MyAppName}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon
#endif

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
// ── Stable install-directory self-heal (v0.9.9.0.1 Beta-folder bug) ──────────
//
// Hardcoded AppId (must match [Setup] AppId) used to read Inno's recorded
// previous install directory from the uninstall registry key.
const
  APP_ID = '{B7E2F8A1-4D3C-4E5B-9F1A-2C8D6E0F3B9A}';

// The directory recorded by Inno BEFORE this run overwrites it. Captured in
// InitializeSetup so it is still the OLD value when CurStepChanged runs.
var
  PrevInstallDirAtStart: String;

function CorrectStableDir(): String;
begin
  Result := ExpandConstant('{localappdata}\Front Porch AI');
end;

function BuggedBetaDir(): String;
begin
  Result := ExpandConstant('{localappdata}\Front Porch AI Beta');
end;

// Inno records the last install directory under this AppId. Per-user installs
// (PrivilegesRequired=lowest) land in HKCU; check it first, then machine-wide.
function RecordedInstallDir(): String;
var
  Key, V: String;
begin
  Result := '';
  Key := 'Software\Microsoft\Windows\CurrentVersion\Uninstall\' + APP_ID + '_is1';
  if RegQueryStringValue(HKCU, Key, 'Inno Setup: App Path', V) then
    Result := V
  else if RegQueryStringValue(HKLM, Key, 'Inno Setup: App Path', V) then
    Result := V;
end;

// DefaultDirName for STABLE builds. Forces the correct folder (repairing
// v0.9.9.0.1 installs that the bug placed in the Beta directory) while
// preserving any genuine custom location the user previously chose.
function GetStableInstallDir(Param: String): String;
var
  Prev: String;
begin
  Prev := RecordedInstallDir();
  if (Prev <> '') and
     (CompareText(Prev, CorrectStableDir()) <> 0) and
     (CompareText(Prev, BuggedBetaDir()) <> 0) then
    Result := Prev                 // genuine custom path -> honor it
  else
    Result := CorrectStableDir();  // fresh / already-correct / bugged-Beta -> correct dir
end;

// True if a Rawhide Nightly build is installed. Nightly and Beta share the
// "...\Front Porch AI Beta" folder, so we use Nightly's DEDICATED Start Menu
// group to detect it and NEVER delete a folder a Nightly user relies on.
function IsRawhideNightlyInstalled(): Boolean;
begin
  Result := DirExists(ExpandConstant('{userprograms}\Front Porch AI Nightly')) or
            DirExists(ExpandConstant('{commonprograms}\Front Porch AI Nightly'));
end;

function InitializeSetup(): Boolean;
begin
  PrevInstallDirAtStart := RecordedInstallDir();
  Result := True;
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssPostInstall then
  begin
    // Clean up the stray Beta folder left by the v0.9.9.0.1 bug, but ONLY when:
    //   1. the previously-tracked install was literally the Beta folder (the bug
    //      signature) — captured before the registry was overwritten this run,
    //   2. this install now lives somewhere else (we relocated stable out), and
    //   3. NO Rawhide Nightly is present (Nightly/Beta share that folder).
    // Beta/Nightly installs of THIS app have {app} == the Beta folder, so the
    // {app} <> Beta check makes them skip this entirely.
    if (CompareText(PrevInstallDirAtStart, BuggedBetaDir()) = 0) and
       (CompareText(ExpandConstant('{app}'), BuggedBetaDir()) <> 0) and
       (not IsRawhideNightlyInstalled()) and
       DirExists(BuggedBetaDir()) then
    begin
      DelTree(BuggedBetaDir(), True, True, True);
    end;
  end;
end;

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
