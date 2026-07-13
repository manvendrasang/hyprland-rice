------------------------------------------------------------
-- Global Variables
------------------------------------------------------------

require("config.variables")

------------------------------------------------------------
-- Core Configuration
------------------------------------------------------------

require("config.environment")
require("config.monitors")
require("config.input")

------------------------------------------------------------
-- Appearance
------------------------------------------------------------

require("appearance.appearance")
require("appearance.animations")
require("appearance.decorations")
require("appearance.workspaces")

------------------------------------------------------------
-- Rules
------------------------------------------------------------

require("rules.window_rules")
require("rules.workspace_rules")

------------------------------------------------------------
-- Keybindings
------------------------------------------------------------

require("bindings.applications")
require("bindings.windows")
require("bindings.workspaces")
require("bindings.media")
require("bindings.clipboard")
require("bindings.screenshots")
require("bindings.notifications")
require("bindings.mouse")
require("bindings.lockscreen")

------------------------------------------------------------
-- Startup
------------------------------------------------------------

require("startup.autostart")