------------------------------------------------------------
-- Screenshots
------------------------------------------------------------

hl.bind(
    "",
    "Print",
    hl.dsp.exec_cmd(
        "grim -g \"$(slurp)\" - | satty --filename -"
    )
)

hl.bind(
    "SHIFT",
    "Print",
    hl.dsp.exec_cmd(
        "grim ~/Pictures/Screenshots/$(date +'%F-%H-%M-%S').png"
    )
)