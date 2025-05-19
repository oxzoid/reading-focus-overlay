; ──────────────────────────────────────────────────────────────
;  Focus‑Frame (Snipping‑Tool clone)  •  darker background
;  build 16‑May‑2025  v4.6.0
; ──────────────────────────────────────────────────────────────
#Requires AutoHotkey v2.0
#SingleInstance Force
CoordMode "Mouse", "Screen"

; — crosshair cursor —
plusPath := A_Temp "\plus_cursor.cur"
FileInstall "plus_cursor.cur", plusPath, 1
crossCur := plusPath

; ====== CONFIG ======
DIM_DRAG := 120    ; overlay alpha while selecting   (0‑255; lower = lighter)
DIM_FINAL := 225    ; overlay alpha after selection   (0‑255; higher = darker)

; ====== GLOBALS ======
global lastClickTime := 0
global clickThreshold := 200  ; milliseconds
global clickBlock := false
global haveFrame := false, frame := { x: 0, y: 0, w: 0, h: 0 }
global dimShown := false, snipActive := false
global dragStart := { x: 0, y: 0 }
global dimGui := 0, frameGui := 0, toolbarGui := 0
global selectMode := "rectangle"  ; "rectangle" or "polygon"
global polyPoints := [], polyGui := []
global drawing := false
global toolbarDragging := false
global toolbarPos := { x: 0, y: 10 }
global inToolbarArea := false
global toolbarVisible := true
global activePolygons := []      ; Array to store multiple polygon definitions
global isDrawingPolygon := false ; Flag for polygon drawing state
global canvasGui := 0        ; The GUI window that acts as our canvas
global gdipToken := 0        ; GDI+ token for startup/shutdown
global gdipGraphics := 0     ; Graphics object for drawing
global canvasGui := 0
global memHDC := 0
global memBitmap := 0
global oldBitmap := 0

; Math helper function
ATan2(y, x) {
    return DllCall("msvcrt\atan2", "Double", y, "Double", x, "Double")
}
OnWM_LBUTTONDOWN(wParam, lParam, msg, hwnd) {
    Snip_LButtonDown(wParam, lParam, msg, hwnd)
}

OnWM_MOUSEMOVE(wParam, lParam, msg, hwnd) {
    Snip_MouseMove(wParam, lParam, msg, hwnd)
}

OnWM_LBUTTONUP(wParam, lParam, msg, hwnd) {
    Snip_LButtonUp(wParam, lParam, msg, hwnd)
}

; Then change your OnMessage calls to:
OnMessage(0x201, OnWM_LBUTTONDOWN)
OnMessage(0x200, OnWM_MOUSEMOVE)
OnMessage(0x202, OnWM_LBUTTONUP)

; — Hotkeys —
^+F:: ToggleFocusFrame()
+Esc:: ShiftEsc()
#HotIf clickBlock
*LButton:: return
*LButton Up:: return
#HotIf

; Remove the wrapper functions as they're not needed anymore

; — Thin border helper —
SetRingRegion(hwnd, w, h, t := 2) {
    o := DllCall("CreateRectRgn", "int", 0, "int", 0, "int", w, "int", h, "ptr")
    i := DllCall("CreateRectRgn", "int", t, "int", t, "int", w - t, "int", h - t, "ptr")
    r := DllCall("CreateRectRgn", "int", 0, "int", 0, "int", 0, "int", 0, "ptr")
    DllCall("CombineRgn", "ptr", r, "ptr", o, "ptr", i, "int", 3)
    DllCall("SetWindowRgn", "ptr", hwnd, "ptr", r, "int", true)
    DllCall("DeleteObject", "ptr", o), DllCall("DeleteObject", "ptr", i)
}
; Initialize GDI+ rendering system
InitGDIPlusCanvas() {
    global canvasGui, gdipToken, gdipGraphics

    ; Start GDI+
    gdipInput := Buffer(16, 0)
    NumPut("UInt", 1, gdipInput, 0)  ; Version = 1
    token := 0
    DllCall("gdiplus\GdiplusStartup", "UPtr*", &token, "Ptr", gdipInput, "Ptr", 0)
    gdipToken := token

    ; Create canvas GUI with transparent background
    canvasGui := Gui("+AlwaysOnTop -Caption +E0x80000 +LastFound")
    canvasGui.BackColor := "Black"
    WinSetTransColor("Black 255")  ; Make black fully transparent
    canvasGui.Show("x0 y0 w" A_ScreenWidth " h" A_ScreenHeight)

    ; Get device context for drawing
    hwnd := canvasGui.Hwnd
    hdc := DllCall("GetDC", "Ptr", hwnd)

    ; Create GDI+ graphics object
    pGraphics := 0
    DllCall("gdiplus\GdipCreateFromHDC", "Ptr", hdc, "UPtr*", &pGraphics)
    gdipGraphics := pGraphics

    ; Set high quality rendering
    DllCall("gdiplus\GdipSetSmoothingMode", "Ptr", pGraphics, "Int", 4)  ; Quality mode

    ; Release DC after creating graphics
    DllCall("ReleaseDC", "Ptr", hwnd, "Ptr", hdc)

    return true
}
; Clean up GDI+ resources
ShutdownGDIPlusCanvas() {
    global gdipToken, gdipGraphics, canvasGui

    ; Delete graphics object if it exists
    if (gdipGraphics) {
        DllCall("gdiplus\GdipDeleteGraphics", "Ptr", gdipGraphics)
        gdipGraphics := 0
    }

    ; Destroy canvas GUI
    if (canvasGui) {
        canvasGui.Destroy()
        canvasGui := 0
    }

    ; Shutdown GDI+
    if (gdipToken) {
        DllCall("gdiplus\GdiplusShutdown", "Ptr", gdipToken)
        gdipToken := 0
    }
}
; — Focus‑Frame UX —
ToggleFocusFrame() {
    global haveFrame, dimShown, snipActive

    if snipActive
        return

    ; Lock updates during state changes
    DllCall("LockWindowUpdate", "UInt", DllCall("GetDesktopWindow", "Ptr"))

    if !haveFrame {
        ; Start with rectangle mode by default
        selectMode := "rectangle"
        ; Release lock before entering snip mode, as it handles its own locking
        DllCall("LockWindowUpdate", "UInt", 0)
        EnterSnipMode()
        return
    }

    dimShown := !dimShown
    if (dimShown) {
        ShowDimmer(DIM_FINAL)
    } else {
        DestroyDimmer()
    }

    ; Release the lock
    DllCall("LockWindowUpdate", "UInt", 0)
}

