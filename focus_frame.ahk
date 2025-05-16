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
global lastClickTime := 0
global clickThreshold := 200  ; milliseconds
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
        Sleep 20  ; Add a small delay to ensure cleanup
    }
    
    ; Create a fresh toolbar GUI - NO WS_EX_NOACTIVATE flag to allow button clicks
    toolbarGui := Gui("+AlwaysOnTop -Caption +Owner" . dimGui.Hwnd)
    toolbarGui.BackColor := "White"  ; Reverted to original color
    
    ; Add a bit of padding and border effect with drag handle
    dragArea := toolbarGui.AddText("x0 y0 w170 h24 Center", "≡  Selection Mode  ≡")
    dragArea.SetFont("s10 Bold", "Segoe UI")
    dragArea.OnEvent("Click", ToolbarDragStart)
    
    ; Rectangle mode button (icon: □) with highlighting for current mode
    rectBtn := toolbarGui.AddButton("x40 y32 w32 h32", "□")
    try {
        if (selectMode = "rectangle") {
            rectBtn.Opt("+Background44AA44")  ; Green background for selected mode
        }
        rectBtn.OnEvent("Click", SwitchToRectMode)
    } catch {
        ; Ignore any errors with control options
    }
    
    ; Polygon mode button (icon: ⬡) with highlighting for current mode
    polyBtn := toolbarGui.AddButton("x80 y32 w32 h32", "⬡")
    try {
        if (selectMode = "polygon") {
            polyBtn.Opt("+Background44AA44")  ; Green background for selected mode
        }
        polyBtn.OnEvent("Click", SwitchToPolyMode)
    } catch {
        ; Ignore any errors with control options
    }
    
    ; Close button (icon: ✕)
    closeBtn := toolbarGui.AddButton("x122 y32 w32 h32", "✕")
    try {
        closeBtn.OnEvent("Click", CancelSnip)
    } catch {
        ; Ignore any errors with control options
    }
    
    ; Add arrow indicators for keyboard navigation
    arrowText := toolbarGui.AddText("x0 y64 w170 h20 Center", "1  2  3")
    try {
        arrowText.SetFont("s9", "Segoe UI")
    } catch {
        ; Ignore any errors with control options
    }
    
    ; Position at stored position or default top center
    if (toolbarPos.x == 0)
        toolbarPos.x := A_ScreenWidth/2 - 85
    
    ; Show toolbar
    toolbarVisible := true
    try {
        toolbarGui.Show("w170 h90 x" . toolbarPos.x . " y" . toolbarPos.y)  ; Increased height to accommodate arrow text
    } catch {
        ; Handle possible show errors
        ; MsgBox("Failed to create toolbar")  ; Removed MsgBox to avoid interruption
    }
}
SwitchToRectMode(*) {
    global selectMode, toolbarGui, toolbarPos, toolbarVisible, polyPoints
    global frameGui, frame, haveFrame, dimGui
    
    ; Disable the event handler temporarily to prevent recursion
    try {
        if (IsObject(toolbarGui) && toolbarGui.Hwnd) {
            toolbarGui.Opt("-E")  ; Disable events
        }
    } catch {
        ; Ignore errors if GUI already destroyed
    }
    
    selectMode := "rectangle"
    
    ; Clear any active polygon points and lines
    polyPoints := []
    ClearPolyGuis()
    
    ; Clear rectangle - more aggressive approach
    try {
        if (IsObject(frameGui)) {
            try {
                frameGui.Destroy()  ; Completely destroy the frame GUI
            } catch {
                ; Ignore errors if already destroyed
            }
        }
    } catch {
        ; Ignore errors if frameGui is not an object
    }
    
    ; Create a fresh frameGui
    try {
        frameGui := Gui("+AlwaysOnTop -Caption +ToolWindow")  ; Create fresh one
        frameGui.BackColor := "White"
        frameGui.Show("x0 y0 w1 h1 Hide")  ; Create hidden until needed
    } catch {
        ; Ignore errors if creation fails
    }
    
    ; Reset frame data
    frame := {x:0, y:0, w:0, h:0}
    haveFrame := false  ; Important: reset the frame flag
    
    ; Reset dimmer hole if dimmer exists
    try {
        if (IsObject(dimGui) && dimGui.Hwnd && WinExist("ahk_id " dimGui.Hwnd)) {
            UpdateDimHole(dimGui.Hwnd, 0, 0, 0, 0)  ; Remove hole but keep dimmer
        }
    } catch {
        ; Ignore errors if dimGui is invalid
    }
    
    ; Add a delay before creating new toolbar
    Sleep 50
    
    ; Show toolbar with updated mode
    try {
        CreateToolbar()  ; Recreate to refresh highlighting
        toolbarVisible := true
        if (IsObject(toolbarGui) && toolbarGui.Hwnd) {
            toolbarGui.Show("NA")  ; Show without activating
        }
    } catch {
        ; Ignore errors if show fails
    }
}

