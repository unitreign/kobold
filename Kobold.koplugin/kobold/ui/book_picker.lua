-- kobold/ui/book_picker.lua — Kobold
-- Popup for adding books to a collection, in the same rounded style as the
-- other Kobold popups: a page of books with a checkbox each, the side page
-- bar to move through them, and Cancel / Add buttons. Ticks are kept while
-- paging. Books already in the collection are not listed.

local Blitbuffer      = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device          = require("device")
local FrameContainer  = require("ui/widget/container/framecontainer")
local Geom            = require("ui/geometry")
local GestureRange    = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan  = require("ui/widget/horizontalspan")
local InputContainer  = require("ui/widget/container/inputcontainer")
local LeftContainer   = require("ui/widget/container/leftcontainer")
local LineWidget      = require("ui/widget/linewidget")
local TextWidget      = require("ui/widget/textwidget")
local UIManager       = require("ui/uimanager")
local VerticalGroup   = require("ui/widget/verticalgroup")
local VerticalSpan    = require("ui/widget/verticalspan")
local _               = require("gettext")
local KoboldMyBooksData = require("kobold.data.mybooks")
local KoboldEditors   = require("kobold.ui.editors")
local KoboldPopup     = require("kobold.ui.popup")
local KoboldWidgets   = require("kobold.ui.widgets")

local Screen = Device.screen

local ROWS = 6  -- books per page

-- Filter and sort choices, as in My Books.
local FILTERS = { "all", "reading", "unread", "finished" }
local FILTER_LABELS = { all = _("All"), reading = _("Reading"), unread = _("Unread"), finished = _("Finished") }
local SORTS = { "title_asc", "title_desc", "opened_desc", "added_desc" }
local SORT_LABELS = {
    title_asc = _("Title A–Z"), title_desc = _("Title Z–A"),
    opened_desc = _("Recent"), added_desc = _("Newest"),
}

-- A grey rounded pill: text then a down chevron (or `icon`), exactly h tall.
local function pill(text, h, icon, max_w)
    local label = TextWidget:new{ text = text, face = KoboldWidgets.italicFace(15), max_width = max_w }
    local content = HorizontalGroup:new{
        align = "center",
        label,
        HorizontalSpan:new{ width = Screen:scaleBySize(6) },
        icon or KoboldWidgets.chevronDown(Screen:scaleBySize(16)),
    }
    local ch = content:getSize().h
    local side = Screen:scaleBySize(14)
    local top = math.floor((h - ch) / 2)
    local frame = FrameContainer:new{
        bordersize = 0, radius = math.floor(h / 2), background = Blitbuffer.COLOR_LIGHT_GRAY,
        padding = 0, padding_left = side, padding_right = side,
        padding_top = top, padding_bottom = h - ch - top,
        content,
    }
    return frame, frame:getSize().w
end

local KoboldBookPicker = InputContainer:extend{
    -- Not modal: its filter and sort choices and the search keyboard must
    -- open on top of it.
    name = "kobold_book_picker",
    title = nil,     -- popup heading
    books = nil,     -- entries to choose from (see data/mybooks.lua)
    on_add = nil,    -- called with { [file] = true } of the ticked books
}

-- Rounded checkbox, filled when ticked. Exactly `size` square.
local function checkbox(size, ticked)
    local border = Screen:scaleBySize(2)
    local gap = Screen:scaleBySize(4)
    local inner = size - 2 * border
    local mark = KoboldWidgets.fixed(inner, inner, HorizontalSpan:new{ width = 0 })
    if ticked then
        local fill = inner - 2 * gap
        mark = KoboldWidgets.fixed(inner, inner, HorizontalGroup:new{
            HorizontalSpan:new{ width = gap },
            VerticalGroup:new{
                VerticalSpan:new{ width = gap },
                FrameContainer:new{
                    bordersize = 0, padding = 0, radius = Screen:scaleBySize(2),
                    background = Blitbuffer.COLOR_BLACK,
                    KoboldWidgets.fixed(fill, fill, HorizontalSpan:new{ width = 0 }),
                },
            },
        })
    end
    return FrameContainer:new{
        bordersize = border, padding = 0, radius = Screen:scaleBySize(4),
        background = Blitbuffer.COLOR_WHITE,
        mark,
    }
end

-- A rounded button of exactly w x h. `dim` greys the label (nothing to do).
local function button(text, w, h, bold, dim)
    local border = Screen:scaleBySize(2)
    return FrameContainer:new{
        bordersize = border, padding = 0, radius = Screen:scaleBySize(8),
        background = Blitbuffer.COLOR_WHITE,
        CenterContainer:new{
            dimen = Geom:new{ w = w - 2 * border, h = h - 2 * border },
            TextWidget:new{
                text = text, face = KoboldWidgets.face(16), bold = bold,
                fgcolor = dim and Blitbuffer.COLOR_DARK_GRAY or nil,
            },
        },
    }
