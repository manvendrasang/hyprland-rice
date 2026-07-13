------------------------------------------------------------
-- Window Management
------------------------------------------------------------

hl.bind(mainMod .. " + Q",
    hl.dsp.window.kill_active(),
    { description = "Close Window" }
)

hl.bind(mainMod .. " + V",
    hl.dsp.window.toggle_floating(),
    { description = "Toggle Floating" }
)

hl.bind(mainMod .. " + M",
    hl.dsp.window.toggle_fullscreen(),
    { description = "Fullscreen" }
)

hl.bind(mainMod .. " + P",
    hl.dsp.window.pin(),
    { description = "Pin Window" }
)

------------------------------------------------------------
-- Focus
------------------------------------------------------------

hl.bind(mainMod .. " + Left",  hl.dsp.window.focus("l"))
hl.bind(mainMod .. " + Right", hl.dsp.window.focus("r"))
hl.bind(mainMod .. " + Up",    hl.dsp.window.focus("u"))
hl.bind(mainMod .. " + Down",  hl.dsp.window.focus("d"))

------------------------------------------------------------
-- Move
------------------------------------------------------------

hl.bind(mainMod .. " + SHIFT + Left",  hl.dsp.window.move("l"))
hl.bind(mainMod .. " + SHIFT + Right", hl.dsp.window.move("r"))
hl.bind(mainMod .. " + SHIFT + Up",    hl.dsp.window.move("u"))
hl.bind(mainMod .. " + SHIFT + Down",  hl.dsp.window.move("d"))