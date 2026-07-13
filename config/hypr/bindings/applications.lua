------------------------------------------------------------
-- Application Keybinds
------------------------------------------------------------

hl.bind(mainMod .. " + T",
    hl.dsp.exec_cmd(terminal),
    { description = "Terminal" }
)

hl.bind(mainMod .. " + B",
    hl.dsp.exec_cmd(browser),
    { description = "Browser" }
)

hl.bind(mainMod .. " + F",
    hl.dsp.exec_cmd(fileManager),
    { description = "File Manager" }
)

hl.bind(mainMod .. " + C",
    hl.dsp.exec_cmd(textEditor),
    { description = "VS Code" }
)

hl.bind(mainMod .. " + N",
    hl.dsp.exec_cmd(terminal .. " -e " .. terminalEditor),
    { description = "Neovim" }
)

hl.bind(mainMod .. " + SPACE",
    hl.dsp.exec_cmd(launcher),
    { description = "Launcher" }
)