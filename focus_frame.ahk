; ──────────────────────────────────────────────────────────────
;  Focus‑Frame (Snipping‑Tool clone)  •  darker background
;  build 16‑May‑2025  v4.5.3
; ──────────────────────────────────────────────────────────────
#Requires AutoHotkey v2.0
#SingleInstance Force
CoordMode "Mouse", "Screen"

; — crosshair cursor —
plusPath := A_Temp "\plus_cursor.cur"
FileInstall "plus_cursor.cur", plusPath, 1
crossCur := plusPath


; ====== CONFIG ======
DIM_DRAG  := 120    ; overlay alpha while selecting   (0‑255; lower = lighter)
DIM_FINAL := 225    ; overlay alpha after selection   (0‑255; higher = darker)

; ====== GLOBALS ======
global clickBlock := false
global haveFrame  := false, frame := {x:0,y:0,w:0,h:0}
global dimShown := false, snipActive := false
global dragStart := {x:0,y:0}
global dimGui := 0, frameGui := 0, toolbarGui := 0
global selectMode := "rectangle"  ; "rectangle" or "polygon"
global polyPoints := [], polyGui := []
global drawing := false
global toolbarDragging := false
global toolbarPos := {x:0, y:10}
global inToolbarArea := false
global toolbarVisible := true

; Math helper function
ATan2(y, x) {
    return DllCall("msvcrt\atan2", "Double", y, "Double", x, "Double")
}

OnMessage(0x201, Snip_LButtonDown)
OnMessage(0x200, Snip_MouseMove)
OnMessage(0x202, Snip_LButtonUp)

; — Hotkeys —
^+F::ToggleFocusFrame()
+Esc::ShiftEsc()
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
        ; Start with rectangle mode by default
        selectMode := "rectangle"
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
        selectMode := "rectangle"  ; Reset to rectangle mode
        EnterSnipMode()
    }
}

; — Toolbar UI —
CreateToolbar() {
    global toolbarGui, selectMode, toolbarPos, toolbarVisible
    
    ; Destroy any existing toolbar to create a fresh one
    if (toolbarGui) {
        try {
            toolbarGui.Destroy()
        } catch {
            ; GUI might already be destroyed, ignore error
        }
        toolbarGui := 0
    }
    
    ; Create a fresh toolbar GUI - NO WS_EX_NOACTIVATE flag to allow button clicks
    toolbarGui := Gui("+AlwaysOnTop -Caption +Owner" . dimGui.Hwnd)
    toolbarGui.BackColor := "White"
    
    ; Add a bit of padding and border effect with drag handle
    dragArea := toolbarGui.AddText("x0 y0 w170 h24 Center", "≡  Selection Mode  ≡")
    dragArea.SetFont("s10 Bold", "Segoe UI")
    dragArea.OnEvent("Click", ToolbarDragStart)
    
    ; Rectangle mode button (icon: □)
    rectBtn := toolbarGui.AddButton("x40 y32 w32 h32 " . (selectMode = "rectangle" ? "+Default" : ""), "□")
    rectBtn.OnEvent("Click", SwitchToRectMode)
    
    ; Polygon mode button (icon: ⬡)
    polyBtn := toolbarGui.AddButton("x80 y32 w32 h32 " . (selectMode = "polygon" ? "+Default" : ""), "⬡")
    polyBtn.OnEvent("Click", SwitchToPolyMode)
    
    ; Close button (icon: ✕)
    closeBtn := toolbarGui.AddButton("x122 y32 w32 h32", "✕")
    closeBtn.OnEvent("Click", CancelSnip)
    
    ; Position at stored position or default top center
    if (toolbarPos.x == 0)
        toolbarPos.x := A_ScreenWidth/2 - 85
    
    ; Show toolbar
    toolbarVisible := true
    try {
        toolbarGui.Show("w170 h70 x" . toolbarPos.x . " y" . toolbarPos.y)
    } catch {
        ; Handle possible show errors
        MsgBox("Failed to create toolbar")
    }
}

SwitchToRectMode(*) {
    global selectMode, toolbarGui, toolbarPos, toolbarVisible
    selectMode := "rectangle"
    
    ; Show toolbar if hidden
    if (!toolbarGui || !WinExist("ahk_id " toolbarGui.Hwnd)) {
        CreateToolbar()
    } else {
        toolbarVisible := true
        toolbarGui.Show("NA")  ; Show without activating
    }
}

SwitchToPolyMode(*) {
    global selectMode, toolbarGui, toolbarVisible
    selectMode := "polygon"
    
    ; Keep toolbar visible in polygon mode too
    toolbarVisible := true
    if (!toolbarGui || !WinExist("ahk_id " toolbarGui.Hwnd)) {
        CreateToolbar()
    } else {
        toolbarGui.Show("NA")  ; Show without activating
    }
}

