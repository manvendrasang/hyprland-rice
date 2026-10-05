---- AUTOSTART ----
-------------------

-- See https://wiki.hypr.land/Configuring/Basics/Autostart/

-- Autostart necessary processes (like notifications daemons, status bars, etc.)
-- Or execute your favorite apps at launch like this:
--
hl.on("hyprland.start", function()
	hl.exec_cmd("pkill hyprpaper; hyprpaper")
	-- hyprpaper needs a moment to bring up its IPC socket before
	-- it can accept the wallpaper-set call. Without this delay,
	-- the restore call below can race hyprpaper's own startup and
	-- The restore call can be dropped if hyprpaper's IPC is not up yet,
	-- and waypaper --restore has nothing to restore on a fresh install.
	hl.exec_cmd("sleep 1 && ~/.local/share/hyprx/scripts/wallpaper-restore.sh")
	-- Loses an early-session race with the Wayland socket, silently.
	-- Retries until the surface is registered - see ensure-waybar.sh.
	hl.exec_cmd("~/.config/waybar/scripts/ensure-waybar.sh &")
	hl.exec_cmd("swaync")
	hl.exec_cmd("hypridle")
	hl.exec_cmd("wl-paste --type text --watch cliphist store")
	hl.exec_cmd("wl-paste --type image --watch cliphist store")
	-- nm-applet used to be launched here as well as the waybar `network` module,
	-- so the tray showed a second, redundant wifi indicator immediately after
	-- the notifications module. It was not even in packages.list, so nothing
	-- tracked it. The `network` module is the one that reports signal strength.
	-- music-daemon.sh used to be launched here. Its only consumer was the
	-- custom/music bar module, which was removed, so it was a daemon writing to
	-- nothing on every login. Nothing replaces it.
	hl.exec_cmd("~/.config/waybar/scripts/bluetooth-daemon.sh &")
	-- Re-runs wallust on any wallpaper change, whoever made it.
	hl.exec_cmd("~/.config/waybar/scripts/wallust-hyprpaper-sync.sh &")
end)
-------------------------------
