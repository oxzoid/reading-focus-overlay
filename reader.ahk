#Requires AutoHotkey v2.0
#SingleInstance Force
CoordMode("Mouse", "Screen")
#Include Gdip_All.ahk            ; keep this file beside reader.ahk

; ── embed pencil.png into the EXE at compile time ────────────────
pencilPath := A_Temp '\pencil.png'
FileInstall 'pencil.png', pencilPath, 1   ; << baked into .exe

maxEdge := 300        ; scale longest edge
offsetX := 10         ; shift right
offsetY := 10         ; shift down

global overlayOn := false
global blockClicks := false
global hGui := 0, hdc := 0, hbm := 0, obm := 0, gfx := 0, pBmp := 0
global sW := 0, sH := 0, pTok := 0

^+r:: ToggleOverlay()
^+b:: ToggleClickBlock()

ToggleOverlay() {
    global overlayOn, hGui, hdc, hbm, obm, gfx, pBmp, sW, sH, pTok, pencilPath, maxEdge
    overlayOn := !overlayOn
    if overlayOn {
        if !pTok := Gdip_Startup() {
            MsgBox 'GDI+ init failed', , 48
            overlayOn := false
            return
        }
        pBmp := Gdip_CreateBitmapFromFile(pencilPath)
        if !pBmp {
            MsgBox 'Embedded PNG failed to load', , 48
            overlayOn := false
            return
        }
        w := Gdip_GetImageWidth(pBmp), h := Gdip_GetImageHeight(pBmp)
        if w > h
            sW := maxEdge , sH := Round(maxEdge * h / w)
        else
            sH := maxEdge , sW := Round(maxEdge * w / h)

        ov := Gui('+AlwaysOnTop -Caption +ToolWindow +E0x80020', 'Pencil')
        ov.Show('w' sW ' h' sH ' x0 y0 NoActivate')
        hGui := ov.Hwnd

        hdc := CreateCompatibleDC()
        hbm := CreateDIBSection(sW, sH)
        obm := SelectObject(hdc, hbm)
        gfx := Gdip_GraphicsFromHDC(hdc)
        Gdip_SetSmoothingMode(gfx, 4)

        SetTimer Draw, 10
    } else {
        SetTimer Draw, 0
        GuiFromHwnd(hGui).Hide()
        Gdip_DisposeImage(pBmp)
        Gdip_DeleteGraphics(gfx)
        SelectObject(hdc, obm), DeleteObject(hbm), DeleteDC(hdc)
        Gdip_Shutdown(pTok)
    }
}

Draw(*) {
    global hGui, hdc, gfx, pBmp, sW, sH, offsetX, offsetY
    MouseGetPos &x, &y
    Gdip_GraphicsClear(gfx)
    DllCall('gdiplus\GdipDrawImageRect', 'ptr', gfx, 'ptr', pBmp
        , 'float', 0, 'float', 0, 'float', sW*1.0, 'float', sH*1.0)
    UpdateLayeredWindow(hGui, hdc, x + offsetX, y + offsetY, sW, sH)
}

ToggleClickBlock() {
    global blockClicks
    blockClicks := !blockClicks
    ToolTip blockClicks ? 'Click‑block ON' : 'Click‑block OFF', 0, 0, 1
    SetTimer () => ToolTip('',,,1), -700
}

#HotIf blockClicks && overlayOn
*LButton::Return
*LButton Up::Return
#HotIf
