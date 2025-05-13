; Loads all user‑configurable hotkeys from config.ini.
;if !FileExist("config.ini") {
 ;   IniWrite("^+R", "config.ini", "Shortcuts", "HOTKEY_TOGGLE_OVERLAY")
  ;  IniWrite("^+B", "config.ini", "Shortcuts", "HOTKEY_TOGGLE_CLICKBLOCK")
   ; IniWrite("^+D", "config.ini", "Shortcuts", "HOTKEY_TOGGLE_BLUR")
   ; IniWrite("^+F", "config.ini", "Shortcuts", "HOTKEY_TOGGLE_FOCUS")
    ;IniWrite("+Esc", "config.ini", "Shortcuts", "HOTKEY_SELECT_FOCUS")
;}
	
global HOTKEY_TOGGLE_OVERLAY   := "^+R"
global HOTKEY_TOGGLE_CLICKBLOCK:= "^+B"
global HOTKEY_TOGGLE_BLUR      := "^+D"
global HOTKEY_TOGGLE_FOCUS     := "^+F"
global HOTKEY_SELECT_FOCUS     := "+Esc"
