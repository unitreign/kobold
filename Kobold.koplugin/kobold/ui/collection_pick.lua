-- kobold/ui/collection_pick.lua — Kobold
-- "Add to collection" for one book (from the book menu), in the e-reader's
-- style: an inset panel with the book's title on top, the "Add to
-- collection" heading, a collection name sort and a plus for a new
-- collection, then every collection with its book count and a round marker
-- (a dark tick when the book is in it, a grey plus when not). Tap a row to
-- change it; nothing is saved until Save.

local Blitbuffer      = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device          = require("device")
local FrameContainer  = require("ui/widget/container/framecontainer")
local Geom            = require("ui/geometry")
local GestureRange    = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan  = require("ui/widget/horizontalspan")
local InfoMessage     = require("ui/widget/infomessage")
local InputContainer  = require("ui/widget/container/inputcontainer")
local InputDialog     = require("ui/widget/inputdialog")
local LeftContainer   = require("ui/widget/container/leftcontainer")
local LineWidget      = require("ui/widget/linewidget")
local OverlapGroup    = require("ui/widget/overlapgroup")
local RightContainer  = require("ui/widget/container/rightcontainer")
local TextWidget      = require("ui/widget/textwidget")
local UIManager       = require("ui/uimanager")
local VerticalGroup   = require("ui/widget/verticalgroup")
local VerticalSpan    = require("ui/widget/verticalspan")
local _               = require("gettext")
local KoboldMenu      = require("kobold.ui.menu")
local KoboldPopup     = require("kobold.ui.popup")
local KoboldWidgets   = require("kobold.ui.widgets")

local Screen = Device.screen

local KoboldCollectionPick = InputContainer:extend{
    -- Not modal: the sort menu and the keyboard open on top of it.
    name = "kobold_collection_pick",
    file = nil,       -- the book
    title = nil,      -- its title, shown on top
    on_change = nil,  -- runs after Save
    sort = "name_asc",
}

local function readCollection()
    local ok, RC = pcall(require, "readcollection")
    if ok and RC and RC.coll then return RC end
    return nil
end

local function marker(size, ticked)
    return FrameContainer:new{
        bordersize = 0, padding = 0, radius = math.floor(size / 2),
        background = ticked and Blitbuffer.COLOR_DARK_GRAY or Blitbuffer.COLOR_LIGHT_GRAY,
        CenterContainer:new{
            dimen = Geom:new{ w = size, h = size },
            TextWidget:new{
                text = ticked and "✓" or "+", face = KoboldWidgets.face(15), bold = ticked,
                fgcolor = ticked and Blitbuffer.COLOR_WHITE or Blitbuffer.COLOR_BLACK,
            },
        },
    }
end