SwitchToPolyMode(*) {
    global selectMode, toolbarGui, toolbarVisible, polyPoints
    global frameGui, frame, haveFrame, dimGui
    
    ; Disable the event handler temporarily to prevent recursion
    try {
        if (IsObject(toolbarGui) && toolbarGui.Hwnd) {
            toolbarGui.Opt("-E")  ; Disable events
        }
    } catch {
        ; Ignore errors if GUI already destroyed
    }
    
    selectMode := "polygon"
    
    ; Clear any active polygon points and lines
    polyPoints := []
    ClearPolyGuis()
    
    ; Clear rectangle - more aggressive approach
    try {
        if (IsObject(frameGui)) {
            try {
                frameGui.Destroy()  ; Completely destroy the frame GUI
            } catch {
                ; Ignore errors if already destroyed
            }
        }
    } catch {
        ; Ignore errors if frameGui is not an object
    }
    
    ; Create a fresh frameGui
    try {
        frameGui := Gui("+AlwaysOnTop -Caption +ToolWindow")  ; Create fresh one
        frameGui.BackColor := "White"
        frameGui.Show("x0 y0 w1 h1 Hide")  ; Create hidden until needed
    } catch {
        ; Ignore errors if creation fails
    }
    
    ; Reset frame data
    frame := {x:0, y:0, w:0, h:0}
    haveFrame := false  ; Important: reset the frame flag
    
    ; Reset dimmer hole if dimmer exists
    try {
        if (IsObject(dimGui) && dimGui.Hwnd && WinExist("ahk_id " dimGui.Hwnd)) {
            UpdateDimHole(dimGui.Hwnd, 0, 0, 0, 0)  ; Remove hole but keep dimmer
        }
    } catch {
        ; Ignore errors if dimGui is invalid
    }
    
    ; Add a delay before creating new toolbar
    Sleep 50
    
    ; Show toolbar with updated mode
    try {
        CreateToolbar()  ; Recreate to refresh highlighting
        toolbarVisible := true
        if (IsObject(toolbarGui) && toolbarGui.Hwnd) {
            toolbarGui.Show("NA")  ; Show without activating
        }
    } catch {
        ; Ignore errors if show fails
    }
}
ToolbarDragStart(*) {
    global toolbarDragging
    toolbarDragging := true
}

