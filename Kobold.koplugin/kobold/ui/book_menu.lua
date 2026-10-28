-- kobold/ui/book_menu.lua — Kobold
-- The small menu for one book: Read now, View Details (Kobold's details
-- page), Add to collection, and KOReader Details (the file browser's own
-- book menu). Opened from a book's "..." in My Books and Search, and by
-- holding one of Home's recent books. Drawn by the shared dropdown menu
-- (menu.lua).

local UIManager       = require("ui/uimanager")
local _               = require("gettext")
local KoboldMenu      = require("kobold.ui.menu")
local KoboldWidgets   = require("kobold.ui.widgets")

local KoboldBookMenu = {}

local function showKOReaderMenu(file, on_change)
    if not KoboldWidgets.showBookMenu(file, on_change) then
        UIManager:show(require("ui/widget/infomessage"):new{
            text = _("The KOReader book menu is not available."),
        })
    end
end

-- Opens the menu. opts = { file, screen, anchor (Geom), align, side, on_change }.
-- `side` places it to the left of the anchor (book rows); otherwise below or
-- above it. With Kobold Settings > Book menu set to KOReader, KOReader's own
-- book menu opens directly instead.
function KoboldBookMenu.show(opts)
    if require("kobold.data.prefs").get("book_menu") == "koreader" then
        return showKOReaderMenu(opts.file, opts.on_change)
    end
    local file, screen, on_change = opts.file, opts.screen, opts.on_change
    KoboldMenu.show{
        anchor = opts.anchor,
        place = opts.side and "left" or nil,
        align = opts.align,
        items = {
            { text = _("Read now"), callback = function()
                require("kobold.ui.reader").open(screen, file)
            end },
            { text = _("View Details"), callback = function()
                require("kobold.ui.book_details").show(file, screen, on_change)
            end },
            { text = _("Add to collection"), callback = function()
                local info = require("kobold.data.bookinfo").get(file) or {}
                local title = info.title or (file:match("([^/]+)%.[^%.]+$") or file)
                require("kobold.ui.collection_pick").show(file, title, on_change)
            end },
            { text = _("KOReader Details"), callback = function()
                showKOReaderMenu(file, on_change)
            end },
        },
    }
end

return KoboldBookMenu
