------------------------------------------------------------
-- Autostart
------------------------------------------------------------

local apps = {
    "waybar",
    "swaync",
    "hyprpaper",
    "nm-applet",
    "blueman-applet",
    "wl-paste --type text --watch cliphist store",
    "wl-paste --type image --watch cliphist store",
}

for _, app in ipairs(apps) do
    hl.exec_once(app)
end