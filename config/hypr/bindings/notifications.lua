------------------------------------------------------------
-- Notifications
------------------------------------------------------------

hl.bind(
    mainMod .. " + D",
    hl.dsp.exec_cmd("swaync-client -t")
)

hl.bind(
    mainMod .. " + SHIFT + D",
    hl.dsp.exec_cmd("swaync-client -d")
)