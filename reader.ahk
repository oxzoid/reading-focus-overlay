
#NoEnv
#SingleInstance, Force
SetBatchLines, -1
CoordMode, Mouse, Screen
#Include Gdip.ahk

lineColor := 0xFF000000
toggle := false
hbm := 0, hdc := 0, gfx := 0

^+r:: ; Ctrl+Shift+R to toggle the angled pencil overlay
toggle := !toggle
if (toggle) {
    if !pToken := Gdip_Startup()
    {
        MsgBox, GDI+ failed to start. Exiting.
        ExitApp
    }
    Gui, +AlwaysOnTop -Caption +ToolWindow +LastFound +E0x80020
    Gui, Show, w300 h300 x0 y0 NoActivate
    hwnd := WinExist()
    hbm := CreateDIBSection(300, 300)
    hdc := CreateCompatibleDC()
    obm := SelectObject(hdc, hbm)
    gfx := Gdip_GraphicsFromHDC(hdc)
    Gdip_SetSmoothingMode(gfx, 4)
    SetTimer, Draw, 10
} else {
    SetTimer, Draw, Off
    Gui, Hide
    Gdip_DeleteGraphics(gfx)
    SelectObject(hdc, obm)
    DeleteObject(hbm)
    DeleteDC(hdc)
    Gdip_Shutdown(pToken)
}
return

^+c:: ; Ctrl+Shift+C to toggle color
if (toggle) {
    lineColor := (lineColor = 0xFF000000) ? 0xFF00FF00 : 0xFF000000
}
return

Draw:
MouseGetPos, x, y
Gdip_GraphicsClear(gfx)
xOffset := 13
yOffset := 10
pPen := Gdip_CreatePen(lineColor, 5)
Gdip_DrawLine(gfx, pPen, 0, 0, 200, 200)
Gdip_DeletePen(pPen)
UpdateLayeredWindow(hwnd, hdc, x + xOffset, y + yOffset, 300, 300)
return

