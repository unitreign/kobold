-- kobold/ui/reader.lua — Kobold
-- Opens a book from a Kobold screen.

local InfoMessage     = require("ui/widget/infomessage")
local UIManager       = require("ui/uimanager")
local _               = require("gettext")
local KoboldSession   = require("kobold.ui.session")

local KoboldReader = {}

-- Closes `screen`, then opens the book with KOReader's reader (the same call
-- SimpleUI uses). The screen is remembered so closing the book returns to it.
-- A failure is shown on screen instead of being ignored.
function KoboldReader.open(screen, file)
    KoboldSession.rememberScreen(screen)
    UIManager:close(screen)
    local ok, err = pcall(function()
        local ReaderUI = package.loaded["apps/reader/readerui"]
            or require("apps/reader/readerui")
        ReaderUI:showReader(file)
    end)
    if not ok then
        UIManager:show(InfoMessage:new{
            text = _("Could not open the book: ") .. tostring(err),
        })
    end
end

return KoboldReader
