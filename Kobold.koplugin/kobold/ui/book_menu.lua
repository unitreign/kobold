-- kobold/ui/book_menu.lua — Kobold
-- The small menu for one book: Read now, View Details (Kobold's details
-- page), Add to collection, and KOReader Details (the file browser's own
-- book menu), plus Remove from Home on Home's reading row and Show in Home
-- in My Books. Opened from a book's "..." in My Books and Search, and by
-- holding one of Home's recent books. Drawn by the shared dropdown menu
-- (menu.lua).

local UIManager       = require("ui/uimanager")
local _               = require("kobold.l10n")
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

-- Opens the menu. opts = { file, screen, anchor (Geom), align, side,
-- on_change, on_remove, home_show }. `on_remove` is given only by Home's
-- reading row: it adds "Remove from Home" and runs when that is picked.
-- `home_show` (My Books only) adds "Show in Home" for a book being read
-- that Home's reading row does not show.
-- `side` places it to the left of the anchor (book rows); otherwise below or
-- above it. With Kobold Settings > Book menu set to KOReader, KOReader's own
-- book menu opens directly instead.
function KoboldBookMenu.show(opts)
    if require("kobold.data.prefs").get("book_menu") == "koreader" then
        return showKOReaderMenu(opts.file, opts.on_change)
    end
    local file, screen, on_change = opts.file, opts.screen, opts.on_change
    local items = {
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
    }
    if opts.home_show and require("kobold.data.home").canShowInHome(file) then
        table.insert(items, #items, { text = _("Show in Home"), callback = function()
            require("kobold.data.home").showInHome(file)
        end })
    end
    if opts.on_remove then
        table.insert(items, #items, { text = _("Remove from Home"), callback = opts.on_remove })
    end
    KoboldMenu.show{
        anchor = opts.anchor,
        place = opts.side and "left" or nil,
        align = opts.align,
        items = items,
    }
end

return KoboldBookMenu
