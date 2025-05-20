; shared_state.ahk
#Requires AutoHotkey v2.0

; Guard against multiple inclusions
if (IsSet(SHARED_STATE_LOADED))
    return
global taskbarWasHidden := false  ; Track if taskbar was hidden before focus mode
