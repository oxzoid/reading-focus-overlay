#Requires AutoHotkey v2.0
#SingleInstance Force
#Include Gdip_All.ahk

global blurGui := 0
global blurOn := false
global pToken := Gdip_Startup()
global blurRestoreNeeded := false

ToggleBlur(*) {
    global blurOn
    if blurOn
        HideBlur()
    else
        ShowBlur()
}

ShowBlur() {
    global blurGui, blurOn

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
    blurred := SimulateBlur(pBitmap, w, h)

    ; Create GUI to show it
    blurGui := Gui("+AlwaysOnTop -Caption +ToolWindow", "BlurOverlay")
    blurGui.BackColor := "Black"
    hwnd := blurGui.Hwnd

    hbm := CreateDIBSection(w, h)
    hdc := CreateCompatibleDC()
    obm := SelectObject(hdc, hbm)
    g := Gdip_GraphicsFromHDC(hdc)
    Gdip_DrawImage(g, blurred, 0, 0, w, h)
    Gdip_DeleteGraphics(g)
    Gdip_DisposeImage(pBitmap)
    Gdip_DisposeImage(blurred)

    blurGui.Show("x" x " y" y " w" w " h" h " NA")
    UpdateLayeredWindow(hwnd, hdc, x, y, w, h)
    SelectObject(hdc, obm), DeleteDC(hdc), DeleteObject(hbm)
    DllCall("DeleteObject", "ptr", hBmp)
    DllCall("DeleteDC", "ptr", hMemDC)

    blurOn := true
}

HideBlur() {
    global blurGui, blurOn
    try blurGui.Destroy()
    blurGui := 0
    blurOn := false
}

; Simulated blur (cheap fallback)
SimulateBlur(pBitmap, w, h) {
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
    return final
}
EnsureBlurVisible(*) {
    global blurGui, blurOn

    static lastCheckTime := 0
    currentTime := A_TickCount
    if (currentTime - lastCheckTime < 1000)  ; Check max once per second
        return
    lastCheckTime := currentTime
    ; Only proceed if blur should be on
    if (blurOn) {
        ; Check if the GUI still exists
        if (IsObject(blurGui) && blurGui.HasProp("Hwnd") && blurGui.Hwnd) {
            ; Check if window actually exists in Windows and is visible
            if (!WinExist("ahk_id " . blurGui.Hwnd) || !DllCall("IsWindowVisible", "Ptr", blurGui.Hwnd)) {
                ; Window doesn't exist or isn't visible - recreate
                try blurGui.Destroy()  ; Clean up if needed
                catch {
                }  ; Ignore errors

                blurOn := false  ; Reset state
                ShowBlur()       ; Recreate
                return
            }

            ; Force its visibility and z-order
            blurGui.Show("NA")  ; Show without activating
            WinSetAlwaysOnTop(true, "ahk_id " . blurGui.Hwnd)
        } else {
            ; GUI reference invalid - recreate it
            blurOn := false  ; Reset state
            ShowBlur()       ; Recreate
        }
    }
}

; Set timer to periodically check blur visibility
SetTimer EnsureBlurVisible, 600

; Add this hotkey to manually fix blur when needed
Hotkey("^+b", EnsureBlurVisible)  ; Ctrl+Shift+B to manually fix

; Hotkey
Hotkey("^+d", ToggleBlur)

; Cleanup
OnExit((*) => (blurOn && HideBlur()))