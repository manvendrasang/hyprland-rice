------------------------------------------------------------
-- Clipboard
------------------------------------------------------------

hl.bind(
    mainMod .. " + V",
    hl.dsp.exec_cmd("cliphist list | rofi -dmenu | cliphist decode | wl-copy"),
    {
        description = "Clipboard History"
    }
)