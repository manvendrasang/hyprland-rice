-- HyprX compositor config - entry point only.
--
-- Every area lives in its own file so a change is local: keybinds in
-- keybinds.lua, autostart in autostart.lua, look-and-feel in theme.lua, and
-- so on. Edit those, not this. Order matters - each require runs in turn,
-- exactly as these lines read top to bottom.

require("monitors")
require("apps")
require("autostart")
require("env")
require("general")
require("theme")
require("animations")
require("layouts")
require("keybinds")
require("rules")
