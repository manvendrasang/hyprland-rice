---- MY PROGRAMS ----
---------------------

-- Set programs that you use
--
-- Every one of these must resolve to something HyprX actually installs, or the
-- keybind opens nothing and nothing reports why. That class of bug shipped
-- seven times over (see database/binary-providers.conf), so each of these is
-- declared there and checked by `hyprx doctor --only manifest`.
--
-- To use a different file manager or browser, edit this line AND add the
-- package to packages.list - otherwise the next install will not provide it.
return {
	terminal = "kitty",
	fileManager = "thunar",      -- was an uninstalled file manager: the bind opened nothing
	launcher = "rofi -show drun -show-icons",
	browser = "brave",
	runner = "rofi -show run",
}

-------------------
