#Requires AutoHotkey v2.0

#SingleInstance Force
#Include Gdip_All.ahk

; -- GLOBALS --
global blurActive := false
global blurWin := 0
global pToken := Gdip_Startup()

; -- HOTKEYS --
; Make Ctrl+Shift+D toggle the taskbar blur
Hotkey "^+d", ToggleTaskbarBlur

; -- FUNCTIONS --
ToggleTaskbarBlur(*) {
    global blurActive

    if (blurActive)
        HideTaskbarBlur()
    else
        ShowTaskbarBlur()
}

ShowTaskbarBlur() {
    global blurActive, blurWin

    ; Get taskbar position
    x := y := w := h := 0
    WinGetPos(&x, &y, &w, &h, "ahk_class Shell_TrayWnd")

    ; Capture screen under taskbar
    hDC := DllCall("GetDC", "ptr", 0, "ptr")
    hMemDC := DllCall("CreateCompatibleDC", "ptr")
    hBmp := DllCall("CreateCompatibleBitmap", "ptr", hDC, "int", w, "int", h, "ptr")
    obmp := DllCall("SelectObject", "ptr", hMemDC, "ptr", hBmp, "ptr")
    DllCall("BitBlt", "ptr", hMemDC, "int", 0, "int", 0, "int", w, "int", h,
        "ptr", hDC, "int", x, "int", y, "uint", 0x00CC0020)
    DllCall("ReleaseDC", "ptr", 0, "ptr", hDC)

    ; Create bitmap
    pBitmap := Gdip_CreateBitmapFromHBITMAP(hBmp)

    ; Simulated blur via repeated scaled draw
    scaled := Gdip_CreateBitmap(w // 4, h // 4)
    g := Gdip_GraphicsFromImage(scaled)
    Gdip_SetInterpolationMode(g, 7)  ; HighQualityBicubic
    Gdip_DrawImage(g, pBitmap, 0, 0, w // 4, h // 4, 0, 0, w, h)
    Gdip_DeleteGraphics(g)

    final := Gdip_CreateBitmap(w, h)
    g2 := Gdip_GraphicsFromImage(final)
    Gdip_SetInterpolationMode(g2, 7)
    Gdip_DrawImage(g2, scaled, 0, 0, w, h, 0, 0, w // 4, h // 4)
    Gdip_DeleteGraphics(g2)
    Gdip_DisposeImage(scaled)

    ; Create GUI to show it - with special attributes
    blur := Gui("AlwaysOnTop -Caption +ToolWindow", "TASKBAR_BLUR_WINDOW")
    blur.BackColor := "Black"
    hwnd := blur.Hwnd

    ; Store for later use
    blurWin := hwnd

    ; Create layered window
    hbm := CreateDIBSection(w, h)
    hdc := CreateCompatibleDC()
    obm := SelectObject(hdc, hbm)
    g := Gdip_GraphicsFromHDC(hdc)
    Gdip_DrawImage(g, final, 0, 0, w, h)
    Gdip_DeleteGraphics(g)
    Gdip_DisposeImage(pBitmap)
    Gdip_DisposeImage(final)

    ; Show the window with special attributes
    blur.Show("x" x " y" y " w" w " h" h " NA")
    UpdateLayeredWindow(hwnd, hdc, x, y, w, h)
    SelectObject(hdc, obm), DeleteDC(hdc), DeleteObject(hbm)
    DllCall("DeleteObject", "ptr", hBmp)
    DllCall("DeleteDC", "ptr", hMemDC)

    ; Set special window styles to prevent it from being affected by focus frame
    style := WinGetExStyle("ahk_id " . hwnd)
    WinSetExStyle(style | 0x00000080, "ahk_id " . hwnd)  ; WS_EX_TOOLWINDOW

    ; Add a timer to check and restore if needed
    SetTimer EnsureBlurVisible, 500

    blurActive := true
}

HideTaskbarBlur() {
    global blurActive, blurWin

    ; Clear timer
    SetTimer EnsureBlurVisible, 0

    ; Destroy window by handle to ensure it's the right one
    if (blurWin && WinExist("ahk_id " . blurWin)) {
        WinClose("ahk_id " . blurWin)
    }

    blurWin := 0
    blurActive := false
}

EnsureBlurVisible(*) {
    global blurActive, blurWin

    ; If blur should be active but window doesn't exist
    if (blurActive && (!blurWin || !WinExist("ahk_id " . blurWin))) {
        ; Recreate blur
        blurWin := 0
        ShowTaskbarBlur()
    }

    ; If blur should be active but window might be invisible
    if (blurActive && blurWin && WinExist("ahk_id " . blurWin)) {
        ; Get current visibility state
        style := WinGetStyle("ahk_id " . blurWin)
        visible := (style & 0x10000000) != 0  ; WS_VISIBLE

        ; If not visible, make visible again
        if (!visible) {
            WinShow("ahk_id " . blurWin)
            WinActivate("ahk_id " . blurWin)
        }
    }
}

; -- CLEANUP --
ExitFunc(*) {
    global pToken, blurActive

    ; Clean up blur if active
    if (blurActive)
        HideTaskbarBlur()

    ; Shutdown GDI+
    Gdip_Shutdown(pToken)
}

OnExit(ExitFunc)