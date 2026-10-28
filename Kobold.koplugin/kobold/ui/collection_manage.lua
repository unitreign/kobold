-- kobold/ui/collection_manage.lua — Kobold
-- Manage collection, in the e-reader's style: an inset panel with two views.
--   Manage: the collection's books, each with a filled tick; tap a book to
--     mark it for removal. "Add Books" switches to the other view.
--   Add books: every book in the library, ticked when in the collection;
--     tap to add or remove. A back arrow returns to Manage; search narrows
--     the list.
-- Both views have Filter and Sort, "Adding: n  Removing: n" at the bottom,
-- and Cancel / Save. Nothing changes until Save. Creating a new collection
-- opens straight into Add books with a Create button.

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
local LeftContainer   = require("ui/widget/container/leftcontainer")
local LineWidget      = require("ui/widget/linewidget")
local OverlapGroup    = require("ui/widget/overlapgroup")
local RightContainer  = require("ui/widget/container/rightcontainer")
local TextWidget      = require("ui/widget/textwidget")
local UIManager       = require("ui/uimanager")
local VerticalGroup   = require("ui/widget/verticalgroup")
local VerticalSpan    = require("ui/widget/verticalspan")
local _               = require("gettext")
local KoboldMyBooksData = require("kobold.data.mybooks")
local KoboldMenu      = require("kobold.ui.menu")
local KoboldPopup     = require("kobold.ui.popup")
local KoboldWidgets   = require("kobold.ui.widgets")

local Screen = Device.screen

local FILTERS = { "all", "reading", "unread", "finished" }
local FILTER_LABELS = { all = _("All"), reading = _("Reading"), unread = _("Unread"), finished = _("Finished") }
local SORTS = { "opened_desc", "added_desc", "title_asc", "title_desc" }
local SORT_LABELS = {
    opened_desc = _("Recent"), added_desc = _("Date added"),
    title_asc = _("Title A–Z"), title_desc = _("Title Z–A"),
}

local KoboldCollectionManage = InputContainer:extend{
    -- Not modal: menus and the keyboard open on top of it.
    name = "kobold_collection_manage",
    collection = nil, -- the collection's name (its key in KOReader's collections)
    books = nil,      -- every library book (My Books entries)
    create = false,   -- true: a new collection, created on Save ("Create")
    on_done = nil,    -- called after Save with the collection's name
}

local function readCollection()
    local ok, RC = pcall(require, "readcollection")
    if ok and RC and RC.coll then return RC end
    return nil
end

-- A pill with italic text and a down chevron, exactly h tall.
local function pill(text, h, max_w, grey)
    local label = TextWidget:new{ text = text, face = KoboldWidgets.italicFace(15), max_width = max_w }
    local content = HorizontalGroup:new{
        align = "center",
        label,
        HorizontalSpan:new{ width = Screen:scaleBySize(6) },
        KoboldWidgets.chevronDown(Screen:scaleBySize(16)),
    }
    local ch = content:getSize().h
    local side = Screen:scaleBySize(12)
    local top = math.floor((h - ch) / 2)
    local frame = FrameContainer:new{
        bordersize = 0, radius = math.floor(h / 2),
        background = grey and Blitbuffer.COLOR_LIGHT_GRAY or nil,
        padding = 0, padding_left = side, padding_right = side,
        padding_top = top, padding_bottom = h - ch - top,
        content,
    }
    return frame, frame:getSize().w
end

-- Round marker on the right of a row: a dark circle with a white tick when
-- the book is in the collection, a light grey circle with a plus when not.
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

