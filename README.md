# Minimalist Reading Overlay (AutoHotkey v2)
UPDATE:no new releases after this,this will be ported to cpp for better performance and control this project is whole in itseld with ahk with only few minor things left which cannot be done easily in autohotkey and fulfils my need,see u in the new port whenever i start on it. can fix some stuff here and there if theres something majorly wrong.

This tool helps you focus while reading or coding by adding:
- A pencil-style overlay cursor
- A click blocker to prevent distractions
- A blur overlay for the taskbar or screen
- A focus frame that dims everything except selected areas

## How to Use

### Quick Start
Just run the .exe from release

### Manual Setup
1. Requires AutoHotkey v2.0+
2. Run `main.ahk` (or compile it into an .exe using Ahk2Exe)
3. Use the default hotkeys:
   - `Ctrl + Shift + R` = Toggle pencil overlay
   - `Ctrl + Shift + B` = Toggle click block
   - `Ctrl + Shift + D` = Toggle taskbar dimming
   - `Ctrl + Shift + F` = Toggle focus frame
   - `Shift + Esc` = Re-select focus area
   - `Esc` = Leave selection mode of focus area

## Focus Frame Features

### Rectangle Mode
- Quick selection of rectangular areas to focus on
- Simply click and drag to create a rectangular focus area
- Best for standard document layouts

### Polygon Mode
- Create custom-shaped focus areas with multiple points
- Perfect for irregular content layouts, multiple areas of interest, or complex UI elements
- **Multi-Polygon Workflow:**
  1. Click points to create the first polygon (at least 3 points)
  2. Press `Enter` to complete the current polygon
  3. Start clicking to create additional polygons as needed
  4. Press `Enter` after each polygon to add it to your selection
  5. Press `Space` when finished to finalize all polygons and exit selection mode
  6. Press `Backspace` to remove the last added polygon if needed

### Mode Selection
- Switch between modes using the toolbar or number keys
- Visual toolbar appears during selection with helpful buttons:
  - Rectangle mode (□): Select rectangular areas
  - Polygon mode (⬡): Select custom-shaped areas
  - Cancel (✕): Exit selection mode
- Active mode is highlighted in green

### Keyboard Shortcuts During Selection
- `1` = Switch to Rectangle mode
- `2` = Switch to Polygon mode
- `3` = Cancel selection
- `Enter` = Complete current polygon (in Polygon mode)
- `Space` = Finalize all polygons and exit selection (in Polygon mode)
- `Backspace` = Remove last added line in incomplete polygon (in Polygon mode)
- `Shift + Backspace` = Remove last added polygon (in Polygon mode)
- `Esc` = Cancel selection and exit

## How to Customize Shortcuts

Open `config.ahk` and change the hotkey values at the top.
There is no UI — just edit the file and restart the script.

## Files

- main.ahk
- config.ahk
- pencil_overlay.ahk
- distraction.ahk
- focus_frame.ahk
- Gdip_All.ahk
- pencil.png
- invisible-cursor.cur
- plus_cursor.cur

> Note on Antivirus Flags

Some antivirus engines may flag the compiled .exe due to use of AutoHotkey, Windows API calls (like SetSystemCursor), or file embedding (FileInstall).
This is a known false positive with AHK scripts.

To be 100% sure, you're welcome to inspect or run the script directly, or compile it yourself using Ahk2Exe. That's the whole reason I made it open source.

## Demonstrations

### Standard Focus Frame
![Focus Frame Demo](https://github.com/oxzoid/reading-focus-overlay/blob/ccb5584d5956c22cc779049e43a8d4b9c8c40223/6qTwpI3Q1Y.gif)

### Polygon Selection Mode
![Polygon Selection Demo](https://github.com/oxzoid/reading-focus-overlay/blob/ca896257ffe135c673048562e4a11c39264b3c9c/reading_focus_overlay_zY21JMZIbu.gif)
