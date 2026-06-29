; Sparta Windows installer script (NSIS)
; Produces an unsigned setup.exe. Code-signing is not yet applied.
;
; Build with:
;   makensis -DVERSION=0.1.0 -DEXE_PATH=sparta.exe sparta.nsi
; or let the release workflow set VERSION and EXE_PATH.

!define APPNAME    "Sparta"
!define PUBLISHER  "Lacaedemon"
!define REGKEY     "Software\${PUBLISHER}\${APPNAME}"
!define UNINST_KEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APPNAME}"

; --- Metadata ---
Name              "${APPNAME} ${VERSION}"
OutFile           "sparta-${VERSION}-windows-setup.exe"
InstallDir        "$PROGRAMFILES64\${APPNAME}"
InstallDirRegKey  HKLM "${REGKEY}" "InstallDir"
RequestExecutionLevel admin
SetCompressor     /SOLID lzma

; --- Pages ---
Page directory
Page instfiles
UninstPage uninstConfirm
UninstPage instfiles

; --- Installer ---
Section "Sparta (required)"
  SectionIn RO

  SetOutPath "$INSTDIR"
  File "${EXE_PATH}"

  ; Start-menu shortcut
  CreateDirectory "$SMPROGRAMS\${APPNAME}"
  CreateShortcut  "$SMPROGRAMS\${APPNAME}\${APPNAME}.lnk" "$INSTDIR\sparta.exe"
  CreateShortcut  "$SMPROGRAMS\${APPNAME}\Uninstall ${APPNAME}.lnk" "$INSTDIR\uninstall.exe"

  ; Desktop shortcut
  CreateShortcut "$DESKTOP\${APPNAME}.lnk" "$INSTDIR\sparta.exe"

  ; Registry: install path + uninstall info
  WriteRegStr HKLM "${REGKEY}"     "InstallDir" "$INSTDIR"
  WriteRegStr HKLM "${UNINST_KEY}" "DisplayName"          "${APPNAME}"
  WriteRegStr HKLM "${UNINST_KEY}" "DisplayVersion"       "${VERSION}"
  WriteRegStr HKLM "${UNINST_KEY}" "Publisher"            "${PUBLISHER}"
  WriteRegStr HKLM "${UNINST_KEY}" "UninstallString"      '"$INSTDIR\uninstall.exe"'
  WriteRegStr HKLM "${UNINST_KEY}" "QuietUninstallString" '"$INSTDIR\uninstall.exe" /S'
  WriteRegDWORD HKLM "${UNINST_KEY}" "NoModify" 1
  WriteRegDWORD HKLM "${UNINST_KEY}" "NoRepair" 1

  WriteUninstaller "$INSTDIR\uninstall.exe"
SectionEnd

; --- Uninstaller ---
Section "Uninstall"
  Delete "$INSTDIR\sparta.exe"
  Delete "$INSTDIR\uninstall.exe"
  RMDir "$INSTDIR"

  Delete "$SMPROGRAMS\${APPNAME}\${APPNAME}.lnk"
  Delete "$SMPROGRAMS\${APPNAME}\Uninstall ${APPNAME}.lnk"
  RMDir  "$SMPROGRAMS\${APPNAME}"
  Delete "$DESKTOP\${APPNAME}.lnk"

  DeleteRegKey HKLM "${UNINST_KEY}"
  DeleteRegKey HKLM "${REGKEY}"
SectionEnd