ToolbarDragStart(*) {
    global toolbarDragging
    toolbarDragging := true
}

IsMouseOverToolbar() {
    global toolbarGui, toolbarVisible
    
    if (!toolbarGui || !toolbarVisible || !WinExist("ahk_id " toolbarGui.Hwnd))
        return false
    
    try {
        ; Get toolbar position and size
        WinGetPos &tbX, &tbY, &tbW, &tbH, "ahk_id " toolbarGui.Hwnd
        
        ; Get mouse position
        MouseGetPos &mouseX, &mouseY
        
        ; Check if mouse is over toolbar
        return (mouseX >= tbX && mouseX <= tbX + tbW && 
                mouseY >= tbY && mouseY <= tbY + tbH)
    } catch {
        return false
    }
}

; — Snip mode —
EnterSnipMode(){
    global snipActive, dimGui, frameGui, dimShown, polyPoints, toolbarVisible
    if snipActive
        return
    snipActive := true
    
    ; Clear polygon points
    polyPoints := []
    ClearPolyGuis()
    
    ; Register ESC hotkey once
    Hotkey("Esc", CancelSnip, "On")
    
    dimShown := true

    dimGui := Gui("+AlwaysOnTop -Caption +ToolWindow")
    dimGui.BackColor := "Black"
    WinSetTransparent(DIM_DRAG, dimGui.Hwnd)     ; light dim while dragging
    dimGui.Show("Maximize")

    frameGui := Gui("+AlwaysOnTop -Caption +ToolWindow")
    frameGui.BackColor := "White"
    WinSetTransparent(255, frameGui.Hwnd)
    frameGui.Show("x0 y0 w1 h1")
    
    ; Always create a fresh toolbar - destroyed at each cycle
    toolbarVisible := true
    CreateToolbar()

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
    global snipActive, dragStart, selectMode, polyPoints, drawing, toolbarDragging, toolbarGui, inToolbarArea, toolbarVisible
    if !snipActive
        return 0
        
    MouseGetPos &sx, &sy
    
    ; Check if mouse is over toolbar and if toolbar is visible
    inToolbarArea := toolbarVisible && IsMouseOverToolbar()
    
    if (inToolbarArea) {
        ; If we're in the title bar area of toolbar (top 24px), start dragging
        if (toolbarGui) {
            WinGetPos &tbX, &tbY, &tbW, &tbH, "ahk_id " toolbarGui.Hwnd
            if (sy - tbY < 24)
                toolbarDragging := true
        }
        ; Let the click pass directly to the button - don't handle it here
        return
    }
    
    if (selectMode = "rectangle") {
        dragStart.x := sx, dragStart.y := sy
    } 
    else if (selectMode = "polygon") {
        ; Add new point to polygon
        polyPoints.Push({x: sx, y: sy})
        
        ; Create a small dot to mark the vertex
        dotGui := Gui("+AlwaysOnTop -Caption +ToolWindow")
        dotGui.BackColor := "Red"
        dotGui.Show("x" (sx-3) " y" (sy-3) " w6 h6")
        polyGui.Push(dotGui)
        
        ; If we have at least two points, draw the line segment
        if (polyPoints.Length > 1) {
            lastIndex := polyPoints.Length
            p1 := polyPoints[lastIndex-1]
            p2 := polyPoints[lastIndex]
            DrawLine(p1.x, p1.y, p2.x, p2.y)
        }
        
        ; Check if polygon can be closed (3+ points and click near starting point)
        if (polyPoints.Length >= 3) {
            startPoint := polyPoints[1]
            if (Abs(sx - startPoint.x) < 10 && Abs(sy - startPoint.y) < 10) {
                ; Close the polygon
                DrawLine(sx, sy, startPoint.x, startPoint.y)
                FinishPolygon()
            }
        }
    }
    return 0
}

