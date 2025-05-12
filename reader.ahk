#NoEnv
#SingleInstance, Force
SetBatchLines, -1
CoordMode, Mouse, Screen
#Include Gdip.ahk

; ── settings ─────────────────────────────────────────────
lineColor   := 0xFF000000   ; black
blockClicks := true         ; start in “stimulus / no‑select” mode
overlayOn   := true         ; overlay visible at launch (set false to start hidden)

; ── build overlay ───────────────────────────────────────
if !pToken := Gdip_Startup() {
    MsgBox, GDI+ failed
    ExitApp
}
Gui, +AlwaysOnTop -Caption +ToolWindow +HwndhGui +E0x80020  ; always click‑through
if (overlayOn)
    Gui, Show, w300 h300 x0 y0 NoActivate
hbm := CreateDIBSection(300,300), hdc := CreateCompatibleDC()
obm := SelectObject(hdc,hbm),  gfx := Gdip_GraphicsFromHDC(hdc)
Gdip_SetSmoothingMode(gfx, 4)
SetTimer, Draw, 10

; ── hotkeys ─────────────────────────────────────────────
^+r::                         ; show / hide overlay (fixed)
    overlayOn := !overlayOn
    if (overlayOn)
        Gui, Show, NoActivate
    else
        Gui, Hide
return

^+c::                         ; toggle colour
    if (overlayOn)
        lineColor := (lineColor = 0xFF000000) ? 0xFF00FF00 : 0xFF000000
return

^+b::                         ; toggle click‑block mode
    blockClicks := !blockClicks
    Tooltip % blockClicks ? "Clicks BLOCKED" : "Clicks PASSTHRU"
    SetTimer, TooltipOff, -800
return
TooltipOff:
    Tooltip
return

; ── mouse filtering when blockClicks = true ─────────────
#If blockClicks
*LButton::Return
*LButton Up::Return
#If

; ── draw loop ────────────────────────────────────────────
Draw:
    if (!overlayOn)
        return
    MouseGetPos, x, y
    Gdip_GraphicsClear(gfx)
    xOffset := 10, yOffset := 10
    pPen := Gdip_CreatePen(lineColor, 5)
    Gdip_DrawLine(gfx, pPen, 0, 0, 200, 200)
    Gdip_DeletePen(pPen)
    UpdateLayeredWindow(hGui, hdc, x+xOffset, y+yOffset, 300, 300)
return
