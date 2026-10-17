-- kobold/meta.lua — Kobold
-- Facts about the plugin itself, for anywhere that needs them (About page,
-- _meta.lua, logs). Change VERSION here when releasing.

local KoboldMeta = {
    VERSION = "1.1.1",
    REPO    = "https://github.com/unitreign/kobold",
    LICENSE = "GPL-3.0",
    -- Developer tools, default state. When on: long-press the clock in the
    -- status bar to save a screenshot (see KoboldWidgets.statusBarFrame).
    -- Tapping the Kobold logo on the About page 10 times toggles it and
    -- saves the choice, which then wins over this default.
    DEBUG   = false,
}

-- Plugin folder (…/Kobold.koplugin), from this file's own path.
KoboldMeta.DIR = (debug.getinfo(1, "S").source or ""):match("^@(.*)/kobold/meta%.lua$")

-- True when debug mode is on: the saved toggle, or DEBUG when never toggled.
function KoboldMeta.debugOn()
    local saved = G_reader_settings and G_reader_settings:readSetting("kobold_settings")
    if type(saved) == "table" and saved.debug ~= nil then return saved.debug == true end
    return KoboldMeta.DEBUG
end

-- Full path of a file in the plugin's icons folder, or nil.
function KoboldMeta.icon(name)
    return KoboldMeta.DIR and (KoboldMeta.DIR .. "/icons/" .. name) or nil
end

return KoboldMeta
