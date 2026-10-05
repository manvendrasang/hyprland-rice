---- ENVIRONMENT VARIABLES ----
-------------------------------

-- See https://wiki.hypr.land/Configuring/Advanced-and-Cool/Environment-variables/

hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_SIZE", "24")
hl.env("QT_QPA_PLATFORMTHEME", "qt6ct")

-- NVIDIA compatibility. Without these, Hyprland's compositor effects
-- (blur, and potentially other rendering features) can silently fail
-- to work at all, with no error.
-- hl.env("LIBVA_DRIVER_NAME", "nvidia")
hl.env("XDG_SESSION_TYPE", "wayland")
-- Only uncomment GBM_BACKEND=nvidia-drm if your laptop has a real MUX
-- switch letting the dGPU drive the internal panel directly. On a
-- MUX-less hybrid Optimus setup (most laptops, including this rig),
-- the internal panel is wired only to the iGPU - forcing the whole
-- compositor's GBM backend to nvidia-drm in that case means Hyprland
-- renders everything correctly but nothing ever reaches the screen
-- (hyprctl layers looks perfect; the panel just stays blank). Confirm
-- via your laptop's spec sheet or `cat /sys/kernel/debug/vgaswitcheroo/switch`
-- before enabling this. scripts/prime-run.sh already exists for running
-- one specific app on the dGPU without touching this global setting.
-- hl.env("GBM_BACKEND", "nvidia-drm")
-- hl.env("__GLX_VENDOR_LIBRARY_NAME", "nvidia")