IsMouseOverToolbar() {
    global toolbarGui, toolbarVisible
    
    if (!toolbarGui || !toolbarVisible)
        return false
        
    try {
        if (!WinExist("ahk_id " toolbarGui.Hwnd))
            return false
            
        ; Get toolbar position and size
        WinGetPos &tbX, &tbY, &tbW, &tbH, "ahk_id " toolbarGui.Hwnd
        
        ; Get mouse position
        MouseGetPos &mouseX, &mouseY
        
        ; Check if mouse is over toolbar
        return (mouseX >= tbX && mouseX <= tbX + tbW && 
                mouseY >= tbY && mouseY <= tbY + tbH)
    } catch {
        return false  ; Return false on any error
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
    
    ; Register number keys for mode selection
    Hotkey("1", SwitchToRectMode, "On")
    Hotkey("2", SwitchToPolyMode, "On")
    Hotkey("3", CancelSnip, "On")
    
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
    global snipActive, dimGui, frameGui, toolbarGui, polyGui
    
    ; Set flag first to prevent re-entry
    if !snipActive
        return
    
    ; Immediately set this to prevent further processing
    snipActive := false
    
    ; Restore system cursor immediately
    DllCall("SystemParametersInfo", "UInt", 0x57, "UInt", 0, "UInt", 0, "UInt", 0x1)
    
    ; Release capture to ensure the mouse is free
    DllCall("ReleaseCapture")
    
    ; Unregister hotkeys
    try {
        Hotkey("Esc", CancelSnip, "Off")
        Hotkey("1", SwitchToRectMode, "Off")
        Hotkey("2", SwitchToPolyMode, "Off")
        Hotkey("3", CancelSnip, "Off")
    } catch {
        ; Ignore errors if hotkeys already off
    }
    
    ; Clean up polygon guides
    ClearPolyGuis()
    
    ; More aggressive GUI cleanup - destroy in the correct order
    if (toolbarGui) {
        try {
            WinHide("ahk_id " toolbarGui.Hwnd)  ; Hide first
            Sleep 10
            toolbarGui.Destroy()
        } catch {
            ; Ignore errors
        }
        toolbarGui := 0
    }
    
    if (frameGui) {
        try {
            WinHide("ahk_id " frameGui.Hwnd)  ; Hide first
            Sleep 10
            frameGui.Destroy()
        } catch {
            ; Ignore errors
        }
        frameGui := 0
    }
    
    if (dimGui) {
        try {
            WinHide("ahk_id " dimGui.Hwnd)  ; Hide first
            Sleep 10
            dimGui.Destroy()
        } catch {
            ; Ignore errors
        }
        dimGui := 0
    }
    
    ; Reset all state variables
    global dimShown := false
    global toolbarVisible := false
    global haveFrame := false
    global frame := {x:0, y:0, w:0, h:0}
    global polyPoints := []
    
    ; Force a screen refresh
    Sleep 20
    DllCall("UpdateWindow", "Ptr", 0)  ; Update desktop window
    
    ; Remove the garbage collection code that's causing the warning
    ; since AutoHotkey v2 handles this automatically
    
    TearDownSnip("cancel")
}

Snip_LButtonDown(*) {
    global snipActive, dragStart, selectMode, polyPoints, drawing
    global toolbarDragging, toolbarGui, inToolbarArea, toolbarVisible
    global lastClickTime, clickThreshold, dimGui
    
    if !snipActive
        return 0
    
    ; Check for rapid clicking
    currentTime := A_TickCount
    clickInterval := currentTime - lastClickTime
    lastClickTime := currentTime
    
    ; If clicks are too rapid, handle specially
    if (clickInterval < clickThreshold) {
        ; Force a small delay
        Sleep 50
        ; Maybe redraw the screen
        if (IsObject(dimGui) && dimGui.Hwnd)
            WinRedraw("ahk_id " dimGui.Hwnd)
    }
    
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
        
        ; Check if frameGui is still valid
        try {
            if (IsObject(frameGui) && frameGui.Hwnd) {
                frameGui.Show("x" x " y" y " w" w " h" h)
                SetRingRegion(frameGui.Hwnd, w, h)
            }
        } catch {
            ; Recreate frameGui if it's invalid
            try {
                frameGui := Gui("+AlwaysOnTop -Caption +ToolWindow")
                frameGui.BackColor := "White"
                frameGui.Show("x" x " y" y " w" w " h" h)
                SetRingRegion(frameGui.Hwnd, w, h)
            } catch {
                ; If we still can't create it, just return
                return 0
            }
        }
        
        ; Check if dimGui is still valid before updating hole
        try {
            if (IsObject(dimGui) && dimGui.Hwnd) {
                UpdateDimHole(dimGui.Hwnd, x, y, w, h)
            }
        } catch {
            ; If dimGui is invalid, we can't update it
            return 0
        }
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
    
    ; Unregister number keys when snip mode ends
    Hotkey("1", SwitchToRectMode, "Off")
    Hotkey("2", SwitchToPolyMode, "Off")
    Hotkey("3", CancelSnip, "Off")
    
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
    ; Local variables to track resources
    full := 0
    hole := 0
    
    ; Validate input parameters
    if (!hwnd || !IsInteger(hwnd) || hwnd <= 0)
        return  ; Skip if hwnd is invalid
        
    ; Check if the window still exists
    if (!WinExist("ahk_id " hwnd))
        return  ; Window doesn't exist anymore
    
    try {
        ; Create full screen region
        full := DllCall("CreateRectRgn", "int", 0, "int", 0, "int", A_ScreenWidth, "int", A_ScreenHeight, "ptr")
        if (!full)
            return  ; Skip if region creation failed
            
        ; Create hole region
        hole := DllCall("CreateRectRgn", "int", x, "int", y, "int", x+w, "int", y+h, "ptr")
        if (!hole) {
            ; Clean up full region
            DllCall("DeleteObject", "ptr", full)
            return  ; Skip if region creation failed
        }
        
        ; Combine regions to create hole
        DllCall("CombineRgn", "ptr", full, "ptr", full, "ptr", hole, "int", 3)  ; RGN_DIFF = 3
        
        ; Apply region to window if it still exists
        if (WinExist("ahk_id " hwnd))
            DllCall("SetWindowRgn", "ptr", hwnd, "ptr", full, "int", 1)
        else
            DllCall("DeleteObject", "ptr", full)  ; Clean up if window gone
        
        ; Always clean up hole region
        DllCall("DeleteObject", "ptr", hole)
    } catch {
        ; Clean up any resources that might have been created
        if (hole)
            DllCall("DeleteObject", "ptr", hole)
        if (full)
            DllCall("DeleteObject", "ptr", full)
    }
}