end

function KoboldBookPicker:countSelected()
    local n = 0
    for _f in pairs(self.selected) do n = n + 1 end
    return n
end

-- Builds the box and records the tap rectangles (rows, bar, buttons) in
-- screen coordinates.
function KoboldBookPicker:build()
    local W, H = Screen:getWidth(), Screen:getHeight()
    local pad, border = Screen:scaleBySize(18), Screen:scaleBySize(2)
    local fw, fh = math.floor(W * 0.9), math.floor(H * 0.8)
    local fx, fy = math.floor((W - fw) / 2), math.floor((H - fh) / 2)
    local inner_w, inner_h = fw - 2 * (pad + border), fh - 2 * (pad + border)
    local x0, y0 = fx + border + pad, fy + border + pad

    local title_h   = Screen:scaleBySize(44)
    local gap       = Screen:scaleBySize(12)
    local buttons_h = Screen:scaleBySize(52)
    local line_h    = Screen:scaleBySize(1)
    local bar_w     = Screen:scaleBySize(28)
    local bar_gap   = Screen:scaleBySize(10)
    local arrow     = Screen:scaleBySize(24)
    local cb        = Screen:scaleBySize(26)
    local controls_h = Screen:scaleBySize(40)
    local list_h = inner_h - title_h - controls_h - buttons_h - 3 * gap
    local row_w  = inner_w - bar_w - bar_gap
    local row_h  = math.floor((list_h - (ROWS - 1) * line_h) / ROWS)
    local thumb_h = row_h - Screen:scaleBySize(12)
    local thumb_w = math.floor(thumb_h / 1.5)
    local text_w = row_w - cb - thumb_w - 3 * gap

    self.pages = math.max(1, math.ceil(#self.books / ROWS))
    self.page = math.max(1, math.min(self.page, self.pages))
    local first = (self.page - 1) * ROWS
    self.frame_dimen = Geom:new{ x = fx, y = fy, w = fw, h = fh }
    self.row_hits = {}

    -- Title: heading on the left, how many are ticked on the right.
    local n = self:countSelected()
    local heading = TextWidget:new{
        text = self.title, face = KoboldWidgets.face(19), bold = true,
        max_width = math.floor(inner_w * 0.7),
    }
    local count = TextWidget:new{
        text = n == 1 and _("1 selected") or string.format(_("%d selected"), n),
        face = KoboldWidgets.face(14), fgcolor = KoboldWidgets.subtitleColor(),
    }
    local title_row = KoboldWidgets.fixed(inner_w, title_h, LeftContainer:new{
        dimen = Geom:new{ w = inner_w, h = title_h },
        HorizontalGroup:new{
            heading,
            HorizontalSpan:new{ width = math.max(0, inner_w - heading:getSize().w - count:getSize().w) },
            count,
        },
    })

    -- Controls: Filter and Sort pills; on the right a search icon, or while
    -- searching a pill with the search and an X that clears it.
    local controls_y = y0 + title_h + gap
    local pill_gap = Screen:scaleBySize(12)
    self.control_hits = {}
    local controls = HorizontalGroup:new{ align = "center" }
    local cx = x0
    local function addPill(widget, w, fn)
        if #controls > 0 then
            controls[#controls + 1] = HorizontalSpan:new{ width = pill_gap }
            cx = cx + pill_gap
        end
        controls[#controls + 1] = widget
        self.control_hits[#self.control_hits + 1] = { rect = Geom:new{ x = cx, y = controls_y, w = w, h = controls_h }, fn = fn }
        cx = cx + w
    end
    local f_pill, f_w = pill(_("Filter: ") .. FILTER_LABELS[self.filter], controls_h)
    addPill(f_pill, f_w, function() self:chooseFilter() end)
    local s_pill, s_w = pill(_("Sort: ") .. SORT_LABELS[self.sort], controls_h)
    addPill(s_pill, s_w, function() self:chooseSort() end)
    local search_size = Screen:scaleBySize(26)
    local right_w, right_widget, right_fn
    if self.query then
        local max_text = math.max(Screen:scaleBySize(60), inner_w - (cx - x0) - 2 * pill_gap - Screen:scaleBySize(60))
        right_widget, right_w = pill('"' .. self.query .. '"', controls_h,
            KoboldWidgets.icon("close", Screen:scaleBySize(16)), max_text)
        right_fn = function() self:clearSearch() end
    else
        right_widget = KoboldWidgets.customIcon("search", search_size, "appbar.search")
        right_w = search_size
        right_fn = function() self:askSearch() end
    end
    controls[#controls + 1] = HorizontalSpan:new{ width = math.max(pill_gap, x0 + inner_w - cx - right_w) }
    controls[#controls + 1] = right_widget
    local right_x = x0 + inner_w - right_w
    self.control_hits[#self.control_hits + 1] = {
        rect = Geom:new{ x = right_x - pill_gap, y = controls_y, w = right_w + pill_gap + pad, h = controls_h },
        fn = right_fn,
    }

    -- One page of rows, with a thin line between rows.
    local rows = VerticalGroup:new{ align = "left" }
    local used = 0
    local list_y = controls_y + controls_h + gap
    if #self.books == 0 then
        rows[#rows + 1] = CenterContainer:new{
            dimen = Geom:new{ w = row_w, h = list_h },
            TextWidget:new{
                text = (self.query or self.filter ~= "all") and _("No books match.")
                    or _("Every book is already in this collection."),
                face = KoboldWidgets.face(15), fgcolor = KoboldWidgets.subtitleColor(),
                max_width = row_w,
            },
        }
        used = list_h
    end
    for i = 1, ROWS do
        local book = self.books[first + i]
        if not book then break end
        if i > 1 then
            rows[#rows + 1] = LineWidget:new{
                dimen = Geom:new{ w = row_w, h = line_h },
                background = Blitbuffer.COLOR_LIGHT_GRAY,
            }
            used = used + line_h
        end
        local top = list_y + used
        local text = VerticalGroup:new{
            align = "left",
            TextWidget:new{ text = book.title, face = KoboldWidgets.face(16), max_width = text_w },
        }
        if book.authors then
            text[#text + 1] = TextWidget:new{
                text = book.authors, face = KoboldWidgets.face(13),
                fgcolor = KoboldWidgets.subtitleColor(), max_width = text_w,
            }
        end
        rows[#rows + 1] = HorizontalGroup:new{
            align = "center",
            CenterContainer:new{ dimen = Geom:new{ w = cb, h = row_h }, checkbox(cb, self.selected[book.file]) },
            HorizontalSpan:new{ width = gap },
            CenterContainer:new{
                dimen = Geom:new{ w = thumb_w, h = row_h },
                KoboldWidgets.makeCover(book.file, thumb_w, thumb_h),
            },
            HorizontalSpan:new{ width = gap },
            LeftContainer:new{ dimen = Geom:new{ w = text_w, h = row_h }, text },
        }
        self.row_hits[#self.row_hits + 1] = {
            rect = Geom:new{ x = x0, y = top, w = row_w, h = row_h }, file = book.file,
        }
        used = used + row_h
    end
    rows[#rows + 1] = VerticalSpan:new{ width = math.max(0, list_h - used) }

    self.bar = { w = bar_w, h = list_h, page = self.page, pages = self.pages, arrow = arrow }
    self.bar_rect = Geom:new{ x = x0 + row_w + math.floor(bar_gap / 2), y = list_y,
        w = bar_w + math.floor(bar_gap / 2) + pad, h = list_h }

    -- Buttons: Cancel and Add, side by side.
    local button_w = math.floor((inner_w - gap) / 2)
    local buttons_y = list_y + list_h + gap
    self.cancel_rect = Geom:new{ x = x0, y = buttons_y, w = button_w, h = buttons_h }
    self.add_rect = Geom:new{ x = x0 + button_w + gap, y = buttons_y, w = button_w, h = buttons_h }
    local add_label = n > 0 and string.format(_("Add (%d)"), n) or _("Add")

    local box = FrameContainer:new{
        bordersize = border, padding = pad,
        radius = KoboldPopup.radius(),
        background = Blitbuffer.COLOR_WHITE,
        VerticalGroup:new{
            align = "left",
            title_row,
            VerticalSpan:new{ width = gap },
            KoboldWidgets.fixed(inner_w, controls_h, controls),
            VerticalSpan:new{ width = gap },
            HorizontalGroup:new{
                align = "top",
                rows,
                HorizontalSpan:new{ width = bar_gap },
                KoboldWidgets.pageBar(self.bar),
            },
            VerticalSpan:new{ width = gap },
            HorizontalGroup:new{
                button(_("Cancel"), button_w, buttons_h),
                HorizontalSpan:new{ width = gap },
                button(add_label, button_w, buttons_h, true, n == 0),
            },
        },
    }
    return KoboldPopup.place(self.dimen, fx, fy, box)
end

function KoboldBookPicker:init()
    local W, H = Screen:getWidth(), Screen:getHeight()
    self.dimen = Geom:new{ x = 0, y = 0, w = W, h = H }
    self.selected = {}
    self.page = 1
    self.all_books = self.books
    self.filter, self.sort, self.query = "all", "title_asc", nil
    self:applyView()
    self[1] = self:build()
    if Device:hasKeys() then
        self.key_events = {
            Close = { { Device.input.group.Back } },
            PickerNextPage = { { Device.input.group.PgFwd } },
            PickerPrevPage = { { Device.input.group.PgBack } },
        }
    end
    if Device:isTouchDevice() then
        self.ges_events = {
            TapPicker = { GestureRange:new{ ges = "tap", range = self.dimen } },
            SwipePicker = { GestureRange:new{ ges = "swipe", range = self.dimen } },
        }
    end
end

-- Redraws the box only (ticks, page, count).
-- The books shown: all of them, narrowed by the search and filter, in the
-- chosen order. Ticks are kept; the list goes back to its first page.
function KoboldBookPicker:applyView()
    local list = self.all_books
    if self.query then
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
    self.books = KoboldMyBooksData.sort(list, self.sort)
    self.page = 1
end

function KoboldBookPicker:chooseFilter()
    local choices = {}
    for _i, id in ipairs(FILTERS) do choices[#choices + 1] = { id = id, label = FILTER_LABELS[id] } end
    KoboldEditors.choose(_("Filter"), choices, self.filter, function(id)
        self.filter = id
        self:applyView()
    end, function() self:refresh() end)
end

function KoboldBookPicker:chooseSort()
    local choices = {}
    for _i, id in ipairs(SORTS) do choices[#choices + 1] = { id = id, label = SORT_LABELS[id] } end
    KoboldEditors.choose(_("Sort"), choices, self.sort, function(id)
        self.sort = id
        self:applyView()
    end, function() self:refresh() end)
end

-- Search by title, author, series or file name. Empty text clears it.
function KoboldBookPicker:askSearch()
    KoboldEditors.text(_("Search books"), nil, self.query or "", function(text)
        self.query = text ~= "" and text or nil
        self:applyView()
    end, function() self:refresh() end)
end

-- Back to the list as it was before searching (filter and sort kept).
function KoboldBookPicker:clearSearch()
    self.query = nil
    self:applyView()
    self:refresh()
end

function KoboldBookPicker:refresh()
    self[1] = self:build()
    UIManager:setDirty(self, function() return "ui", self.frame_dimen end)
end

function KoboldBookPicker:goToPage(page)
    page = math.max(1, math.min(self.pages, page))
    if page == self.page then return end
    self.page = page
    self:refresh()
end

function KoboldBookPicker:onTapPicker(_, ges)
    local pos = ges.pos
    if not pos:intersectWith(self.frame_dimen) then
        return self:onClose()
    end
    for _i, hit in ipairs(self.control_hits or {}) do
        if pos:intersectWith(hit.rect) then
            hit.fn()
            return true
        end
    end
    for _i, hit in ipairs(self.row_hits) do
        if pos:intersectWith(hit.rect) then
            self.selected[hit.file] = (not self.selected[hit.file]) or nil
            self:refresh()
            return true
        end
    end
    if pos:intersectWith(self.bar_rect) then
        local page = KoboldWidgets.pageBarTarget(pos.y - self.bar_rect.y, self.bar)
        if page then self:goToPage(page) end
    elseif pos:intersectWith(self.cancel_rect) then
        self:onClose()
    elseif pos:intersectWith(self.add_rect) and next(self.selected) then
        local picked = self.selected
        self:onClose()
        if self.on_add then self.on_add(picked) end
    end
    return true
end

-- Swipe up for the next page, down for the previous one, like My Books.
function KoboldBookPicker:onSwipePicker(_, ges)
    if ges.direction == "north" then
        self:goToPage(self.page + 1)
    elseif ges.direction == "south" then
        self:goToPage(self.page - 1)
    end
    return true
end

function KoboldBookPicker:onPickerNextPage() self:goToPage(self.page + 1) return true end
function KoboldBookPicker:onPickerPrevPage() self:goToPage(self.page - 1) return true end

function KoboldBookPicker:onClose()
    UIManager:close(self, "ui", self.frame_dimen)
    return true
end

-- Opens the picker. opts = { title, books, on_add }.
function KoboldBookPicker.show(opts)
    UIManager:show(KoboldBookPicker:new(opts), "ui")
end

return KoboldBookPicker
