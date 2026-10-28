-- kobold/ui/search.lua — Kobold
-- Kobold's search page (the search icon in the status bar; Kobold Settings
-- > Toolbar can send it to KOReader's file search instead). In the
-- e-reader's style: an inset panel with a back arrow and "Search", a search
-- box ("title, author, or series" | My Books), recent searches with Clear
-- History, and the results as book rows with a sort menu and pages. Only
-- books are searched: their title, author and series.

local Blitbuffer      = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device          = require("device")
local FrameContainer  = require("ui/widget/container/framecontainer")
local Geom            = require("ui/geometry")
local GestureRange    = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan  = require("ui/widget/horizontalspan")
local InputContainer  = require("ui/widget/container/inputcontainer")
local InputText       = require("ui/widget/inputtext")
local LeftContainer   = require("ui/widget/container/leftcontainer")
local LineWidget      = require("ui/widget/linewidget")
local OverlapGroup    = require("ui/widget/overlapgroup")
local RightContainer  = require("ui/widget/container/rightcontainer")
local TextBoxWidget   = require("ui/widget/textboxwidget")
local TextWidget      = require("ui/widget/textwidget")
local UIManager       = require("ui/uimanager")
local VerticalGroup   = require("ui/widget/verticalgroup")
local VerticalSpan    = require("ui/widget/verticalspan")
local _               = require("gettext")
local KoboldMyBooksData = require("kobold.data.mybooks")
local KoboldPrefs     = require("kobold.data.prefs")
local KoboldMenu      = require("kobold.ui.menu")
local KoboldPopup     = require("kobold.ui.popup")
local KoboldWidgets   = require("kobold.ui.widgets")

local Screen = Device.screen

local HISTORY_KEY = "search_history"
local HISTORY_MAX = 10

local SORTS = { "relevance", "recent", "added", "title", "author", "series", "size", "type" }
local SORT_LABELS = {
    relevance = _("Relevance"), recent = _("Recent"), added = _("Date added"), title = _("Title"),
    author = _("Author"), series = _("Series"), size = _("File size"), type = _("File type"),
}

local KoboldSearch = InputContainer:extend{
    -- A panel over the screen it was opened from. Not modal, so the
    -- keyboard and the menus open on top of it.
    name = "kobold_search",
    -- Also gets taps the keyboard does not use (KOReader gives a tap to the
    -- top window, the keyboard, first), so the back arrow and the results
    -- work while the keyboard is up.
    is_always_active = true,
    screen = nil,  -- the Kobold screen it was opened from (books open from there)
    query = nil,
    sort = "relevance",
}

local function history()
    local h = KoboldPrefs.get(HISTORY_KEY)
    return type(h) == "table" and h or {}
end

local function remember(query)
    local h = { query }
    for _i, q in ipairs(history()) do
        if q:lower() ~= query:lower() and #h < HISTORY_MAX then h[#h + 1] = q end
    end
    KoboldPrefs.set(HISTORY_KEY, h)
end