function KoboldCollectionManage:init()
    local W, H = Screen:getWidth(), Screen:getHeight()
    self.dimen = Geom:new{ x = 0, y = 0, w = W, h = H }
    local RC = readCollection()
    self.original = {}
    local coll = RC and RC.coll[self.collection]
    if coll then
        for file in pairs(coll) do self.original[file] = true end
    end
    self.adds, self.removes = {}, {}
    self.view = self.create and "add" or "manage"
    self.filter, self.sort, self.query = "all", "opened_desc", nil
    self.page = 1
    self:applyView()
    self[1] = self:build()
    if Device:hasKeys() then
        self.key_events = {
            Close = { { Device.input.group.Back } },
            ManageNextPage = { { Device.input.group.PgFwd } },
            ManagePrevPage = { { Device.input.group.PgBack } },
        }
    end
    if Device:isTouchDevice() then
        self.ges_events = {
            TapManage = { GestureRange:new{ ges = "tap", range = self.dimen } },
            SwipeManage = { GestureRange:new{ ges = "swipe", range = self.dimen } },
        }
    end
end

-- True when `file` will be in the collection after Save.
function KoboldCollectionManage:inCollection(file)
    if self.original[file] then return not self.removes[file] end
    return self.adds[file] == true
end

function KoboldCollectionManage:toggle(file)
    if self.original[file] then
        self.removes[file] = (not self.removes[file]) or nil
    else
        self.adds[file] = (not self.adds[file]) or nil
    end
end

local function count(t) local n = 0 for _k in pairs(t) do n = n + 1 end return n end

