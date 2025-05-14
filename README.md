Minimalist Reading Overlay (AutoHotkey v2)
------------------------------------------

This tool helps you focus while reading or coding by adding:

- A pencil-style overlay cursor
- A click blocker to prevent distractions
- A blur overlay for the taskbar or screen
- A focus frame that dims everything except a selected area

How to Use:
-----------
Just run the .exe from release
----------------------------------
OR
----------------------------------
1. Requires AutoHotkey v2.0+
2. Run `main.ahk` (or compile it into an .exe using Ahk2Exe)
3. Use the default hotkeys:

- `Ctrl + Shift + R   = Toggle pencil overlay`
- `trl + Shift + B   = Toggle click block`
- `Ctrl + Shift + D   = Toggle taskbar dimming`
- `Ctrl + Shift + F   = Toggle focus frame`
- `Shift + Esc        = Re-select focus area`
- `Esc                = Leave Selection mode of focus area`

How to Customize Shortcuts:
---------------------------

Open `config.ahk` and change the hotkey values at the top.
There is no UI — just edit the file and restart the script.

Files:
------

- main.ahk
- config.ahk
- pencil_overlay.ahk
- distraction.ahk
- focus_frame.ahk
- Gdip_All.ahk
- pencil.png
- invisible-cursor.cur
- plus_cursor.cur

Enjoy.

> Note on Antivirus Flags
Some antivirus engines may flag the compiled .exe due to use of AutoHotkey, Windows API calls (like SetSystemCursor), or file embedding (FileInstall).
This is a known false positive with AHK scripts.

To be 100% sure, you’re welcome to inspect or run the script directly, or compile it yourself using Ahk2Exe. Whole reason i made it open source

![](<https://github.com/oxzoid/reading-focus-overlay/blob/ccb5584d5956c22cc779049e43a8d4b9c8c40223/6qTwpI3Q1Y.gif>)
