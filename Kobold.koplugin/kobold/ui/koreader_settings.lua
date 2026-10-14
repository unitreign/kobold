-- kobold/ui/koreader_settings.lua — Kobold
-- Popup list of KOReader's global settings (read-only).

local Menu            = require("ui/widget/menu")
local UIManager       = require("ui/uimanager")
local _               = require("gettext")
local KoboldSettings  = require("kobold.data.settings")

local KoboldKOReaderSettings = {}

function KoboldKOReaderSettings.show()
    local items = KoboldSettings.getKOReaderItems()
    for _i, item in ipairs(items) do
        item.callback = function() end  -- display only, nothing to act on
    end

    local menu = Menu:new{
        title = _("KOReader Settings"),
        item_table = items,
        covers_fullscreen = true,
        is_borderless = true,
        is_popout = false,
    }
    UIManager:show(menu)
    return menu
end

return KoboldKOReaderSettings
