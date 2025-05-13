; ──────────────────────────────────────────────────────────────
;  Focus‑Frame (Snipping‑Tool clone)  •  darker background
;  build 15‑May‑2025  v4.3
; ──────────────────────────────────────────────────────────────
#Requires AutoHotkey v2.0
#SingleInstance Force
CoordMode "Mouse", "Screen"

; — crosshair cursor —
crossCur := A_ScriptDir "\plus_cursor.cur"

; ====== CONFIG ======
DIM_DRAG  := 120    ; overlay alpha while selecting   (0‑255; lower = lighter)
DIM_FINAL := 225    ; overlay alpha after selection   (0‑255; higher = darker)

; ====== GLOBALS ======
global clickBlock := false
global haveFrame  := false, frame := {x:0,y:0,w:0,h:0}
global dimShown := false, snipActive := false
global dragStart := {x:0,y:0}
global dimGui := 0, frameGui := 0

OnMessage(0x201, Snip_LButtonDown)
OnMessage(0x200, Snip_MouseMove)
OnMessage(0x202, Snip_LButtonUp)

; — Hotkeys —
^+F::ToggleFocusFrame()
+Esc::ShiftEsc()
Esc::CancelSnip()
#HotIf clickBlock
*LButton::Return
*LButton Up::Return
#HotIf

; — Thin border helper —
SetRingRegion(hwnd, w, h, t:=2){
    o := DllCall("CreateRectRgn","int",0,"int",0,"int",w,"int",h,"ptr")
    i := DllCall("CreateRectRgn","int",t,"int",t,"int",w-t,"int",h-t,"ptr")
    r := DllCall("CreateRectRgn","int",0,"int",0,"int",0,"int",0,"ptr")
    DllCall("CombineRgn","ptr",r,"ptr",o,"ptr",i,"int",3)
    DllCall("SetWindowRgn","ptr",hwnd,"ptr",r,"int",true)
    DllCall("DeleteObject","ptr",o), DllCall("DeleteObject","ptr",i)
}

; — Focus‑Frame UX —
ToggleFocusFrame(){
    global haveFrame, dimShown
    if snipActive
        return
    if !haveFrame {
        EnterSnipMode()
        return
    }
    dimShown := !dimShown
    dimShown ? ShowDimmer(DIM_FINAL) : DestroyDimmer()
}
ShiftEsc(){
    if snipActive
        CancelSnip()
    else if dimShown {
        DestroyDimmer()
        EnterSnipMode()
    }
}

; — Snip mode —
EnterSnipMode(){
    global snipActive, dimGui, frameGui, dimShown
    if snipActive
        return
    snipActive := true
    dimShown   := true

    dimGui := Gui("+AlwaysOnTop -Caption +ToolWindow")
    dimGui.BackColor := "Black"
    WinSetTransparent(DIM_DRAG, dimGui.Hwnd)     ; light dim while dragging
    dimGui.Show("Maximize")

    frameGui := Gui("+AlwaysOnTop -Caption +ToolWindow")
    frameGui.BackColor := "White"
    WinSetTransparent(255, frameGui.Hwnd)
    frameGui.Show("x0 y0 w1 h1")

    DllCall("SetCapture","ptr",dimGui.Hwnd)
    hCur := DllCall("LoadCursorFromFile","str",crossCur,"ptr")
    if hCur
        DllCall("SetSystemCursor","ptr",hCur,"int",32512)
}
CancelSnip(*) {
    if snipActive
        TearDownSnip("cancel")
}
Snip_LButtonDown(*) {
    global snipActive, dragStart
    if !snipActive
        return 0
    MouseGetPos &sx,&sy
    dragStart.x := sx, dragStart.y := sy
    return 0
}
Snip_MouseMove(*) {
    global snipActive, frameGui, dimGui, dragStart
    if !snipActive || !GetKeyState("LButton","P")
        return 0
    MouseGetPos &cx,&cy
    x := Min(cx,dragStart.x), y := Min(cy,dragStart.y)
    w := Abs(cx-dragStart.x), h := Abs(cy-dragStart.y)
    if (w<2||h<2)
        return 0
    frameGui.Show("x" x " y" y " w" w " h" h)
    SetRingRegion(frameGui.Hwnd,w,h)
    UpdateDimHole(dimGui.Hwnd,x,y,w,h)
    return 0
}
Snip_LButtonUp(*) {
    global snipActive, frame, haveFrame, dimShown, dragStart
    if !snipActive
        return 0
    MouseGetPos &ex,&ey
    frame := {x:Min(ex,dragStart.x), y:Min(ey,dragStart.y)
             ,w:Abs(ex-dragStart.x), h:Abs(ey-dragStart.y)}
    if (frame.w<4||frame.h<4){
        TearDownSnip("cancel")
        return 0
    }
    haveFrame := true, dimShown := true
    TearDownSnip("keep")
    return 0
}
TearDownSnip(mode){
    global snipActive, dimGui, frameGui
    snipActive := false
    DllCall("ReleaseCapture")
    DllCall("SystemParametersInfo","UInt",0x57,"UInt",0,"UInt",0,"UInt",0x1)
    if frameGui
        frameGui.Destroy(), frameGui := 0
    if mode="cancel" {
        if dimGui
            dimGui.Destroy()
        dimGui := 0, dimShown := false
    } else
        ShowDimmer(DIM_FINAL)          ; darker after selection
}

; — Dimmer helpers —
ShowDimmer(alpha){
    global dimGui, frame
    if !dimGui {
        dimGui := Gui("+AlwaysOnTop -Caption +ToolWindow")
        dimGui.BackColor := "Black"
        dimGui.Show("Maximize")
    }
    WinSetTransparent(alpha, dimGui.Hwnd)
    UpdateDimHole(dimGui.Hwnd,frame.x,frame.y,frame.w,frame.h)
}
DestroyDimmer(){
    global dimGui, dimShown
    if dimGui
        dimGui.Destroy(), dimGui := 0
    dimShown := false
}
UpdateDimHole(hwnd,x,y,w,h){
    full := DllCall("CreateRectRgn","int",0,"int",0,"int",A_ScreenWidth,"int",A_ScreenHeight,"ptr")
    hole := DllCall("CreateRectRgn","int",x,"int",y,"int",x+w,"int",y+h,"ptr")
    DllCall("CombineRgn","ptr",full,"ptr",full,"ptr",hole,"int",3)
    DllCall("SetWindowRgn","ptr",hwnd,"ptr",full,"int",true)
}
