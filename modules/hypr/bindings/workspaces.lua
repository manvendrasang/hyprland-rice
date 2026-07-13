------------------------------------------------------------
-- Workspaces
------------------------------------------------------------

for i = 1, 9 do

    hl.bind(
        mainMod .. " + " .. i,
        hl.dsp.workspace.switch(i)
    )

    hl.bind(
        mainMod .. " + SHIFT + " .. i,
        hl.dsp.window.move_to_workspace(i)
    )

end