-- The books listed: in Manage, the collection's books (also ones marked for
-- removal, so they can be ticked again); in Add books, the whole library,
-- narrowed by the search. Then the filter and sort.
function KoboldCollectionManage:applyView()
    local list = {}
    for _i, b in ipairs(self.books) do
        if self.view == "add" or self.original[b.file] or self.adds[b.file] then
            list[#list + 1] = b
        end
    end
    if self.view == "add" and self.query then
        local q = self.query:lower()
        local found = {}
        for _i, b in ipairs(list) do
            local hay = table.concat({ b.title or "", b.authors or "", b.series or "",
                b.file:match("([^/]+)$") or "" }, "\n"):lower()
            if hay:find(q, 1, true) then found[#found + 1] = b end
        end
        list = found
    end
    list = KoboldMyBooksData.filter(list, self.filter)
    self.list = KoboldMyBooksData.sort(list, self.sort)
    self.page = 1
end

function KoboldCollectionManage:build()
    local R = KoboldPopup.panelRect()
    local border  = Screen:scaleBySize(2)
    local pad     = Screen:scaleBySize(20)
    local inner_w = R.w - 2 * (border + pad)
    local inner_h = R.h - 2 * (border + pad)
    local x0, y0  = R.x + border + pad, R.y + border + pad
    local top_h   = Screen:scaleBySize(36)
    local head_h  = Screen:scaleBySize(56)
    local ctrl_h  = Screen:scaleBySize(40)
    local foot_h  = Screen:scaleBySize(52)
    local gap     = Screen:scaleBySize(10)
    local line_h  = Screen:scaleBySize(1)
    local icon    = Screen:scaleBySize(26)
    local mark    = Screen:scaleBySize(30)
    self.panel_rect = R
    self.hits = {}
    local function hit(rect, fn) self.hits[#self.hits + 1] = { rect = rect, fn = fn } end

    -- Rows: as many as fit between the controls and the bottom bar.
    local list_y = y0 + top_h + head_h + line_h + gap + ctrl_h + gap
    local list_h = (y0 + inner_h) - foot_h - gap - list_y
    local probe = VerticalGroup:new{
        TextWidget:new{ text = "Ag", face = KoboldWidgets.italicFace(17) },
        TextWidget:new{ text = "AG", face = KoboldWidgets.face(12) },
        TextWidget:new{ text = "Ag", face = KoboldWidgets.face(13) },
    }
    -- Thin rows (the three text lines and a little air), at least five a
    -- page, as many as fit; the leftover is shared out so the page is filled.
    local min_row = probe:getSize().h + Screen:scaleBySize(8)
    local per_page = math.max(5, math.floor(list_h / (min_row + line_h)))
    local row_h = math.floor(list_h / per_page) - line_h
    self.pages = math.max(1, math.ceil(#self.list / per_page))
    self.page = math.max(1, math.min(self.page, self.pages))
    local first = (self.page - 1) * per_page

    -- Top bar: back arrow (Add books opened from Manage), the collection's
    -- name in the middle, close on the right.
    local top = OverlapGroup:new{
        dimen = Geom:new{ w = inner_w, h = top_h },
        CenterContainer:new{
            dimen = Geom:new{ w = inner_w, h = top_h },
            TextWidget:new{ text = self.collection, face = KoboldWidgets.face(15), max_width = inner_w - 4 * icon },
        },
        RightContainer:new{ dimen = Geom:new{ w = inner_w, h = top_h }, KoboldWidgets.icon("close", icon) },
    }
    hit(Geom:new{ x = x0 + inner_w - icon - pad, y = R.y, w = icon + 2 * pad, h = top_h + pad }, function() self:onClose() end)
    if self.view == "add" and not self.create then
        top[#top + 1] = LeftContainer:new{
            dimen = Geom:new{ w = inner_w, h = top_h }, KoboldWidgets.icon("chevron.left", icon),
        }
        hit(Geom:new{ x = R.x, y = R.y, w = icon + 2 * pad, h = top_h + pad }, function() self:switchView("manage") end)
    end

    -- Heading, with "Page x of y" on the right.
    local heading = TextWidget:new{
        text = self.view == "add" and _("Add books to collection") or _("Manage collection"),
        face = KoboldWidgets.face(24), max_width = math.floor(inner_w * 0.7),
    }
    local page_label = TextWidget:new{
        text = self.pages > 1 and string.format(_("Page %d of %d"), self.page, self.pages) or "",
        face = KoboldWidgets.italicFace(15),
    }
    local head = KoboldWidgets.fixed(inner_w, head_h, HorizontalGroup:new{
        align = "center",
        HorizontalSpan:new{ width = gap },
        heading,
        HorizontalSpan:new{ width = math.max(0, inner_w - gap - heading:getSize().w - page_label:getSize().w) },
        page_label,
    })

    -- Controls: Filter and Sort; on the right "Add Books" (Manage) or the
    -- search icon, or while searching a pill with the text and an X.
    local ctrl_y = y0 + top_h + head_h + line_h + gap
    local controls = HorizontalGroup:new{ align = "center" }
    local cx = x0
    local f_pill, f_w = pill(_("Filter: ") .. FILTER_LABELS[self.filter], ctrl_h, nil, self.filter ~= "all")
    controls[#controls + 1] = f_pill
    hit(Geom:new{ x = cx, y = ctrl_y, w = f_w, h = ctrl_h }, function() self:chooseFilter(Geom:new{ x = cx, y = ctrl_y, w = f_w, h = ctrl_h }) end)
    cx = cx + f_w + gap
    controls[#controls + 1] = HorizontalSpan:new{ width = gap }
    local s_pill, s_w = pill(_("Sort: ") .. SORT_LABELS[self.sort], ctrl_h)
    controls[#controls + 1] = s_pill
    local s_x = cx
    hit(Geom:new{ x = s_x, y = ctrl_y, w = s_w, h = ctrl_h }, function() self:chooseSort(Geom:new{ x = s_x, y = ctrl_y, w = s_w, h = ctrl_h }) end)
    cx = cx + s_w
    local right, right_w, right_fn
    if self.view == "manage" then
        right = TextWidget:new{ text = _("Add Books"), face = KoboldWidgets.italicFace(16) }
        right_w = right:getSize().w
        right_fn = function() self:switchView("add") end
    elseif self.query then
        local label = TextWidget:new{
            text = '"' .. self.query .. '"', face = KoboldWidgets.italicFace(15),
            max_width = math.max(Screen:scaleBySize(60), x0 + inner_w - cx - 3 * gap - icon),
        }
        right = HorizontalGroup:new{ align = "center", label, HorizontalSpan:new{ width = gap }, KoboldWidgets.icon("close", Screen:scaleBySize(16)) }
        right_w = right:getSize().w
        right_fn = function() self.query = nil self:applyView() self:refresh() end
    else
        right = KoboldWidgets.customIcon("search", icon, "appbar.search")
        right_w = icon
        right_fn = function() self:askSearch() end
    end
    controls[#controls + 1] = HorizontalSpan:new{ width = math.max(gap, x0 + inner_w - cx - right_w) }
    controls[#controls + 1] = right
    hit(Geom:new{ x = x0 + inner_w - right_w - gap, y = ctrl_y, w = right_w + gap + pad, h = ctrl_h }, right_fn)

    -- One page of book rows.
    local rows = VerticalGroup:new{ align = "left" }
    local used = 0
    local text_w = inner_w - mark - 2 * gap
    if #self.list == 0 then
        local empty
        if self.view == "manage" then
            empty = _("No books in this collection yet. Tap Add Books to add some.")
        else
            empty = _("No books match.")
        end
        rows[#rows + 1] = CenterContainer:new{
            dimen = Geom:new{ w = inner_w, h = list_h },
            TextWidget:new{ text = empty, face = KoboldWidgets.face(15), fgcolor = KoboldWidgets.subtitleColor(), max_width = inner_w },
        }
        used = list_h
    end
    for i = 1, per_page do
        local b = self.list[first + i]
        if not b then break end
        local text = VerticalGroup:new{
            align = "left",
            TextWidget:new{ text = b.title, face = KoboldWidgets.italicFace(17), max_width = text_w },
        }
        if b.series then
            local s = b.series:upper()
            if b.series_index then
                local n = b.series_index
                if n == math.floor(n) then n = math.floor(n) end
                s = s .. " - " .. tostring(n)
            end
            text[#text + 1] = TextWidget:new{ text = s, face = KoboldWidgets.face(12), max_width = text_w }
        end
        text[#text + 1] = TextWidget:new{
            text = b.authors or _("Unknown Author"), face = KoboldWidgets.face(13), max_width = text_w,
        }
        rows[#rows + 1] = KoboldWidgets.fixed(inner_w, row_h, HorizontalGroup:new{
            align = "center",
            LeftContainer:new{ dimen = Geom:new{ w = text_w + gap, h = row_h }, HorizontalGroup:new{ HorizontalSpan:new{ width = gap }, text } },
            HorizontalSpan:new{ width = gap },
            marker(mark, self:inCollection(b.file)),
        })
        local file = b.file
        hit(Geom:new{ x = x0, y = list_y + used, w = inner_w, h = row_h }, function()
            self:toggle(file)
            self:refresh()
        end)
        used = used + row_h
        rows[#rows + 1] = LineWidget:new{ dimen = Geom:new{ w = inner_w, h = line_h }, background = Blitbuffer.COLOR_LIGHT_GRAY }
        used = used + line_h
    end
    rows[#rows + 1] = VerticalSpan:new{ width = math.max(0, list_h - used) }

    -- Bottom bar: the counts, Cancel and Save (Create for a new collection).
    local button_w = Screen:scaleBySize(130)
    local function button(text)
        return FrameContainer:new{
            bordersize = 0, padding = 0, background = Blitbuffer.COLOR_LIGHT_GRAY,
            CenterContainer:new{ dimen = Geom:new{ w = button_w, h = foot_h },
                TextWidget:new{ text = text, face = KoboldWidgets.italicFace(17) } },
        }
    end
    local counts = TextWidget:new{
        text = string.format(_("Adding: %d    Removing: %d"), count(self.adds), count(self.removes)),
        face = KoboldWidgets.face(15),
    }
    local foot_y = y0 + inner_h - foot_h
    local foot = HorizontalGroup:new{
        align = "center",
        HorizontalSpan:new{ width = gap },
        counts,
        HorizontalSpan:new{ width = math.max(gap, inner_w - gap - counts:getSize().w - 2 * button_w - gap) },
        button(_("Cancel")),
        HorizontalSpan:new{ width = gap },
        button(self.create and _("Create") or _("Save")),
    }
    hit(Geom:new{ x = x0 + inner_w - 2 * button_w - gap, y = foot_y, w = button_w, h = foot_h }, function() self:onClose() end)
    hit(Geom:new{ x = x0 + inner_w - button_w, y = foot_y, w = button_w, h = foot_h }, function() self:save() end)

    local panel = FrameContainer:new{
        bordersize = border, padding = pad,
        radius = KoboldPopup.radius(),
        background = Blitbuffer.COLOR_WHITE,
        VerticalGroup:new{
            align = "left",
            top,
            head,
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

function KoboldCollectionManage:switchView(view)
    self.view = view
    self.query = nil
    self:applyView()
    self:refresh()
end

function KoboldCollectionManage:chooseFilter(anchor)
    local items = {}
    for _i, id in ipairs(FILTERS) do
        items[#items + 1] = { text = FILTER_LABELS[id], checked = id == self.filter, callback = function()
            self.filter = id
            self:applyView()
            self:refresh()
        end }
    end
    KoboldMenu.show{ items = items, anchor = anchor, align = "left" }
end

function KoboldCollectionManage:chooseSort(anchor)
    local items = {}
    for _i, id in ipairs(SORTS) do
        items[#items + 1] = { text = SORT_LABELS[id], checked = id == self.sort, callback = function()
            self.sort = id
            self:applyView()
            self:refresh()
        end }
    end
    KoboldMenu.show{ items = items, anchor = anchor, align = "left" }
end

-- Search popup (search_prompt.lua); the results show in this list with the
-- search text and an X on top.
function KoboldCollectionManage:askSearch()
    require("kobold.ui.search_prompt").show{
        text = self.query or "",
        on_search = function(text)
            self.query = text ~= "" and text or nil
            self:applyView()
            self:refresh()
        end,
    }
end

-- Applies the changes to KOReader's collections and saves them.
function KoboldCollectionManage:save()
    local RC = readCollection()
    if not RC then return end
    local name = self.collection
    local ok = pcall(function()
        if not RC.coll[name] then RC:addCollection(name) end
        if next(self.adds) then RC:addItemsMultiple(self.adds, { [name] = true }) end
        for file in pairs(self.removes) do RC:removeItem(file, name, true) end
        RC:write(self.create and nil or { [name] = true })
    end)
    self:onClose()
    if not ok then
        UIManager:show(InfoMessage:new{ text = _("The collection could not be saved.") })
        return
    end
    if self.on_done then self.on_done(name) end
end

function KoboldCollectionManage:refresh()
    if self.closed then return end
    self[1] = self:build()
    UIManager:setDirty(self, function() return "ui", self.panel_rect end)
end

function KoboldCollectionManage:goToPage(page)
    page = math.max(1, math.min(self.pages or 1, page))
    if page == self.page then return end
    self.page = page
    self:refresh()
end

function KoboldCollectionManage:onTapManage(_, ges)
    for _i, h in ipairs(self.hits) do
        if ges.pos:intersectWith(h.rect) then
            h.fn()
            return true
        end
    end
    return true
end

function KoboldCollectionManage:onSwipeManage(_, ges)
    if ges.direction == "north" then self:goToPage(self.page + 1)
    elseif ges.direction == "south" then self:goToPage(self.page - 1) end
    return true
end

function KoboldCollectionManage:onManageNextPage() self:goToPage(self.page + 1) return true end
function KoboldCollectionManage:onManagePrevPage() self:goToPage(self.page - 1) return true end

function KoboldCollectionManage:onClose()
    self.closed = true
    UIManager:close(self, "ui", self.panel_rect)
    return true
end

-- Opens the panel. opts = { collection, books, create, on_done }.
function KoboldCollectionManage.show(opts)
    local w = KoboldCollectionManage:new(opts)
    UIManager:show(w, "ui", w.panel_rect)
end

return KoboldCollectionManage
