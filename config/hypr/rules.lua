---- WINDOWS AND WORKSPACES ----
--------------------------------

-- See https://wiki.hypr.land/Configuring/Basics/Window-Rules/
-- and https://wiki.hypr.land/Configuring/Basics/Workspace-Rules/

-- Example window rules that are useful

local suppressMaximizeRule = hl.window_rule({
	-- Ignore maximize requests from all apps. You'll probably like this.
	name = "suppress-maximize-events",
	match = { class = ".*" },

	suppress_event = "maximize",
})
-- suppressMaximizeRule:set_enabled(false)

hl.window_rule({
	-- Fix some dragging issues with XWayland
	name = "fix-xwayland-drags",
	match = {
		class = "^$",
		title = "^$",
		xwayland = true,
		float = true,
		fullscreen = false,
		pin = false,
	},

	no_focus = true,
})

-- Layer rules also return a handle.
-- local overlayLayerRule = hl.layer_rule({
--     name  = "no-anim-overlay",
--     match = { namespace = "^my-overlay$" },
--     no_anim = true,
-- })
-- overlayLayerRule:set_enabled(false)

-- Hyprland-run windowrule
hl.window_rule({
	name = "move-hyprland-run",
	match = { class = "hyprland-run" },

	move = "20 monitor_h-120",
	float = true,
})

-- Waybar widget popups: small floating boxes, not tiled full-size
-- (Hyprland tiles new windows by default, which is why these looked
-- "full screen" before - these apps aren't actually large themselves)

hl.window_rule({
	name = "float-nm-connection-editor",
	match = { class = "^[Nn]m-connection-editor$" },

	float = true,
	size = "450 550",
	center = true,
	rounding = 12,
})

hl.window_rule({
	name = "float-pavucontrol",
	match = { class = "^org\\.pulseaudio\\.pavucontrol$" },

	float = true,
	size = "450 500",
	center = true,
	rounding = 12,
})

hl.window_rule({
	name = "float-mission-center",
	match = { class = "^io\\.missioncenter\\.MissionCenter$" },

	float = true,
	size = "800 600",
	center = true,
	rounding = 12,
})

hl.window_rule({
	name = "float-blueman-manager",
	match = { class = "^[Bb]lueman-manager$" },

	float = true,
	size = "450 550",
	center = true,
	rounding = 12,
})