function KoboldCollectionPick:init()
    local W, H = Screen:getWidth(), Screen:getHeight()
    self.dimen = Geom:new{ x = 0, y = 0, w = W, h = H }
    local RC = readCollection()
    self.names, self.counts, self.member = {}, {}, {}
    if RC then
        for name, coll in pairs(RC.coll) do
            self.names[#self.names + 1] = name
            local n = 0
            for _f in pairs(coll) do n = n + 1 end
            self.counts[name] = n
            if RC:isFileInCollection(self.file, name) then self.member[name] = true end
        end
    end
    self.new_names = {}  -- collections made here, created on Save
    self.page = 1
    self:sortNames()
    self[1] = self:build()
    if Device:hasKeys() then
        self.key_events = {
            Close = { { Device.input.group.Back } },
            PickNextPage = { { Device.input.group.PgFwd } },
            PickPrevPage = { { Device.input.group.PgBack } },
        }
    end
    if Device:isTouchDevice() then
        self.ges_events = {
            TapPick = { GestureRange:new{ ges = "tap", range = self.dimen } },
            SwipePick = { GestureRange:new{ ges = "swipe", range = self.dimen } },
        }
    end
end

function KoboldCollectionPick:sortNames()
    local desc = self.sort == "name_desc"
    table.sort(self.names, function(a, b)
        local x, y = a:lower(), b:lower()
        if x == y then return a < b end
        if desc then return x > y end
        return x < y
    end)
end

function KoboldCollectionPick:build()
    local R = KoboldPopup.panelRect()
    local border  = Screen:scaleBySize(2)
    local pad     = Screen:scaleBySize(20)
    local inner_w = R.w - 2 * (border + pad)
    local inner_h = R.h - 2 * (border + pad)
    local x0, y0  = R.x + border + pad, R.y + border + pad
    local top_h   = Screen:scaleBySize(36)
    local head_h  = Screen:scaleBySize(56)
    local ctrl_h  = Screen:scaleBySize(44)
    local foot_h  = Screen:scaleBySize(52)
    local gap     = Screen:scaleBySize(10)
    local line_h  = Screen:scaleBySize(1)
    local icon    = Screen:scaleBySize(26)
    local mark    = Screen:scaleBySize(30)
    self.panel_rect = R
    self.hits = {}
    local function hit(rect, fn) self.hits[#self.hits + 1] = { rect = rect, fn = fn } end

    -- Top bar: the book's title in the middle, close on the right.
    local top = OverlapGroup:new{
        dimen = Geom:new{ w = inner_w, h = top_h },
        CenterContainer:new{ dimen = Geom:new{ w = inner_w, h = top_h },
            TextWidget:new{ text = self.title or "", face = KoboldWidgets.face(15), max_width = inner_w - 4 * icon } },
        RightContainer:new{ dimen = Geom:new{ w = inner_w, h = top_h }, KoboldWidgets.icon("close", icon) },
    }
    hit(Geom:new{ x = x0 + inner_w - icon - pad, y = R.y, w = icon + 2 * pad, h = top_h + pad }, function() self:onClose() end)

    local heading = TextWidget:new{ text = _("Add to collection"), face = KoboldWidgets.face(24) }
    local head = KoboldWidgets.fixed(inner_w, head_h, LeftContainer:new{ dimen = Geom:new{ w = inner_w, h = head_h },
        HorizontalGroup:new{ HorizontalSpan:new{ width = gap }, heading } })

    -- Controls: the sort on the left, a plus for a new collection on the right.
    local ctrl_y = y0 + top_h + head_h + line_h + gap
    local sort_label = TextWidget:new{
        text = self.sort == "name_desc" and _("Sort: Collection name Z–A") or _("Sort: Collection name"),
        face = KoboldWidgets.italicFace(16),
    }
    local sort = HorizontalGroup:new{ align = "center", HorizontalSpan:new{ width = gap }, sort_label,
        HorizontalSpan:new{ width = Screen:scaleBySize(6) }, KoboldWidgets.chevronDown(Screen:scaleBySize(16)) }
    local sort_w = sort:getSize().w
    local plus = KoboldWidgets.plusIcon(icon)
    local controls = HorizontalGroup:new{ align = "center", sort,
        HorizontalSpan:new{ width = math.max(gap, inner_w - sort_w - icon - gap) }, plus }
    local sort_rect = Geom:new{ x = x0, y = ctrl_y, w = sort_w, h = ctrl_h }
    hit(sort_rect, function() self:chooseSort(sort_rect) end)
    hit(Geom:new{ x = x0 + inner_w - icon - 2 * gap, y = ctrl_y, w = icon + 2 * gap + pad, h = ctrl_h }, function() self:newCollection() end)

    -- Rows: every collection, filling the page.
    local list_y = ctrl_y + ctrl_h + gap
    local list_h = (y0 + inner_h) - foot_h - gap - list_y
    local min_row = TextWidget:new{ text = "Ag", face = KoboldWidgets.italicFace(18) }:getSize().h + Screen:scaleBySize(28)
    local per_page = math.max(1, math.floor(list_h / (min_row + line_h)))
    local row_h = min_row
    self.pages = math.max(1, math.ceil(#self.names / per_page))
    self.page = math.max(1, math.min(self.page, self.pages))
    local first = (self.page - 1) * per_page
    local rows = VerticalGroup:new{ align = "left" }
    local used = 0
    if #self.names == 0 then
        rows[#rows + 1] = CenterContainer:new{ dimen = Geom:new{ w = inner_w, h = list_h },
            TextWidget:new{ text = _("No collections yet. Tap + to make one."), face = KoboldWidgets.face(15),
                fgcolor = KoboldWidgets.subtitleColor(), max_width = inner_w } }
        used = list_h
    end
    for i = 1, per_page do
        local name = self.names[first + i]
        if not name then break end
        local in_it = self.member[name] == true
        local n = (self.counts[name] or 0)
        local count = TextWidget:new{
            text = n == 1 and _("1 book") or string.format(_("%d books"), n),
            face = KoboldWidgets.face(14),
        }
        local name_w = inner_w - count:getSize().w - mark - 4 * gap
        rows[#rows + 1] = KoboldWidgets.fixed(inner_w, row_h, HorizontalGroup:new{ align = "center",
            HorizontalSpan:new{ width = gap },
            LeftContainer:new{ dimen = Geom:new{ w = name_w, h = row_h },
                TextWidget:new{ text = name, face = KoboldWidgets.italicFace(18), max_width = name_w } },
            count,
            HorizontalSpan:new{ width = 2 * gap },
            marker(mark, in_it),
        })
        hit(Geom:new{ x = x0, y = list_y + used, w = inner_w, h = row_h }, function()
            self.member[name] = (not self.member[name]) or nil
            self:refresh()
        end)
        used = used + row_h
        rows[#rows + 1] = LineWidget:new{ dimen = Geom:new{ w = inner_w, h = line_h }, background = Blitbuffer.COLOR_LIGHT_GRAY }
        used = used + line_h
    end
    rows[#rows + 1] = VerticalSpan:new{ width = math.max(0, list_h - used) }

    -- Bottom: the page (when there are several) and Save.
    local button_w = Screen:scaleBySize(130)
    local page_label = TextWidget:new{
        text = self.pages > 1 and string.format(_("Page %d of %d"), self.page, self.pages) or "",
        face = KoboldWidgets.italicFace(15),
    }
    local foot_y = y0 + inner_h - foot_h
    local foot = HorizontalGroup:new{ align = "center",
        HorizontalSpan:new{ width = gap }, page_label,
        HorizontalSpan:new{ width = math.max(gap, inner_w - gap - page_label:getSize().w - button_w) },
        FrameContainer:new{ bordersize = 0, padding = 0, background = Blitbuffer.COLOR_LIGHT_GRAY,
            CenterContainer:new{ dimen = Geom:new{ w = button_w, h = foot_h },
                TextWidget:new{ text = _("Save"), face = KoboldWidgets.italicFace(17) } } },
    }
    hit(Geom:new{ x = x0 + inner_w - button_w, y = foot_y, w = button_w, h = foot_h }, function() self:save() end)

    local panel = FrameContainer:new{
        bordersize = border, padding = pad, radius = KoboldPopup.radius(),
        background = Blitbuffer.COLOR_WHITE,
        VerticalGroup:new{ align = "left",
            top, head,
            LineWidget:new{ dimen = Geom:new{ w = inner_w, h = line_h }, background = Blitbuffer.COLOR_DARK_GRAY },
            VerticalSpan:new{ width = gap },
            KoboldWidgets.fixed(inner_w, ctrl_h, controls),
            VerticalSpan:new{ width = gap },
            KoboldWidgets.fixed(inner_w, list_h, rows),
            VerticalSpan:new{ width = gap },
            KoboldWidgets.fixed(inner_w, foot_h, foot),
        },
    }
    return KoboldPopup.place(self.dimen, R.x, R.y, panel)
end

function KoboldCollectionPick:chooseSort(anchor)
    local function item(id, text)
        return { text = text, checked = self.sort == id, callback = function()
            self.sort = id
            self:sortNames()
            self:refresh()
        end }
    end
    KoboldMenu.show{ anchor = anchor, align = "left",
        items = { item("name_asc", _("Collection name A–Z")), item("name_desc", _("Collection name Z–A")) } }
end

-- A new collection, ticked for this book; created on Save.
function KoboldCollectionPick:newCollection()
    local RC = readCollection()
    local dialog
    dialog = InputDialog:new{
        title = _("Create new collection"),
        input_hint = _("Collection name"),
        buttons = {{
            { text = _("Cancel"), id = "close", callback = function() UIManager:close(dialog) end },
            { text = _("Create"), is_enter_default = true, callback = function()
                local name = (dialog:getInputText() or ""):match("^%s*(.-)%s*$")
                if name == "" then return end
                if (RC and RC.coll[name]) or self.new_names[name] then
                    UIManager:show(InfoMessage:new{ text = _("A collection with that name already exists."), timeout = 3 })
                    return
                end
                UIManager:close(dialog)
                self.new_names[name] = true
                self.names[#self.names + 1] = name
                self.counts[name] = 0
                self.member[name] = true
                self:sortNames()
                self:refresh()
            end },
        }},
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

-- Puts the book in exactly the ticked collections and saves.
function KoboldCollectionPick:save()
    local RC = readCollection()
    if not RC then return self:onClose() end
    local ok = pcall(function()
        for name in pairs(self.new_names) do
            if not RC.coll[name] then RC:addCollection(name) end
        end
        RC:addRemoveItemMultiple(self.file, self.member)
        RC:write()
    end)
    self:onClose()
    if not ok then
        UIManager:show(InfoMessage:new{ text = _("The collections could not be saved.") })
        return
    end
    if self.on_change then self.on_change() end
end

function KoboldCollectionPick:refresh()
    if self.closed then return end
    self[1] = self:build()
    UIManager:setDirty(self, function() return "ui", self.panel_rect end)
end

function KoboldCollectionPick:goToPage(page)
    page = math.max(1, math.min(self.pages or 1, page))
    if page == self.page then return end
    self.page = page
    self:refresh()
end

function KoboldCollectionPick:onTapPick(_, ges)
    for _i, h in ipairs(self.hits) do
        if ges.pos:intersectWith(h.rect) then
            h.fn()
            return true
        end
    end
    return true
end

function KoboldCollectionPick:onSwipePick(_, ges)
    if ges.direction == "north" then self:goToPage(self.page + 1)
    elseif ges.direction == "south" then self:goToPage(self.page - 1) end
    return true
end

function KoboldCollectionPick:onPickNextPage() self:goToPage(self.page + 1) return true end
function KoboldCollectionPick:onPickPrevPage() self:goToPage(self.page - 1) return true end

function KoboldCollectionPick:onClose()
    self.closed = true
    UIManager:close(self, "ui", self.panel_rect)
    return true
end

-- Opens the panel for `file` (title shown on top); on_change runs after Save.
function KoboldCollectionPick.show(file, title, on_change)
    local w = KoboldCollectionPick:new{ file = file, title = title, on_change = on_change }
    UIManager:show(w, "ui", w.panel_rect)
end

return KoboldCollectionPick