Snip_MouseMove(*) {
    global snipActive, frameGui, dimGui, dragStart, selectMode, polyPoints, drawing, toolbarDragging, toolbarGui, toolbarPos, toolbarVisible
    if !snipActive
        return 0
        
    MouseGetPos &cx, &cy
    
    ; Handle toolbar dragging
    if (toolbarDragging && toolbarGui && WinExist("ahk_id " toolbarGui.Hwnd)) {
        ; Move toolbar with mouse
        toolbarPos.x := cx - 85  ; Half of toolbar width
        toolbarPos.y := cy - 12  ; Half of title bar height
        toolbarGui.Show("x" toolbarPos.x " y" toolbarPos.y " NoActivate")
        return 0
    }
    
    ; Skip rectangle drawing if mouse is over toolbar and not dragging
    if (toolbarVisible && IsMouseOverToolbar() && !GetKeyState("LButton", "P"))
        return 0
        
    if (selectMode = "rectangle" && GetKeyState("LButton","P")) {
        x := Min(cx, dragStart.x), y := Min(cy, dragStart.y)
        w := Abs(cx - dragStart.x), h := Abs(cy - dragStart.y)
        if (w < 2 || h < 2)
            return 0
        frameGui.Show("x" x " y" y " w" w " h" h)
        SetRingRegion(frameGui.Hwnd, w, h)
        UpdateDimHole(dimGui.Hwnd, x, y, w, h)
    }
    return 0
}

Snip_LButtonUp(*) {
    global snipActive, frame, haveFrame, dimShown, dragStart, selectMode, toolbarDragging, inToolbarArea
    
    ; End toolbar dragging if active
    if (toolbarDragging) {
        toolbarDragging := false
        return 0
    }
    
    if !snipActive
        return 0
        
    ; If we clicked in toolbar area, skip processing
    if (inToolbarArea) {
        inToolbarArea := false
        ; Don't capture this click, let it pass through
        return
    }
        
    if (selectMode = "rectangle") {
        MouseGetPos &ex, &ey
        frame := {x:Min(ex,dragStart.x), y:Min(ey,dragStart.y)
                 ,w:Abs(ex-dragStart.x), h:Abs(ey-dragStart.y)}
        if (frame.w < 4 || frame.h < 4) {
            return 0  ; Don't cancel snip on small/accidental clicks
        }
        haveFrame := true, dimShown := true
        TearDownSnip("keep")
    }
    return 0
}

DrawLine(x1, y1, x2, y2) {
    global polyGui
    
    ; Calculate line properties
    w := Abs(x2 - x1) + 1
    h := Abs(y2 - y1) + 1
    x := Min(x1, x2)
    y := Min(y1, y2)
    
    ; Create line GUI
    lineGui := Gui("+AlwaysOnTop -Caption +ToolWindow")
    lineGui.BackColor := "Red"
    lineGui.Show("x" x " y" y " w" w " h" h)
    
    ; Create the line shape
    if (x1 != x2 || y1 != y2) {  ; Not a point
        hDC := DllCall("GetDC", "Ptr", lineGui.Hwnd, "Ptr")
        
        ; Calculate angle and length
        angle := ATan2(y2 - y1, x2 - x1)
        length := Sqrt((x2 - x1)**2 + (y2 - y1)**2)
        
        ; Create points for line region
        thickness := 2  ; Line thickness
        halfThick := thickness / 2
        
        points := Buffer(8 * 4)  ; 4 points, 8 bytes each (x,y are 4 bytes each)
        
        ; Calculate perpendicular offset
        dx := Sin(angle) * halfThick
        dy := -Cos(angle) * halfThick
        
        ; Point 1: Start + offset
        NumPut("Int", Round(x1 - x + dx), points, 0)
        NumPut("Int", Round(y1 - y + dy), points, 4)
        
        ; Point 2: End + offset
        NumPut("Int", Round(x2 - x + dx), points, 8)
        NumPut("Int", Round(y2 - y + dy), points, 12)
        
        ; Point 3: End - offset
        NumPut("Int", Round(x2 - x - dx), points, 16)
        NumPut("Int", Round(y2 - y - dy), points, 20)
        
        ; Point 4: Start - offset
        NumPut("Int", Round(x1 - x - dx), points, 24)
        NumPut("Int", Round(y1 - y - dy), points, 28)
        
        ; Create polygon region
        hRgn := DllCall("CreatePolygonRgn", "Ptr", points, "Int", 4, "Int", 1, "Ptr")
        
        ; Apply region to window
        DllCall("SetWindowRgn", "Ptr", lineGui.Hwnd, "Ptr", hRgn, "Int", 1)
        DllCall("ReleaseDC", "Ptr", lineGui.Hwnd, "Ptr", hDC)
    }
    
    polyGui.Push(lineGui)
}

FinishPolygon() {
    global polyPoints, frame, haveFrame, dimShown
    
    ; Calculate bounding box
    minX := polyPoints[1].x, maxX := polyPoints[1].x
    minY := polyPoints[1].y, maxY := polyPoints[1].y
    
    for i, point in polyPoints {
        minX := Min(minX, point.x)
        maxX := Max(maxX, point.x)
        minY := Min(minY, point.y)
        maxY := Max(maxY, point.y)
    }
    
    ; Create frame from bounding box
    frame := {x:minX, y:minY, w:maxX-minX, h:maxY-minY}
    
    ; Create polygon region for dimmer
    UpdatePolygonRegion()
    
    haveFrame := true
    dimShown := true
    TearDownSnip("keep")
}

