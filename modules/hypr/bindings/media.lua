------------------------------------------------------------
-- Volume
------------------------------------------------------------

hl.bindl(
    "",
    "XF86AudioRaiseVolume",
    hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+")
)

hl.bindl(
    "",
    "XF86AudioLowerVolume",
    hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-")
)

hl.bindl(
    "",
    "XF86AudioMute",
    hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle")
)

------------------------------------------------------------
-- Brightness
------------------------------------------------------------

hl.bindl(
    "",
    "XF86MonBrightnessUp",
    hl.dsp.exec_cmd("brightnessctl s +5%")
)

hl.bindl(
    "",
    "XF86MonBrightnessDown",
    hl.dsp.exec_cmd("brightnessctl s 5%-")
)