-- How well a book matches: title start > title > series > author > file
-- name. 0 when it does not match.
local function score(b, q)
    local title = (b.title or ""):lower()
    if title:sub(1, #q) == q then return 5 end
    if title:find(q, 1, true) then return 4 end
    if (b.series or ""):lower():find(q, 1, true) then return 3 end
    if (b.authors or ""):lower():find(q, 1, true) then return 2 end
    if (b.file:match("([^/]+)$") or ""):lower():find(q, 1, true) then return 1 end
    return 0
end

local function statusText(b)
    if b.status == "finished" then return _("Finished") end
    if b.percent and b.percent > 0 then
        return string.format(_("%d%% Read"), math.floor(b.percent * 100 + 0.5))
    end
    return _("Unread")
end

-- Results for the query, in the chosen order.
function KoboldSearch:runSearch()
    local q = (self.query or ""):lower()
    local found = {}
    for _i, b in ipairs(self.books) do
        local sc = score(b, q)
        if sc > 0 then
            b._score = sc
            found[#found + 1] = b
        end
    end
    local function byTitle(a, c)
        if a.sort_key ~= c.sort_key then return a.sort_key < c.sort_key end
        return a.file < c.file
    end
    local sort = self.sort
    if sort == "recent" then
        found = KoboldMyBooksData.sort(found, "opened_desc")
    elseif sort == "added" then
        found = KoboldMyBooksData.sort(found, "added_desc")
    elseif sort == "title" then
        table.sort(found, byTitle)
    elseif sort == "author" then
        table.sort(found, function(a, c)
            local x, y = (a.authors or "~"):lower(), (c.authors or "~"):lower()
            if x ~= y then return x < y end
            return byTitle(a, c)
        end)
    elseif sort == "series" then
        table.sort(found, function(a, c)
            local x, y = (a.series or "~"):lower(), (c.series or "~"):lower()
            if x ~= y then return x < y end
            if (a.series_index or 0) ~= (c.series_index or 0) then return (a.series_index or 0) < (c.series_index or 0) end
            return byTitle(a, c)
        end)
    elseif sort == "size" then
        table.sort(found, function(a, c)
            if (a.size or 0) ~= (c.size or 0) then return (a.size or 0) > (c.size or 0) end
            return byTitle(a, c)
        end)
    elseif sort == "type" then
        table.sort(found, function(a, c)
            if a.ext ~= c.ext then return a.ext < c.ext end
            return byTitle(a, c)
        end)
    else
        table.sort(found, function(a, c)
            if a._score ~= c._score then return a._score > c._score end
            return byTitle(a, c)
        end)
    end
    self.results = found
    self.page = 1
end

function KoboldSearch:build()
    local R = KoboldPopup.panelRect()
    local border  = Screen:scaleBySize(2)
    local pad     = Screen:scaleBySize(20)
    local inner_w = R.w - 2 * (border + pad)
    local inner_h = R.h - 2 * (border + pad)
    local x0, y0  = R.x + border + pad, R.y + border + pad
    local top_h   = Screen:scaleBySize(40)
    local box_h   = Screen:scaleBySize(54)
    local gap     = Screen:scaleBySize(12)
    local icon    = Screen:scaleBySize(26)
    local line_h  = Screen:scaleBySize(1)
    self.panel_rect = R
    self.hits = {}
    local function hit(rect, fn) self.hits[#self.hits + 1] = { rect = rect, fn = fn } end

    local page = VerticalGroup:new{ align = "left" }
    local y = y0

    -- Top bar: back arrow and the title.
    page[#page + 1] = OverlapGroup:new{
        dimen = Geom:new{ w = inner_w, h = top_h },
        LeftContainer:new{ dimen = Geom:new{ w = inner_w, h = top_h }, KoboldWidgets.icon("chevron.left", icon) },
        CenterContainer:new{ dimen = Geom:new{ w = inner_w, h = top_h },
            TextWidget:new{ text = _("Search"), face = KoboldWidgets.face(16) } },
    }
    hit(Geom:new{ x = R.x, y = R.y, w = icon + 2 * pad, h = top_h + pad }, function() self:onClose() end)
    y = y + top_h + gap
    page[#page + 1] = VerticalSpan:new{ width = gap }

    -- Search box: icon, the query (or a hint), a divider and "My Books".
    local scope = TextWidget:new{ text = _("My Books"), face = KoboldWidgets.italicFace(17) }
    local scope_w = scope:getSize().w + 2 * gap
    local field_w = inner_w - 2 * border - icon - 3 * gap - scope_w - line_h
    -- The box itself is the text field: typing goes straight into it and
    -- the keyboard's Go key searches (no separate input dialog).
    local box_inner = box_h - 2 * border
    if not self.input or self.input_w ~= field_w then
        local old = self.input and self.input:getText() or self.query or ""
        if self.input then self.input:onCloseKeyboard() end
        self.input_w = field_w
        self.input = InputText:new{
            text = old,
            hint = _("title, author, or series"),
            face = KoboldWidgets.face(18),
            width = field_w,
            bordersize = 0, padding = 0, margin = 0,
            focused = true,
            parent = self,
            enter_callback = function() self:submit() end,
        }
    end
    local field = self.input
    page[#page + 1] = FrameContainer:new{
        bordersize = border, padding = 0, radius = 0, background = Blitbuffer.COLOR_WHITE,
        KoboldWidgets.fixed(inner_w - 2 * border, box_inner, HorizontalGroup:new{
            align = "center",
            HorizontalSpan:new{ width = gap },
            KoboldWidgets.customIcon("search", icon, "appbar.search"),
            HorizontalSpan:new{ width = gap },
            KoboldWidgets.fixed(field_w, box_inner, LeftContainer:new{ dimen = Geom:new{ w = field_w, h = box_inner }, field }),
            LineWidget:new{ dimen = Geom:new{ w = line_h, h = math.floor(box_inner * 0.6) }, background = Blitbuffer.COLOR_DARK_GRAY },
            CenterContainer:new{ dimen = Geom:new{ w = scope_w, h = box_inner }, scope },
        }),
    }
    -- Taps on the icon or "My Books" also bring up the keyboard (taps on
    -- the text itself are handled by the field).
    self.box_rect = Geom:new{ x = x0, y = y, w = inner_w, h = box_h }
    hit(self.box_rect, function() self.input:onShowKeyboard() end)
    y = y + box_h + gap
    page[#page + 1] = VerticalSpan:new{ width = gap }

    local rest_h = (y0 + inner_h) - y
    if not self.query then
        self:buildHistory(page, x0, y, inner_w, rest_h, hit)
    else
        self:buildResults(page, x0, y, inner_w, rest_h, hit)
    end

    local panel = FrameContainer:new{
        bordersize = border, padding = pad, radius = KoboldPopup.radius(),
        background = Blitbuffer.COLOR_WHITE,
        KoboldWidgets.fixed(inner_w, inner_h, page),
    }
    return KoboldPopup.place(self.dimen, R.x, R.y, panel)
end

-- No query yet: RECENT SEARCHES (tap one to search it again) and Clear
-- History.
function KoboldSearch:buildHistory(page, x0, y, w, h, hit)
    local items = history()
    if #items == 0 then return end
    local band_h, row_h = Screen:scaleBySize(30), Screen:scaleBySize(46)
    local line_h, gap = Screen:scaleBySize(1), Screen:scaleBySize(12)
    page[#page + 1] = FrameContainer:new{
        bordersize = 0, padding = 0, background = Blitbuffer.COLOR_LIGHT_GRAY,
        KoboldWidgets.fixed(w, band_h, LeftContainer:new{ dimen = Geom:new{ w = w, h = band_h },
            HorizontalGroup:new{ HorizontalSpan:new{ width = gap },
                TextWidget:new{ text = _("RECENT SEARCHES"), face = KoboldWidgets.face(14) } } }),
    }
    y = y + band_h
    local max_rows = math.max(1, math.floor((h - band_h - row_h) / (row_h + line_h)))
    for i, q in ipairs(items) do
        if i > max_rows then break end
        page[#page + 1] = KoboldWidgets.fixed(w, row_h, LeftContainer:new{ dimen = Geom:new{ w = w, h = row_h },
            HorizontalGroup:new{ HorizontalSpan:new{ width = gap },
                TextWidget:new{ text = q, face = KoboldWidgets.italicFace(18), max_width = w - 2 * gap } } })
        hit(Geom:new{ x = x0, y = y, w = w, h = row_h }, function() self:search(q) end)
        y = y + row_h
        page[#page + 1] = LineWidget:new{ dimen = Geom:new{ w = w, h = line_h }, background = Blitbuffer.COLOR_LIGHT_GRAY }
        y = y + line_h
    end
    local clear = TextWidget:new{ text = _("Clear History"), face = KoboldWidgets.italicFace(17) }
    page[#page + 1] = KoboldWidgets.fixed(w, row_h, RightContainer:new{ dimen = Geom:new{ w = w, h = row_h },
        HorizontalGroup:new{ clear, HorizontalSpan:new{ width = gap } } })
    hit(Geom:new{ x = x0 + w - clear:getSize().w - 2 * gap, y = y, w = clear:getSize().w + 2 * gap, h = row_h }, function()
        KoboldPrefs.set(HISTORY_KEY, nil)
        self:refresh()
    end)
end

-- Results: the sort pill, a page of book rows and the page footer.
function KoboldSearch:buildResults(page, x0, y, w, h, hit)
    local pill_h, foot_h = Screen:scaleBySize(40), Screen:scaleBySize(44)
    local gap, line_h = Screen:scaleBySize(12), Screen:scaleBySize(1)
    local chevron = Screen:scaleBySize(16)

    -- Sort pill ("Relevance" and a chevron); opens the sort menu.
    local label = TextWidget:new{ text = SORT_LABELS[self.sort], face = KoboldWidgets.italicFace(17) }
    local pill = HorizontalGroup:new{ align = "center", label, HorizontalSpan:new{ width = Screen:scaleBySize(8) }, KoboldWidgets.chevronDown(chevron) }
    local pill_w = pill:getSize().w + gap
    page[#page + 1] = KoboldWidgets.fixed(w, pill_h, LeftContainer:new{ dimen = Geom:new{ w = w, h = pill_h },
        HorizontalGroup:new{ HorizontalSpan:new{ width = gap }, pill } })
    local pill_rect = Geom:new{ x = x0, y = y, w = pill_w + gap, h = pill_h }
    hit(pill_rect, function() self:chooseSort(pill_rect) end)
    y = y + pill_h + gap
    page[#page + 1] = VerticalSpan:new{ width = gap }

    local list_h = h - pill_h - gap - foot_h
    local results = self.results or {}
    if #results == 0 then
        page[#page + 1] = CenterContainer:new{ dimen = Geom:new{ w = w, h = list_h },
            TextBoxWidget:new{ text = string.format(_("No results for \"%s\"."), self.query),
                face = KoboldWidgets.face(16), width = w - 2 * gap, alignment = "center" } }
        return
    end

    -- As many rows as fit at their natural height (a two-line title, the
    -- series and the author), stretched to fill the page.
    local title_line = TextWidget:new{ text = "Ag", face = KoboldWidgets.face(17) }:getSize().h
    local need = 2 * title_line
        + TextWidget:new{ text = "AG", face = KoboldWidgets.face(12) }:getSize().h
        + TextWidget:new{ text = "Ag", face = KoboldWidgets.face(14) }:getSize().h
        + Screen:scaleBySize(16)
    local rows = math.max(1, math.floor((list_h + line_h) / (need + line_h)))
    self.pages = math.max(1, math.ceil(#results / rows))
    self.page = math.max(1, math.min(self.page or 1, self.pages))
    local first = (self.page - 1) * rows
    local items = {}
    for i = 1, rows do items[i] = results[first + i] end
    KoboldMyBooksData.resolve(items)

    local row_h = math.floor((list_h - (rows - 1) * line_h) / rows)
    local cover_h = row_h - Screen:scaleBySize(14)
    local cover_w = math.floor(cover_h / 1.5)
    local right_w = math.floor(w * 0.28)
    local text_w = w - cover_w - right_w - 2 * gap
    local used = 0
    for i = 1, rows do
        local b = items[i]
        if not b then break end
        if i > 1 then
            page[#page + 1] = LineWidget:new{ dimen = Geom:new{ w = w, h = line_h }, background = Blitbuffer.COLOR_LIGHT_GRAY }
            used = used + line_h
        end
        local text = VerticalGroup:new{ align = "left",
            TextBoxWidget:new{ text = b.title, face = KoboldWidgets.face(17), width = text_w,
                height = 2 * title_line, height_overflow_show_ellipsis = true } }
        if b.series then
            local s = b.series:upper()
            if b.series_index then
                local n = b.series_index
                if n == math.floor(n) then n = math.floor(n) end
                s = s .. " - " .. tostring(n)
            end
            text[#text + 1] = TextWidget:new{ text = s, face = KoboldWidgets.face(12), max_width = text_w }
        end
        text[#text + 1] = TextWidget:new{ text = b.authors or _("Unknown Author"), face = KoboldWidgets.face(14), max_width = text_w }
        local size = KoboldMyBooksData.formatSize(b.size)
        local dots = TextWidget:new{ text = "…", face = KoboldWidgets.face(18), bold = true }
        local right = VerticalGroup:new{ align = "right",
            TextWidget:new{ text = statusText(b), face = KoboldWidgets.face(15), max_width = right_w },
            TextWidget:new{ text = (b.ext ~= "" and b.ext or "") .. (size and (" · " .. size) or ""), face = KoboldWidgets.face(13), max_width = right_w },
            VerticalSpan:new{ width = Screen:scaleBySize(4) },
            dots,
        }
        -- Middle of the "..." from the row's top (the right column is
        -- centred in the row), for the menu's arrow.
        local right_h = right:getSize().h
        local dots_real_w = dots:getSize().w
        local dots_mid = math.floor((row_h - right_h) / 2) + right_h - math.floor(dots:getSize().h / 2)
        page[#page + 1] = KoboldWidgets.fixed(w, row_h, HorizontalGroup:new{ align = "center",
            CenterContainer:new{ dimen = Geom:new{ w = cover_w, h = row_h }, KoboldWidgets.makeCover(b.file, cover_w, cover_h) },
            HorizontalSpan:new{ width = gap },
            LeftContainer:new{ dimen = Geom:new{ w = text_w, h = row_h }, text },
            HorizontalSpan:new{ width = gap },
            RightContainer:new{ dimen = Geom:new{ w = right_w, h = row_h }, right },
        })
        local row_y, file = y + used, b.file
        local dots_w = Screen:scaleBySize(60)
        hit(Geom:new{ x = x0 + w - dots_w, y = row_y, w = dots_w, h = row_h }, function()
            require("kobold.ui.book_menu").show{
                file = file, screen = self.screen, side = true,
                anchor = Geom:new{ x = x0 + w - dots_real_w, y = row_y + dots_mid - Screen:scaleBySize(10), w = dots_real_w, h = Screen:scaleBySize(20) },
            }
        end)
        hit(Geom:new{ x = x0, y = row_y, w = w - dots_w, h = row_h }, function()
            self:onClose()
            require("kobold.ui.reader").open(self.screen, file)
        end)
        used = used + row_h
    end
    page[#page + 1] = VerticalSpan:new{ width = math.max(0, list_h - used) }

    -- Footer: "Page x of y" with a chevron each side where there is a page.
    local label_w = TextWidget:new{ text = string.format(_("Page %d of %d"), self.page, self.pages), face = KoboldWidgets.italicFace(16) }
    local arrow = Screen:scaleBySize(24)
    local function side(name, shown) return shown and KoboldWidgets.icon(name, arrow) or HorizontalSpan:new{ width = arrow } end
    local spacer = math.max(0, math.floor((w - 2 * arrow - label_w:getSize().w) / 2))
    page[#page + 1] = KoboldWidgets.fixed(w, foot_h, HorizontalGroup:new{ align = "center",
        side("chevron.left", self.page > 1), HorizontalSpan:new{ width = spacer }, label_w,
        HorizontalSpan:new{ width = spacer }, side("chevron.right", self.page < self.pages) })
    local foot_y = y + list_h
    hit(Geom:new{ x = x0, y = foot_y, w = math.floor(w / 2), h = foot_h }, function() self:goToPage(self.page - 1) end)
    hit(Geom:new{ x = x0 + math.floor(w / 2), y = foot_y, w = math.ceil(w / 2), h = foot_h }, function() self:goToPage(self.page + 1) end)
end

function KoboldSearch:chooseSort(anchor)
    local items = {}
    for _i, id in ipairs(SORTS) do
        items[#items + 1] = { text = SORT_LABELS[id], checked = id == self.sort, callback = function()
            self.sort = id
            self:runSearch()
            self:refresh()
        end }
    end
    KoboldMenu.show{ items = items, anchor = anchor, align = "left" }
end

-- The keyboard's Go key: searches for the text, or goes back to the recent
-- searches when the box is empty. The keyboard closes to show the results.
function KoboldSearch:submit()
    local text = (self.input:getText() or ""):match("^%s*(.-)%s*$")
    self.input:onCloseKeyboard()
    if text ~= "" then
        self:search(text)
    else
        self.query = nil
        self:refresh()
    end
end

-- Searches for `query` and remembers it. `quiet` skips the redraw (the
-- caller redraws).
function KoboldSearch:search(query, quiet)
    self.query = query
    if self.input then
        if self.input:getText() ~= query then self.input:setText(query) end
        self.input:onCloseKeyboard()
    end
    remember(query)
    self:runSearch()
    if not quiet then self:refresh() end
end

function KoboldSearch:init()
    local W, H = Screen:getWidth(), Screen:getHeight()
    self.dimen = Geom:new{ x = 0, y = 0, w = W, h = H }
    self.books = KoboldMyBooksData.getBooks()
    self.page = 1
    self[1] = self:build()
    if Device:hasKeys() then
        self.key_events = {
            Close = { { Device.input.group.Back } },
            SearchNextPage = { { Device.input.group.PgFwd } },
            SearchPrevPage = { { Device.input.group.PgBack } },
        }
    end
    if Device:isTouchDevice() then
        self.ges_events = {
            TapSearch = { GestureRange:new{ ges = "tap", range = self.dimen } },
            SwipeSearch = { GestureRange:new{ ges = "swipe", range = self.dimen } },
        }
    end
end

function KoboldSearch:goToPage(page)
    if not self.pages then return end
    page = math.max(1, math.min(self.pages, page))
    if page == self.page then return end
    self.page = page
    self:refresh()
end

function KoboldSearch:onTapSearch(_, ges)
    if self.closed then return false end
    for _i, h in ipairs(self.hits) do
        if ges.pos:intersectWith(h.rect) then
            -- Anything but the search box puts the keyboard away first.
            if h.rect ~= self.box_rect and self.input then self.input:onCloseKeyboard() end
            h.fn()
            return true
        end
    end
    if self.input then self.input:onCloseKeyboard() end
    return true
end

function KoboldSearch:onSwipeSearch(_, ges)
    if ges.direction == "north" or ges.direction == "west" then self:goToPage((self.page or 1) + 1)
    elseif ges.direction == "south" or ges.direction == "east" then self:goToPage((self.page or 1) - 1) end
    return true
end

function KoboldSearch:onSearchNextPage() self:goToPage((self.page or 1) + 1) return true end
function KoboldSearch:onSearchPrevPage() self:goToPage((self.page or 1) - 1) return true end

function KoboldSearch:refresh()
    if self.closed then return end
    self[1] = self:build()
    UIManager:setDirty(self, function() return "ui", self.panel_rect end)
end

function KoboldSearch:onClose()
    if self.input then self.input:onCloseKeyboard() end
    self.closed = true
    UIManager:close(self, "ui", self.panel_rect)
    return true
end

-- Opens the search page over `screen` (the Kobold screen it came from),
-- with the keyboard up for a first search.
function KoboldSearch.show(screen)
    local w = KoboldSearch:new{ screen = screen }
    UIManager:show(w, "ui", w.panel_rect)
    w.input:onShowKeyboard()
end

return KoboldSearch