UpdatePolygonRegion() {
    global dimGui, polyPoints
    
    if (!dimGui || !polyPoints.Length)
        return
    
    ; Create polygon region points buffer
    pointCount := polyPoints.Length
    points := Buffer(8 * pointCount)  ; 8 bytes per point (4 for x, 4 for y)
    
    ; Fill points buffer
    for i, point in polyPoints {
        NumPut("Int", point.x, points, (i-1)*8)
        NumPut("Int", point.y, points, (i-1)*8+4)
    }
    
    ; Create polygon region
    polyRgn := DllCall("CreatePolygonRgn", "Ptr", points, "Int", pointCount, "Int", 1, "Ptr")
    
    ; Create full screen region
    fullRgn := DllCall("CreateRectRgn", "Int", 0, "Int", 0, "Int", A_ScreenWidth, "Int", A_ScreenHeight, "Ptr")
    
    ; Combine regions to create hole
    finalRgn := DllCall("CreateRectRgn", "Int", 0, "Int", 0, "Int", 0, "Int", 0, "Ptr")
    DllCall("CombineRgn", "Ptr", finalRgn, "Ptr", fullRgn, "Ptr", polyRgn, "Int", 3)  ; RGN_DIFF = 3
    
    ; Apply region to dimmer window
    DllCall("SetWindowRgn", "Ptr", dimGui.Hwnd, "Ptr", finalRgn, "Int", 1)
    
    ; Clean up
    DllCall("DeleteObject", "Ptr", polyRgn)
    DllCall("DeleteObject", "Ptr", fullRgn)
}

ClearPolyGuis() {
    global polyGui
    
    ; Destroy all polygon point and line GUIs
    for i, gui in polyGui {
        if (gui)
            gui.Destroy()
    }
    polyGui := []
}

TearDownSnip(mode) {
    global snipActive, dimGui, frameGui, selectMode, polyGui, toolbarGui, toolbarVisible
    snipActive := false
    
    ; Unregister the ESC hotkey when snip mode ends
    Hotkey("Esc", CancelSnip, "Off")
    
    DllCall("ReleaseCapture")
    DllCall("SystemParametersInfo", "UInt", 0x57, "UInt", 0, "UInt", 0, "UInt", 0x1)
    
    ; Clean up polygon guides if they exist
    ClearPolyGuis()
    
    ; Hide and destroy the toolbar when exiting snip mode
    toolbarVisible := false
    if (toolbarGui) {
        try {
            toolbarGui.Destroy()
            toolbarGui := 0
        } catch {
            ; Ignore errors if GUI already destroyed
        }
    }
    
    if frameGui {
        try {
            frameGui.Destroy()
            frameGui := 0
        } catch {
            ; Ignore errors if GUI already destroyed
        }
    }
    
    if mode = "cancel" {
        if dimGui {
            try {
                dimGui.Destroy()
                dimGui := 0
            } catch {
                ; Ignore errors if GUI already destroyed
            }
        }
        dimGui := 0
        dimShown := false
    } else {
        ShowDimmer(DIM_FINAL)  ; darker after selection
    }
}

; — Dimmer helpers —
ShowDimmer(alpha) {
    global dimGui, frame, selectMode, polyPoints
    
    if !dimGui {
        dimGui := Gui("+AlwaysOnTop -Caption +ToolWindow")
        dimGui.BackColor := "Black"
        dimGui.Show("Maximize")
    }
    
    WinSetTransparent(alpha, dimGui.Hwnd)
    
    if (selectMode = "polygon" && polyPoints.Length >= 3) {
        UpdatePolygonRegion()
    } else {
        UpdateDimHole(dimGui.Hwnd, frame.x, frame.y, frame.w, frame.h)
    }
}

DestroyDimmer() {
    global dimGui, dimShown
    if dimGui
        dimGui.Destroy(), dimGui := 0
    dimShown := false
}

UpdateDimHole(hwnd, x, y, w, h) {
    full := DllCall("CreateRectRgn", "int", 0, "int", 0, "int", A_ScreenWidth, "int", A_ScreenHeight, "ptr")
    hole := DllCall("CreateRectRgn", "int", x, "int", y, "int", x+w, "int", y+h, "ptr")
    DllCall("CombineRgn", "ptr", full, "ptr", full, "ptr", hole, "int", 3)
    DllCall("SetWindowRgn", "ptr", hwnd, "ptr", full, "int", true)
}