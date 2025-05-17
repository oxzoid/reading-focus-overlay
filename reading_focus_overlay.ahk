#Requires AutoHotkey v2.0
#SingleInstance Force

;────────────────────────────────────────────────────────
;  Auto‑execute section: register callback, include code
;────────────────────────────────────────────────────────
OnExit(ExitCleanup)   ; pass function reference directly

#Include "config.ahk"
#Include "Gdip_All.ahk"
#Include "pencil_overlay.ahk"
#Include "distraction.ahk"
#Include "focus_frame.ahk"

return   ; ← marks end of auto‑execute

;────────────────────────────────────────────────────────
;  Exit handler (runs when script or EXE closes)
;────────────────────────────────────────────────────────
ExitCleanup(Reason, Code) {
    ; put any cleanup / restore logic here if you need it
    ; Example:
    ; MsgBox "Exiting – reason: " Reason " | code: " Code
}