ShiftEsc() {
    global activePolygons, polyPoints, polyGui

    if snipActive
        CancelSnip()
    else if dimShown {
        DestroyDimmer()

        ; Clear both active and in-progress polygons
        activePolygons := []
        polyPoints := []

        ; Clear any polygon visuals
        ClearPolyGuis()

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

    ; Add text explaining the polygon features
    if (selectMode = "polygon") {
        polyInfo := toolbarGui.AddText("x5 y84 w160 h30 Center", "Enter: Add polygon | Space: Finish")
        try {
            polyInfo.SetFont("s8", "Segoe UI")
        } catch {
            ; Ignore any errors with control options
        }
    }

    ; Position at stored position or default top center
    if (toolbarPos.x == 0)
        toolbarPos.x := A_ScreenWidth / 2 - 85

    ; Show toolbar
    toolbarVisible := true
    try {
        toolbarGui.Show("w170 h" (selectMode = "polygon" ? "110" : "90") " x" . toolbarPos.x . " y" . toolbarPos.y)  ; Increased height for polygon help text
    } catch {
        ; Handle possible show errors
        ; MsgBox("Failed to create toolbar")  ; Removed MsgBox to avoid interruption
    }
}

SwitchToRectMode(*) {
    global selectMode, toolbarGui, toolbarPos, toolbarVisible, polyPoints
    global frameGui, frame, haveFrame, dimGui, activePolygons, snipActive

    ; Disable the event handler temporarily to prevent recursion
    try {
        if (IsObject(toolbarGui) && toolbarGui.Hwnd) {
            toolbarGui.Opt("-E")  ; Disable events
        }
    } catch {
        ; Ignore errors if GUI already destroyed
    }

    selectMode := "rectangle"

    ; Disable polygon-specific hotkeys
    Hotkey("Enter", "Off")
    Hotkey("Space", "Off")
    Hotkey("Backspace", "Off")

    ; Clear any active polygon points and lines
    polyPoints := []
    activePolygons := []
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
    frame := { x: 0, y: 0, w: 0, h: 0 }
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
    global frameGui, frame, haveFrame, dimGui, activePolygons, snipActive

    ; Disable the event handler temporarily to prevent recursion
    try {
        if (IsObject(toolbarGui) && toolbarGui.Hwnd) {
            toolbarGui.Opt("-E")  ; Disable events
        }
    } catch {
        ; Ignore errors if GUI already destroyed
    }

    selectMode := "polygon"

    ; Explicitly register polygon-specific hotkeys
    Hotkey("Enter", PolygonEnterKey, "On")
    Hotkey("Space", PolygonSpaceKey, "On")
    Hotkey("Backspace", PolygonBackspaceKey, "On")
    Hotkey("+Backspace", ShiftBackspaceHandler, "On")
    ; Clear any active polygon points and lines
    polyPoints := []
    activePolygons := []
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
    frame := { x: 0, y: 0, w: 0, h: 0 }
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

; Dedicated hotkey functions for polygon mode
PolygonEnterKey(*) {
    global selectMode, snipActive
    if (selectMode = "polygon" && snipActive)
        FinishCurrentPolygon()  ; Just finish the current polygon, don't exit selection mode
}

global polyRenderingComplete := true

; Modify the PolygonSpaceKey function to check rendering status
PolygonSpaceKey(*) {
    global selectMode, snipActive, polyRenderingComplete

    if (selectMode = "polygon" && snipActive) {
        if (polyRenderingComplete) {
            FinishAllPolygons()  ; Only finish polygons if rendering is complete
        } else {
            ; Queue the finish action for when rendering completes
            SetTimer FinishWhenReady, -100  ; Retry in 100ms
        }
    }
}

; Add a new helper function
FinishWhenReady() {
    global polyRenderingComplete

    if (polyRenderingComplete) {
        FinishAllPolygons()
    } else {
        ; Still not ready, check again shortly
        SetTimer FinishWhenReady, -100
    }
}

PolygonBackspaceKey(*) {
    global selectMode, snipActive

    if (selectMode = "polygon" && snipActive) {
        ; Plain Backspace always removes the last point
        RemoveLastPoint()
    }
}

RemoveLastPoint(*) {
    global polyPoints, polyGui

    ; Do nothing if there are no points in the current polygon
    if (polyPoints.Length = 0)
        return

    ; Lock window updates completely
    DllCall("LockWindowUpdate", "UInt", DllCall("GetDesktopWindow", "Ptr"))

    ; Remove the last point
    polyPoints.Pop()

    ; Clear current polygon visuals
    ClearPolyGuis()

    ; Redraw existing completed polygons
    RedrawExistingPolygons()

    ; Now draw the current in-progress polygon (which isn't in activePolygons)
    if (polyPoints.Length > 0) {
        ; Draw all points
        for pointIndex, point in polyPoints {
            g := Gui("+AlwaysOnTop -Caption +ToolWindow")
            g.BackColor := "Red"
            g.Show("x" (point.x - 3) " y" (point.y - 3) " w6 h6 NA")
            polyGui.Push(g)
        }

        ; Then draw all lines
        for pointIndex, point in polyPoints {
            if (pointIndex > 1) {
                prevPoint := polyPoints[pointIndex - 1]
                DrawColoredLine(prevPoint.x, prevPoint.y, point.x, point.y, "Red")
            }
        }
    }

    ; Release the lock
    DllCall("LockWindowUpdate", "UInt", 0)
}
ShiftBackspaceHandler(*) {
    global selectMode, snipActive
    if (selectMode = "polygon" && snipActive)
        RemoveLastPolygon()
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
EnterSnipMode() {
    global snipActive, dimGui, frameGui, dimShown, polyPoints, toolbarVisible
    global activePolygons, selectMode

    if snipActive
        return
    snipActive := true

    ; Clear polygon points and active polygons
    polyPoints := []
    activePolygons := []
    ClearPolyGuis()

    ; Register ESC hotkey once
    Hotkey("Esc", CancelSnip, "On")

    ; Register number keys for mode selection
    Hotkey("1", SwitchToRectMode, "On")
    Hotkey("2", SwitchToPolyMode, "On")
    Hotkey("3", CancelSnip, "On")

    ; If starting in polygon mode, register those hotkeys
    if (selectMode = "polygon") {
        ;Hotkey("Enter", PolygonEnterKey, "On")
        ;Hotkey("Space", PolygonSpaceKey, "On")
        ;Hotkey("Backspace", PolygonBackspaceKey, "On")
        Hotkey("Enter", PolygonEnterKey, "On")
        Hotkey("Space", PolygonSpaceKey, "On")
        Hotkey("Backspace", RemoveLastPoint, "On")
        Hotkey("+Backspace", RemoveLastPolygon, "On")
    }

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

    DllCall("SetCapture", "ptr", dimGui.Hwnd)
    hCur := DllCall("LoadCursorFromFile", "str", crossCur, "ptr")
    if hCur
        DllCall("SetSystemCursor", "ptr", hCur, "int", 32512)
}

CancelSnip(*) {
    global snipActive, dimGui, frameGui, toolbarGui, polyGui
    global activePolygons

    ; Set flag first to prevent re-entry
    if !snipActive
        return

    ; Immediately set this to prevent further processing
    snipActive := false

    ; Lock updates to prevent flickering
    DllCall("LockWindowUpdate", "UInt", DllCall("GetDesktopWindow", "Ptr"))  ; Lock entire screen

    ; Restore system cursor immediately
    DllCall("SystemParametersInfo", "UInt", 0x57, "UInt", 0, "UInt", 0, "UInt", 0x1)

    ; Release capture to ensure the mouse is free
    DllCall("ReleaseCapture")

    ; Unregister hotkeys
    try {
        Hotkey("Esc", "Off")
        Hotkey("1", "Off")
        Hotkey("2", "Off")
        Hotkey("3", "Off")
        Hotkey("Enter", "Off")
        Hotkey("Space", "Off")
        Hotkey("Backspace", "Off")
        Hotkey("+Backspace", "Off")
    } catch {
        ; Ignore errors if hotkeys already off
    }

    ; Clean up polygon guides in one go without redrawing
    if (polyGui.Length > 0) {
        for i, gui in polyGui {
            if (IsObject(gui) && gui.Hwnd)
                gui.Destroy()
        }
        polyGui := []
    }

    ; Destroy GUIs directly without hiding first
    if (toolbarGui)
        try toolbarGui.Destroy(), toolbarGui := 0
    if (frameGui)
        try frameGui.Destroy(), frameGui := 0
    if (dimGui)
        try dimGui.Destroy(), dimGui := 0

    ; Reset all state variables
    global dimShown := false
    global toolbarVisible := false
    global haveFrame := false
    global frame := { x: 0, y: 0, w: 0, h: 0 }
    global polyPoints := []
    global activePolygons := []

    ; Release the lock
    DllCall("LockWindowUpdate", "UInt", 0)

    TearDownSnip("cancel")
}
Snip_MouseMove(*) {
    global snipActive, frameGui, dimGui, dragStart, selectMode, polyPoints, drawing, toolbarDragging, toolbarGui,
        toolbarPos, toolbarVisible
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

    if (selectMode = "rectangle" && GetKeyState("LButton", "P")) {
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

Snip_LButtonDown(wParam, lParam, msg, hwnd) {
    global snipActive, dragStart, selectMode, polyPoints
    global toolbarDragging, toolbarGui, inToolbarArea, toolbarVisible
    global lastClickTime, clickThreshold, dimGui, polyGui

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

    ; Get the mouse coordinates from lParam
    sx := lParam & 0xFFFF          ; Low word = x coordinate
    sy := (lParam >> 16) & 0xFFFF  ; High word = y coordinate

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
        return 0
    }

    if (selectMode = "rectangle") {
        dragStart.x := sx, dragStart.y := sy
    }
    else if (selectMode = "polygon") {
        ; Add new point to polygon
        polyPoints.Push({ x: sx, y: sy })

        ; Create a small dot to mark the vertex
        local dotGui := Gui("+AlwaysOnTop -Caption +ToolWindow")
        dotGui.BackColor := "Red"
        dotGui.Show("x" (sx - 3) " y" (sy - 3) " w6 h6")
        polyGui.Push(dotGui)

        ; If we have at least two points, draw the line segment
        if (polyPoints.Length > 1) {
            lastIndex := polyPoints.Length
            p1 := polyPoints[lastIndex - 1]
            p2 := polyPoints[lastIndex]
            DrawColoredLine(p1.x, p1.y, p2.x, p2.y)
        }

        ; Check if polygon can be closed (3+ points and click near starting point)
        if (polyPoints.Length >= 3) {
            startPoint := polyPoints[1]
            if (Abs(sx - startPoint.x) < 10 && Abs(sy - startPoint.y) < 10) {
                ; Close the polygon
                DrawColoredLine(sx, sy, startPoint.x, startPoint.y)
                FinishCurrentPolygon()
            }
        }
    }

    return 0
}

; If needed, you may also want a helper function to compute keyboard flags from wParam
GetKeyFlags(wParam) {
    flags := {}
    flags.ctrl := (wParam & 0x8) > 0
    flags.shift := (wParam & 0x4) > 0
    flags.alt := (wParam & 0x20) > 0
    flags.lwin := (wParam & 0x40) > 0
    flags.rwin := (wParam & 0x80) > 0
    return flags
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
        frame := { x: Min(ex, dragStart.x), y: Min(ey, dragStart.y), w: Abs(ex - dragStart.x), h: Abs(ey - dragStart.y) }
        if (frame.w < 4 || frame.h < 4) {
            return 0  ; Don't cancel snip on small/accidental clicks
        }
        haveFrame := true, dimShown := true
        TearDownSnip("keep")
    }
    return 0
}

; Function to finish the current polygon
FinishCurrentPolygon() {
    global polyPoints, activePolygons, dimGui, snipActive, polyRenderingComplete

    ; Set flag to indicate rendering in progress
    polyRenderingComplete := false

    ; If we have valid polygon, add it to collection
    if (polyPoints.Length >= 3) {
        ; Clone to avoid reference issues
        activePolygons.Push(polyPoints.Clone())

        ; Reset for next polygon
        polyPoints := []

        ; Redraw existing polygons with GDI+
        RedrawExistingPolygons()
    } else {
        ; Even if we don't add a new polygon, set rendering as complete
        polyRenderingComplete := true
    }
}

; Function to finish all polygons and create final mask
; 2. FinishAllPolygons function - only create the polygon holes when actually finished
FinishAllPolygons() {
    global activePolygons, polyPoints, haveFrame, dimShown, snipActive

    ; If currently drawing a polygon with enough points, add it
    if (polyPoints.Length >= 3) {
        activePolygons.Push(polyPoints.Clone())
        polyPoints := []
    }

    ; Check if we have any polygons
    if (activePolygons.Length = 0)
        return

    ; Only create the polygon holes when user presses Space to finalize
    CreateMultiPolygonRegion()

    ; Set flags and finish
    haveFrame := true
    dimShown := true

    ; Now properly exit selection mode
    TearDownSnip("keep")
}

; Function to remove the last added polygon
RemoveLastPolygon(*) {
    global activePolygons, polyGui

    if (activePolygons.Length = 0)
        return

    ; Lock window updates completely
    DllCall("LockWindowUpdate", "UInt", DllCall("GetDesktopWindow", "Ptr"))

    ; Remove last polygon from collection
    activePolygons.Pop()

    ; Clear current polygon visuals
    ClearPolyGuis()

    ; Redraw remaining polygons
    RedrawExistingPolygons()

    ; Release the lock
    DllCall("LockWindowUpdate", "UInt", 0)
}
; Initialize canvas for polygon drawing with double buffering
InitPolygonCanvas() {
    global canvasGui, memHDC, memBitmap, oldBitmap

    ; Create a transparent canvas GUI
    canvasGui := Gui("+AlwaysOnTop -Caption +ToolWindow +Owner" . dimGui.Hwnd)
    canvasGui.BackColor := "Black"  ; Black for transparency
    canvasGui.Show("x0 y0 w" A_ScreenWidth " h" A_ScreenHeight " Hide")
    WinSetTransColor("Black 255", canvasGui.Hwnd)
    canvasGui.Show("NoActivate")

    ; Initialize double-buffering resources
    hdc := DllCall("GetDC", "Ptr", canvasGui.Hwnd)
    memHDC := DllCall("CreateCompatibleDC", "Ptr", hdc)
    memBitmap := DllCall("CreateCompatibleBitmap", "Ptr", hdc, "Int", A_ScreenWidth, "Int", A_ScreenHeight)
    oldBitmap := DllCall("SelectObject", "Ptr", memHDC, "Ptr", memBitmap)
    DllCall("ReleaseDC", "Ptr", canvasGui.Hwnd, "Ptr", hdc)

    ; Clear the buffer initially
    rect := Buffer(16)
    NumPut("Int", 0, rect, 0)
    NumPut("Int", 0, rect, 4)
    NumPut("Int", A_ScreenWidth, rect, 8)
    NumPut("Int", A_ScreenHeight, rect, 12)
    hBrush := DllCall("CreateSolidBrush", "UInt", 0)  ; Black brush
    DllCall("FillRect", "Ptr", memHDC, "Ptr", rect, "Ptr", hBrush)
    DllCall("DeleteObject", "Ptr", hBrush)

    ; Store in polyGui array
    global polyGui := [canvasGui]

    return true
}

; Free double-buffer resources
ShutdownPolygonCanvas() {
    global canvasGui, memHDC, memBitmap, oldBitmap

    ; Clean up double-buffering resources
    if (memHDC) {
        DllCall("SelectObject", "Ptr", memHDC, "Ptr", oldBitmap)
        DllCall("DeleteObject", "Ptr", memBitmap)
        DllCall("DeleteDC", "Ptr", memHDC)
        memHDC := 0
        memBitmap := 0
        oldBitmap := 0
    }

    ; Destroy canvas GUI
    if (canvasGui) {
        canvasGui.Destroy()
        canvasGui := 0
    }
}

; Completely redesigned RedrawExistingPolygons using double buffering
RedrawExistingPolygons() {
    global activePolygons, polyGui, polyRenderingComplete, canvasGui
    global memHDC, memBitmap, oldBitmap

    ; Set flag to indicate rendering in progress
    polyRenderingComplete := false

    ; Clear existing polygon GUIs except canvas
    ClearPolyGuis()

    ; Make sure canvas exists
    if (!canvasGui) {
        InitPolygonCanvas()
    } else {
        ; Ensure it's visible
        canvasGui.Show("NA")
    }

    ; Clear memory DC with transparent black
    width := A_ScreenWidth
    height := A_ScreenHeight
    rect := Buffer(16)
    NumPut("Int", 0, rect, 0)
    NumPut("Int", 0, rect, 4)
    NumPut("Int", width, rect, 8)
    NumPut("Int", height, rect, 12)
    hBrush := DllCall("CreateSolidBrush", "UInt", 0)  ; Black brush
    DllCall("FillRect", "Ptr", memHDC, "Ptr", rect, "Ptr", hBrush)
    DllCall("DeleteObject", "Ptr", hBrush)

    ; Create green pen (pure green)
    hPen := DllCall("CreatePen", "Int", 0, "Int", 3, "UInt", 0x00FF00)  ; RGB - bright green, width 3
    oldPen := DllCall("SelectObject", "Ptr", memHDC, "Ptr", hPen)

    ; Set background mode to transparent
    oldBkMode := DllCall("SetBkMode", "Ptr", memHDC, "Int", 1)  ; TRANSPARENT

    ; Create green brush for dots
    hBrush := DllCall("CreateSolidBrush", "UInt", 0x00FF00)  ; RGB - bright green
    oldBrush := DllCall("SelectObject", "Ptr", memHDC, "Ptr", hBrush)

    ; Draw all completed polygons to memory DC
    for _, polygon in activePolygons {
        if (polygon.Length < 3)
            continue

        ; Draw polygon outline
        DllCall("MoveToEx", "Ptr", memHDC, "Int", polygon[1].x, "Int", polygon[1].y, "Ptr", 0)

        loop polygon.Length {
            DllCall("LineTo", "Ptr", memHDC, "Int", polygon[A_Index].x, "Int", polygon[A_Index].y)
        }

        ; Close polygon
        DllCall("LineTo", "Ptr", memHDC, "Int", polygon[1].x, "Int", polygon[1].y)

        ; Draw vertices (dots)
        loop polygon.Length {
            x := polygon[A_Index].x - 4
            y := polygon[A_Index].y - 4
            DllCall("Ellipse", "Ptr", memHDC, "Int", x, "Int", y, "Int", x + 8, "Int", y + 8)
        }
    }

    ; Restore original GDI objects in memory DC
    DllCall("SelectObject", "Ptr", memHDC, "Ptr", oldPen)
    DllCall("SelectObject", "Ptr", memHDC, "Ptr", oldBrush)
    DllCall("DeleteObject", "Ptr", hPen)
    DllCall("DeleteObject", "Ptr", hBrush)

    ; Now copy the memory DC to the window DC in one operation
    hdc := DllCall("GetDC", "Ptr", canvasGui.Hwnd)
    DllCall("BitBlt", "Ptr", hdc, "Int", 0, "Int", 0, "Int", width, "Int", height,
        "Ptr", memHDC, "Int", 0, "Int", 0, "UInt", 0x00CC0020)  ; SRCCOPY
    DllCall("ReleaseDC", "Ptr", canvasGui.Hwnd, "Ptr", hdc)

    ; Set flag to indicate rendering is complete
    polyRenderingComplete := true
}
; Helper function to update the window with alpha blending (AHK v2 version)
UpdateLayeredWindow2(hwnd) {
    ; Get window dimensions
    rect := Buffer(16, 0)
    DllCall("GetClientRect", "Ptr", hwnd, "Ptr", rect)
    width := NumGet(rect, 8, "Int")
    height := NumGet(rect, 12, "Int")

    ; Create device contexts and bitmaps
    screenDC := DllCall("GetDC", "Ptr", 0)
    memDC := DllCall("CreateCompatibleDC", "Ptr", screenDC)
    hBitmap := DllCall("CreateCompatibleBitmap", "Ptr", screenDC, "Int", width, "Int", height)
    oldBitmap := DllCall("SelectObject", "Ptr", memDC, "Ptr", hBitmap)

    ; Get window DC and BitBlt content
    windowDC := DllCall("GetDC", "Ptr", hwnd)
    DllCall("BitBlt", "Ptr", memDC, "Int", 0, "Int", 0, "Int", width, "Int", height,
        "Ptr", windowDC, "Int", 0, "Int", 0, "UInt", 0x00CC0020)  ; SRCCOPY

    ; Create blend function
    blendFunc := Buffer(4, 0)
    NumPut("UChar", 0, blendFunc, 0)      ; AC_SRC_OVER
    NumPut("UChar", 0, blendFunc, 1)      ; Reserved
    NumPut("UChar", 255, blendFunc, 2)    ; Alpha value
    NumPut("UChar", 1, blendFunc, 3)      ; AC_SRC_ALPHA

    ; Create points for origin
    ptSrc := Buffer(8, 0)
    ptSize := Buffer(8, 0)
    NumPut("UInt", width, ptSize, 0)
    NumPut("UInt", height, ptSize, 4)

    ; Update window
    DllCall("UpdateLayeredWindow2", "Ptr", hwnd, "Ptr", screenDC, "Ptr", 0,
        "Ptr", ptSize, "Ptr", memDC, "Ptr", ptSrc, "UInt", 0,
        "Ptr", blendFunc, "UInt", 0x00000002)  ; ULW_ALPHA

    ; Clean up
    DllCall("SelectObject", "Ptr", memDC, "Ptr", oldBitmap)
    DllCall("DeleteObject", "Ptr", hBitmap)
    DllCall("DeleteDC", "Ptr", memDC)
    DllCall("ReleaseDC", "Ptr", 0, "Ptr", screenDC)
    DllCall("ReleaseDC", "Ptr", hwnd, "Ptr", windowDC)
}
; Helper function to prepare a line GUI without showing it
PrepareLineGui(x1, y1, x2, y2, color := "Red") {
    ; Calculate line properties
    w := Abs(x2 - x1) + 1
    h := Abs(y2 - y1) + 1
    x := Min(x1, x2)
    y := Min(y1, y2)

    ; Skip if too small
    if (w < 1 || h < 1)
        return 0

    ; Create line GUI but don't show it yet
    lineGui := Gui("+AlwaysOnTop -Caption +ToolWindow")
    lineGui.BackColor := color
    lineGui.Options := { x: x, y: y, w: w, h: h }

    ; Create the line shape if not just a point
    if (x1 != x2 || y1 != y2) {
        ; Calculate angle and length
        angle := ATan2(y2 - y1, x2 - x1)

        ; Create points for line region
        thickness := 2
        halfThick := thickness / 2

        points := Buffer(8 * 4)

        ; Calculate perpendicular offset
        dx := Sin(angle) * halfThick
        dy := -Cos(angle) * halfThick

        ; Calculate all points at once
        NumPut("Int", Round(x1 - x + dx), points, 0)
        NumPut("Int", Round(y1 - y + dy), points, 4)
        NumPut("Int", Round(x2 - x + dx), points, 8)
        NumPut("Int", Round(y2 - y + dy), points, 12)
        NumPut("Int", Round(x2 - x - dx), points, 16)
        NumPut("Int", Round(y2 - y - dy), points, 20)
        NumPut("Int", Round(x1 - x - dx), points, 24)
        NumPut("Int", Round(y1 - y - dy), points, 28)

        ; Create polygon region
        hRgn := DllCall("CreatePolygonRgn", "Ptr", points, "Int", 4, "Int", 1, "Ptr")

        ; Store the region in the GUI object for later application
        lineGui.Region := hRgn
    }

    return lineGui
}
; Colored line drawing function
DrawColoredLine(x1, y1, x2, y2, color := "Red") {
    global polyGui

    ; Skip drawing if less than 2 pixels distance (optimization)
    if (Abs(x2 - x1) < 2 && Abs(y2 - y1) < 2)
        return

    ; Calculate line properties
    w := Abs(x2 - x1) + 1
    h := Abs(y2 - y1) + 1
    x := Min(x1, x2)
    y := Min(y1, y2)

    ; Create line GUI with transparent attributes
    lineGui := Gui("+AlwaysOnTop -Caption +ToolWindow")
    lineGui.BackColor := color

    ; Show first to get a handle
    lineGui.Show("x" x " y" y " w" w " h" h " NA")

    ; Create the line shape
    if (x1 != x2 || y1 != y2) {
        angle := ATan2(y2 - y1, x2 - x1)
        thickness := 2
        halfThick := thickness / 2

        points := Buffer(8 * 4)

        dx := Sin(angle) * halfThick
        dy := -Cos(angle) * halfThick

        NumPut("Int", Round(x1 - x + dx), points, 0)
        NumPut("Int", Round(y1 - y + dy), points, 4)
        NumPut("Int", Round(x2 - x + dx), points, 8)
        NumPut("Int", Round(y2 - y + dy), points, 12)
        NumPut("Int", Round(x2 - x - dx), points, 16)
        NumPut("Int", Round(y2 - y - dy), points, 20)
        NumPut("Int", Round(x1 - x - dx), points, 24)
        NumPut("Int", Round(y1 - y - dy), points, 28)

        hRgn := DllCall("CreatePolygonRgn", "Ptr", points, "Int", 4, "Int", 1, "Ptr")
        DllCall("SetWindowRgn", "Ptr", lineGui.Hwnd, "Ptr", hRgn, "Int", 1)
    }

    polyGui.Push(lineGui)
}
; Create the multi-polygon region for the final selection
CreateMultiPolygonRegion() {
    global dimGui, activePolygons, frame

    if (!dimGui || activePolygons.Length = 0) {
        return
    }

    ; Lock window updates completely to prevent any visual updates until ready
    DllCall("LockWindowUpdate", "UInt", DllCall("GetDesktopWindow", "Ptr"))

    ; Calculate combined bounding box for frame
    minX := A_ScreenWidth, maxX := 0
    minY := A_ScreenHeight, maxY := 0

    ; Count total points and prepare arrays
    totalPoints := 0
    validPolygons := 0
    pointCounts := []

    ; First pass: count points and validate polygons
    for i, polygon in activePolygons {
        if (polygon.Length >= 3) {
            pointCounts.Push(polygon.Length)
            totalPoints += polygon.Length
            validPolygons++

            ; Update bounding box
            for j, point in polygon {
                minX := Min(minX, point.x)
                maxX := Max(maxX, point.x)
                minY := Min(minY, point.y)
                maxY := Max(maxY, point.y)
            }
        }
    }

    if (validPolygons = 0 || totalPoints = 0) {
        ; Re-enable drawing before exiting
        DllCall("LockWindowUpdate", "UInt", 0)
        return
    }

    ; Create all necessary objects in a more efficient batch
    points := Buffer(8 * totalPoints)
    counts := Buffer(4 * validPolygons)
    pointIndex := 0
    countIndex := 0

    ; Fill buffers in one pass
    for i, polygon in activePolygons {
        if (polygon.Length >= 3) {
            NumPut("Int", polygon.Length, counts, countIndex * 4)
            countIndex++

            for j, point in polygon {
                NumPut("Int", point.x, points, pointIndex * 8)
                NumPut("Int", point.y, points, pointIndex * 8 + 4)
                pointIndex++
            }
        }
    }

    ; Create regions and apply them in a single batch
    polyRgn := DllCall("CreatePolyPolygonRgn", "Ptr", points, "Ptr", counts, "Int", validPolygons, "Int", 1, "Ptr")
    if (!polyRgn) {
        ; Re-enable drawing before exiting
        DllCall("LockWindowUpdate", "UInt", 0)
        return
    }

    fullRgn := DllCall("CreateRectRgn", "Int", 0, "Int", 0, "Int", A_ScreenWidth, "Int", A_ScreenHeight, "Ptr")
    if (!fullRgn) {
        DllCall("DeleteObject", "Ptr", polyRgn)
        ; Re-enable drawing before exiting
        DllCall("LockWindowUpdate", "UInt", 0)
        return
    }

    finalRgn := DllCall("CreateRectRgn", "Int", 0, "Int", 0, "Int", 0, "Int", 0, "Ptr")
    if (!finalRgn) {
        DllCall("DeleteObject", "Ptr", fullRgn)
        DllCall("DeleteObject", "Ptr", polyRgn)
        ; Re-enable drawing before exiting
        DllCall("LockWindowUpdate", "UInt", 0)
        return
    }

    ; Make all region operations in a single batch
    DllCall("CombineRgn", "Ptr", finalRgn, "Ptr", fullRgn, "Ptr", polyRgn, "Int", 4)

    ; Apply region and update frame
    DllCall("SetWindowRgn", "Ptr", dimGui.Hwnd, "Ptr", finalRgn, "Int", 0)  ; Using 0 to delay visual update

    ; Update the frame with the calculated bounding box
    frame := { x: minX, y: minY, w: maxX - minX, h: maxY - minY }

    ; Clean up resources
    DllCall("DeleteObject", "Ptr", fullRgn)
    DllCall("DeleteObject", "Ptr", polyRgn)

    ; Finally release the lock to allow window updates
    DllCall("LockWindowUpdate", "UInt", 0)
}
; Helper function to properly redraw a window
RedrawWindow(hwnd) {
    ; RDW flags
    RDW_INVALIDATE := 0x0001
    RDW_INTERNALPAINT := 0x0002
    RDW_ERASE := 0x0004
    RDW_FRAME := 0x0400
    RDW_ALLCHILDREN := 0x0080

    ; Combine flags for complete redraw
    flags := RDW_INVALIDATE | RDW_INTERNALPAINT | RDW_ERASE | RDW_FRAME | RDW_ALLCHILDREN

    ; Call the RedrawWindow API
    DllCall("RedrawWindow", "Ptr", hwnd, "Ptr", 0, "Ptr", 0, "UInt", flags)
}

ClearPolyGuis() {
    global polyGui, canvasGui

    ; If no GUIs to clear, exit early
    if (!IsObject(polyGui) || polyGui.Length < 1)
        return

    ; Keep the canvas GUI, remove others
    for i, gui in polyGui {
        try {
            if (gui != canvasGui && IsObject(gui) && gui.HasProp("Hwnd") && gui.Hwnd)
                gui.Destroy()
        } catch {
            ; Skip any GUI that causes an error
        }
    }

    ; Reset the array but keep canvas if it exists
    if (canvasGui)
        polyGui := [canvasGui]
    else
        polyGui := []
}

TearDownSnip(mode) {
    global snipActive, dimGui, frameGui, selectMode, polyGui, toolbarGui, toolbarVisible
    global activePolygons, dimShown

    snipActive := false

    ; Unregister hotkeys properly by reference to the hotkey only
    try {
        Hotkey("Esc", "Off")
        Hotkey("1", "Off")
        Hotkey("2", "Off")
        Hotkey("3", "Off")
        Hotkey("Enter", "Off")
        Hotkey("Space", "Off")
        Hotkey("Backspace", "Off")
    } catch {
        ; Ignore errors if hotkeys already off
    }

    ; Release system resources
    DllCall("ReleaseCapture")
    DllCall("SystemParametersInfo", "UInt", 0x57, "UInt", 0, "UInt", 0, "UInt", 0x1)

    ; Clean up polygon guides
    ClearPolyGuis()

    ; Hide and destroy toolbar
    toolbarVisible := false
    if (toolbarGui) {
        try {
            toolbarGui.Destroy()
            toolbarGui := 0
        } catch {
            ; Ignore errors if GUI already destroyed
        }
    }

    ; Destroy frame GUI
    if (frameGui) {
        try {
            frameGui.Destroy()
            frameGui := 0
        } catch {
            ; Ignore errors if GUI already destroyed
        }
    }

    if (mode = "cancel") {
        ; Destroy dimmer GUI on cancel
        if (dimGui) {
            try {
                dimGui.Destroy()
                dimGui := 0
            } catch {
                ; Ignore errors if GUI already destroyed
            }
        }
        dimShown := false
    } else {
        ; Update dimmer to final state
        ShowDimmer(DIM_FINAL)
    }
    ShutdownPolygonCanvas()

}

; — Dimmer helpers —
ShowDimmer(alpha) {
    global dimGui, frame, selectMode, polyPoints, activePolygons

    ; Lock window updates at the beginning
    DllCall("LockWindowUpdate", "UInt", DllCall("GetDesktopWindow", "Ptr"))

    if !dimGui {
        dimGui := Gui("+AlwaysOnTop -Caption +ToolWindow")
        dimGui.BackColor := "Black"
        dimGui.Show("Maximize")
    }

    ; Batch all operations before releasing the lock
    WinSetTransparent(alpha, dimGui.Hwnd)

    if (selectMode = "polygon") {
        if (activePolygons.Length > 0) {
            ; If we have multiple polygons, show them all without redrawing
            UpdateMultiPolygonRegionNoRedraw()
        } else if (polyPoints.Length >= 3) {
            ; If we have a single polygon in progress
            UpdatePolygonRegionNoRedraw()
        } else {
            ; Default case - no hole
            UpdateDimHole(dimGui.Hwnd, 0, 0, 0, 0, false)  ; false = don't redraw yet
        }
    } else {
        ; Standard rectangle mode
        UpdateDimHole(dimGui.Hwnd, frame.x, frame.y, frame.w, frame.h, false)  ; false = don't redraw yet
    }

    ; Release the lock at the end
    DllCall("LockWindowUpdate", "UInt", 0)
}

DestroyDimmer() {
    global dimGui, dimShown
    if dimGui
        dimGui.Destroy(), dimGui := 0
    dimShown := false
}

UpdateDimHole(hwnd, x, y, w, h, redraw := true) {
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
        hole := DllCall("CreateRectRgn", "int", x, "int", y, "int", x + w, "int", y + h, "ptr")
        if (!hole) {
            ; Clean up full region
            DllCall("DeleteObject", "ptr", full)
            return  ; Skip if region creation failed
        }

        ; Combine regions to create hole
        DllCall("CombineRgn", "ptr", full, "ptr", full, "ptr", hole, "int", 4)  ; RGN_DIFF = 4

        ; Apply region to window if it still exists
        if (WinExist("ahk_id " hwnd))
            DllCall("SetWindowRgn", "ptr", hwnd, "ptr", full, "int", redraw ? 1 : 0)  ; Only redraw if requested
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
UpdatePolygonRegion() {
    global dimGui, polyPoints

    if (!dimGui || !polyPoints.Length)
        return

    ; Create polygon region points buffer
    pointCount := polyPoints.Length
    points := Buffer(8 * pointCount)  ; 8 bytes per point (4 for x, 4 for y)

    ; Fill points buffer
    for i, point in polyPoints {
        NumPut("Int", point.x, points, (i - 1) * 8)
        NumPut("Int", point.y, points, (i - 1) * 8 + 4)
    }

    ; Create polygon region
    polyRgn := DllCall("CreatePolygonRgn", "Ptr", points, "Int", pointCount, "Int", 1, "Ptr")

    ; Create full screen region
    fullRgn := DllCall("CreateRectRgn", "Int", 0, "Int", 0, "Int", A_ScreenWidth, "Int", A_ScreenHeight, "Ptr")

    ; Combine regions to create hole
    finalRgn := DllCall("CreateRectRgn", "Int", 0, "Int", 0, "Int", 0, "Int", 0, "Ptr")
    DllCall("CombineRgn", "Ptr", finalRgn, "Ptr", fullRgn, "Ptr", polyRgn, "Int", 4)  ; RGN_DIFF = 4

    ; Apply region to dimmer window
    DllCall("SetWindowRgn", "Ptr", dimGui.Hwnd, "Ptr", finalRgn, "Int", 1)

    ; Clean up
    DllCall("DeleteObject", "Ptr", polyRgn)
    DllCall("DeleteObject", "Ptr", fullRgn)
}
UpdatePolygonRegionNoRedraw() {
    global dimGui, polyPoints

    if (!dimGui || !polyPoints.Length)
        return

    ; Create polygon region points buffer
    pointCount := polyPoints.Length
    points := Buffer(8 * pointCount)  ; 8 bytes per point (4 for x, 4 for y)

    ; Fill points buffer
    for i, point in polyPoints {
        NumPut("Int", point.x, points, (i - 1) * 8)
        NumPut("Int", point.y, points, (i - 1) * 8 + 4)
    }

    ; Create polygon region
    polyRgn := DllCall("CreatePolygonRgn", "Ptr", points, "Int", pointCount, "Int", 1, "Ptr")

    ; Create full screen region
    fullRgn := DllCall("CreateRectRgn", "Int", 0, "Int", 0, "Int", A_ScreenWidth, "Int", A_ScreenHeight, "Ptr")

    ; Combine regions to create hole
    finalRgn := DllCall("CreateRectRgn", "Int", 0, "Int", 0, "Int", 0, "Int", 0, "Ptr")
    DllCall("CombineRgn", "Ptr", finalRgn, "Ptr", fullRgn, "Ptr", polyRgn, "Int", 4)  ; RGN_DIFF = 4

    ; Apply region to dimmer window - don't force redraw (0 instead of 1)
    DllCall("SetWindowRgn", "Ptr", dimGui.Hwnd, "Ptr", finalRgn, "Int", 0)

    ; Clean up
    DllCall("DeleteObject", "Ptr", polyRgn)
    DllCall("DeleteObject", "Ptr", fullRgn)
}
UpdateMultiPolygonRegionNoRedraw() {
    global dimGui, activePolygons, frame

    if (!dimGui || activePolygons.Length = 0) {
        return
    }

    ; Count total points and prepare arrays
    totalPoints := 0
    validPolygons := 0
    pointCounts := []

    ; First pass: count points and validate polygons
    for i, polygon in activePolygons {
        if (polygon.Length >= 3) {
            pointCounts.Push(polygon.Length)
            totalPoints += polygon.Length
            validPolygons++

            ; Update bounding box (keep track for region)
            for j, point in polygon {
                minX := (j = 1 || point.x < minX) ? point.x : minX
                maxX := (j = 1 || point.x > maxX) ? point.x : maxX
                minY := (j = 1 || point.y < minY) ? point.y : minY
                maxY := (j = 1 || point.y > maxY) ? point.y : maxY
            }
        }
    }

    if (validPolygons = 0 || totalPoints = 0) {
        return
    }

    ; Create all necessary objects in a more efficient batch
    points := Buffer(8 * totalPoints)
    counts := Buffer(4 * validPolygons)
    pointIndex := 0
    countIndex := 0

    ; Fill buffers in one pass
    for i, polygon in activePolygons {
        if (polygon.Length >= 3) {
            NumPut("Int", polygon.Length, counts, countIndex * 4)
            countIndex++

            for j, point in polygon {
                NumPut("Int", point.x, points, pointIndex * 8)
                NumPut("Int", point.y, points, pointIndex * 8 + 4)
                pointIndex++
            }
        }
    }

    ; Create regions and apply them in a single batch
    polyRgn := DllCall("CreatePolyPolygonRgn", "Ptr", points, "Ptr", counts, "Int", validPolygons, "Int", 1, "Ptr")
    if (!polyRgn) {
        return
    }

    fullRgn := DllCall("CreateRectRgn", "Int", 0, "Int", 0, "Int", A_ScreenWidth, "Int", A_ScreenHeight, "Ptr")
    if (!fullRgn) {
        DllCall("DeleteObject", "Ptr", polyRgn)
        return
    }

    finalRgn := DllCall("CreateRectRgn", "Int", 0, "Int", 0, "Int", 0, "Int", 0, "Ptr")
    if (!finalRgn) {
        DllCall("DeleteObject", "Ptr", fullRgn)
        DllCall("DeleteObject", "Ptr", polyRgn)
        return
    }

    ; Make all region operations in a single batch
    DllCall("CombineRgn", "Ptr", finalRgn, "Ptr", fullRgn, "Ptr", polyRgn, "Int", 4)

    ; Apply region without redrawing (0 instead of 1)
    DllCall("SetWindowRgn", "Ptr", dimGui.Hwnd, "Ptr", finalRgn, "Int", 0)

    ; Update the frame with the calculated bounding box
    frame := { x: minX, y: minY, w: maxX - minX, h: maxY - minY }

    ; Clean up resources
    DllCall("DeleteObject", "Ptr", fullRgn)
    DllCall("DeleteObject", "Ptr", polyRgn)
}
