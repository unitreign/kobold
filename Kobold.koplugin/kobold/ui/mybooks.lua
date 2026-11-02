-- kobold/ui/mybooks.lua — Kobold
-- My Books screen, laid out like the e-reader's own library: the shared status bar, the
-- Books / Authors / Series / Collections tabs over a light rule, a row of
-- pills, then a page of rows with a thin separator under each. Swipe the list
-- up or down, or use the side bar, to move through the list. Bottom nav is shared with the other
-- screens.
--
-- Views:
--   Books tab         book rows, with Filter and Sort pills
--   other tabs        author / series / collection rows, with a Sort pill
--   a tapped group    that group's book rows, with a back pill
-- A book row opens the book; its "…" opens KOReader's own book menu (status,
-- delete, and so on), the same menu as a long-press in the file browser.
--
-- This file holds the screen itself: layout, tabs, pills, paging, taps and
-- reloading. Collections, the list and grid rows, and the Files tab are in
-- kobold/ui/mybooks/ (installed at the end of this file).

local Blitbuffer      = require("ffi/blitbuffer")
local ButtonDialog    = require("ui/widget/buttondialog")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device          = require("device")
local FrameContainer  = require("ui/widget/container/framecontainer")
local Geom            = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan  = require("ui/widget/horizontalspan")
local InfoMessage     = require("ui/widget/infomessage")
local InputContainer  = require("ui/widget/container/inputcontainer")
local LeftContainer   = require("ui/widget/container/leftcontainer")
local LineWidget      = require("ui/widget/linewidget")
local OverlapGroup    = require("ui/widget/overlapgroup")
local TextBoxWidget   = require("ui/widget/textboxwidget")
local TextWidget      = require("ui/widget/textwidget")
local UIManager       = require("ui/uimanager")
local VerticalGroup   = require("ui/widget/verticalgroup")
local VerticalSpan    = require("ui/widget/verticalspan")
local _               = require("kobold.l10n")
local KoboldCovers    = require("kobold.data.covers")
local KoboldPrefs     = require("kobold.data.prefs")
local KoboldLibrary   = require("kobold.data.library")
local KoboldMyBooksData = require("kobold.data.mybooks")
local KoboldNav       = require("kobold.ui.nav")
local KoboldReader    = require("kobold.ui.reader")
local KoboldTaps      = require("kobold.ui.taps")
local KoboldWidgets   = require("kobold.ui.widgets")

local Screen = Device.screen

local COVER_RATIO = 1.5  -- height / width of a book cover
local PAGE_TURNS_PER_FLASH = 10  -- see refreshList

-- Filter and sort choices are kept between sessions under these settings keys.
local FILTER_KEY     = "kobold_mybooks_filter"
local SORT_KEY       = "kobold_mybooks_sort"
local GROUP_SORT_KEY = "kobold_mybooks_group_sort"
local VIEW_KEY       = "kobold_mybooks_view"  -- Books tab: "list" or "grid"

local TABS = {
    { id = "books",       text = _("Books") },
    { id = "authors",     text = _("Authors") },
    { id = "series",      text = _("Series") },
    { id = "collections", text = _("Collections") },
    { id = "files",       text = _("Files") },  -- only when on in Kobold Settings
}

-- Tabs shown: Files only when turned on in Kobold Settings.
local function visibleTabs()
    local out = {}
    for _i, tab in ipairs(TABS) do
        if tab.id ~= "files" or KoboldPrefs.get("files_tab") then out[#out + 1] = tab end
    end
    return out
end

local FILTER_LABELS = {
    all      = _("All"),
    reading  = _("Reading"),
    unread   = _("Unread"),
    finished = _("Finished"),
}

-- pill = short text on the Sort pill, menu = text in the Sort popup.
local SORT_LABELS = {
    opened_desc = { pill = _("Recent"),   menu = _("Last opened") },
    added_desc = { pill = _("Newest"),    menu = _("Date added: newest first") },
    added_asc  = { pill = _("Oldest"),    menu = _("Date added: oldest first") },
    title_asc  = { pill = _("Title A–Z"), menu = _("Title: A to Z") },
    title_desc = { pill = _("Title Z–A"), menu = _("Title: Z to A") },
}

local GROUP_SORT_LABELS = {
    name_asc  = { pill = _("A–Z"), menu = _("Name: A to Z") },
    name_desc = { pill = _("Z–A"), menu = _("Name: Z to A") },
}

local fileChooser  -- defined with the book menu, used by the Files tab too

local KoboldMyBooks = InputContainer:extend{
    -- Not modal: KOReader menus and dialogs (also non-modal) must be able to
    -- open on top of this screen.
    covers_fullscreen = true,
    -- Shows book covers: asks the e-ink controller to dither its refreshes,
    -- so cover images come out smooth instead of banded.
    dithered = true,
    name = "kobold_mybooks",
    kobold_tab = "books",
}
KoboldWidgets.addScreenEvents(KoboldMyBooks)

-- Background of the pills: a pale gray, so black text on it stays easy to
-- read. Falls back to COLOR_LIGHT_GRAY if Color8 is missing.
local function pillColor()
    local ok, c = pcall(function() return Blitbuffer.Color8(0xDD) end)
    if ok and c then return c end
    return Blitbuffer.COLOR_LIGHT_GRAY
end

local function readChoice(key, valid, default)
    local v = G_reader_settings and G_reader_settings:readSetting(key)
    for _i, id in ipairs(valid) do
        if id == v then return v end
    end
    return default
end

local function countText(n)
    return _.N("%1 book", "%1 books", n)
end

-- Index of the rectangle in `hits` that contains point `pos`, or nil.
local function hitIndex(hits, pos)
    for i, r in ipairs(hits or {}) do
        if pos.x >= r.x and pos.x < r.x + r.w and pos.y >= r.y and pos.y < r.y + r.h then
            return i
        end
    end
    return nil
end

function KoboldMyBooks:init()
    local W, H = Screen:getWidth(), Screen:getHeight()
    self.dimen = Geom:new{ x = 0, y = 0, w = W, h = H }

    if Device:hasKeys() then
        -- Page-turn buttons (on the device or a connected remote) move
        -- through the list like swipes do.
        self.key_events = {
            Close = { { Device.input.group.Back } },
            NextListPage = { { Device.input.group.PgFwd } },
            PrevListPage = { { Device.input.group.PgBack } },
        }
    end

    self.tab        = "books"
    self.group      = nil  -- the author / series / collection being shown
    self.filter     = readChoice(FILTER_KEY, KoboldMyBooksData.FILTERS, "all")
    self.sort       = readChoice(SORT_KEY, KoboldMyBooksData.SORTS, "added_desc")
    self.group_sort = readChoice(GROUP_SORT_KEY, KoboldMyBooksData.GROUP_SORTS, "name_asc")
    self.view       = readChoice(VIEW_KEY, { "list", "grid" }, "list")
    self.page       = 1
    self.books      = KoboldMyBooksData.getBooks()

    -- Fixed layout. Every band has a set height except the list, which takes
    -- what is left between the pills and the bottom nav.
    local margin = Screen:scaleBySize(30)
    local L = {
        W = W, H = H,
        margin     = margin,
        content_w  = W - 2 * margin,
        status_h   = Screen:scaleBySize(40),
        tabs_gap   = Screen:scaleBySize(12),
        tabs_h     = Screen:scaleBySize(40),
        tab_bar_h  = Screen:scaleBySize(3),   -- black bar under the selected tab
        tab_rule_h = Screen:scaleBySize(2),   -- light rule under all the tabs
        tab_gap    = Screen:scaleBySize(26),
        pills_gap  = Screen:scaleBySize(12),
        pills_h    = Screen:scaleBySize(38),
        pill_gap   = Screen:scaleBySize(10),
        pill_pad   = Screen:scaleBySize(12),
        list_gap   = Screen:scaleBySize(10),
        line_h     = Screen:scaleBySize(1),
        list_bottom_gap = 0,  -- the last row's own padding is the gap to the nav
        bar_w      = Screen:scaleBySize(28),  -- side bar column
        bar_gap    = Screen:scaleBySize(10),  -- between the rows and the bar
        track_line_w = Screen:scaleBySize(2),
        thumb_bar_w  = Screen:scaleBySize(8),
        thumb_min_h  = Screen:scaleBySize(24),
        row_pad    = Screen:scaleBySize(10),
        col_gap    = Screen:scaleBySize(16),
        dots_w     = Screen:scaleBySize(64),  -- tap width of a row's "…"
        chevron    = Screen:scaleBySize(24),
    }
    L.y_tabs   = margin + L.status_h + L.tabs_gap
    L.y_pills  = L.y_tabs + L.tabs_h + L.pills_gap
    L.y_list   = L.y_pills + L.pills_h + L.list_gap
    L.list_h   = H - KoboldNav.height() - L.list_bottom_gap - L.y_list
    -- Rows take the content width minus the side bar on the right.
    L.list_w   = L.content_w - L.bar_gap - L.bar_w
    L.x_bar    = margin + L.list_w + L.bar_gap
    -- The side bar is a little shorter than the list, centred on it. Only
    -- its look: the pages are the same.
    L.bar_inset = Screen:scaleBySize(20)
    L.bar_h     = L.list_h - 2 * L.bar_inset

    -- n rows fill the list exactly, with a separator between rows but none
    -- after the last, so the last row ends right at the bottom nav. A slot
    -- is a row plus the separator under it.
    -- Book rows (with covers): the count set in Kobold Settings.
    -- Group rows (authors etc., text only): as many as fit at 76 px.
    local function rowsOf(n)
        local row_h = math.floor((L.list_h - (n - 1) * L.line_h) / n)
        return n, row_h + L.line_h, row_h
    end
    L.per_page, L.slot_h, L.row_h = rowsOf(KoboldPrefs.coverRows())
    L.gper_page, L.gslot_h, L.grow_h = rowsOf(math.max(1,
        math.floor((L.list_h + L.line_h) / (Screen:scaleBySize(76) + L.line_h))))

    -- Grid (Books tab, grid view): 4 covers a row, each with its status and
    -- "..." under it, as many rows as fit above a page footer.
    L.grid_cols   = 4
    L.grid_gap_x  = Screen:scaleBySize(18)
    L.grid_gap_y  = Screen:scaleBySize(14)
    L.footer_h    = Screen:scaleBySize(40)
    L.grid_cell_w = math.floor((L.content_w - (L.grid_cols - 1) * L.grid_gap_x) / L.grid_cols)
    L.grid_cover_h = math.floor(L.grid_cell_w * COVER_RATIO)
    L.grid_text_gap = Screen:scaleBySize(6)
    L.grid_status_h = KoboldWidgets.lineHeight(KoboldWidgets.face(14))
    L.grid_dots_h = TextWidget:new{ text = "…", face = KoboldWidgets.face(18), bold = true }:getSize().h
    L.grid_cell_h = L.grid_cover_h + L.grid_text_gap + L.grid_status_h + L.grid_dots_h
    L.grid_h      = L.list_h - L.footer_h
    L.grid_rows   = math.floor((L.grid_h + L.grid_gap_y) / (L.grid_cell_h + L.grid_gap_y))
    -- At least two rows, as on the e-reader: when full-width covers are too
    -- tall for two, the covers shrink to fit (each still keeps its shape
    -- inside the cell).
    if L.grid_rows < 2 then
        L.grid_rows = 2
        L.grid_cover_h = math.floor((L.grid_h - L.grid_gap_y) / 2)
            - L.grid_text_gap - L.grid_status_h - L.grid_dots_h
        L.grid_cell_h = L.grid_cover_h + L.grid_text_gap + L.grid_status_h + L.grid_dots_h
    end
    L.grid_per_page = L.grid_cols * L.grid_rows
    L.y_footer    = L.y_list + L.grid_h

    L.thumb_h  = L.row_h - 2 * L.row_pad
    L.thumb_w  = math.floor(L.thumb_h / COVER_RATIO)
    L.right_w  = math.floor(L.list_w * 0.27)
    L.text_w   = L.list_w - L.thumb_w - 2 * L.col_gap - L.right_w
    -- Titles wrap to at most two lines (this is their height), or one line
    -- when the rows are too short for two lines plus the author.
    local face_title = KoboldWidgets.face(17)
    local two = TextBoxWidget:new{ text = "A\nA", face = face_title, width = L.text_w }
    local one = TextBoxWidget:new{ text = "A", face = face_title, width = L.text_w }
    local author_h = KoboldWidgets.lineHeight(KoboldWidgets.face(14))
        + Screen:scaleBySize(4)
    -- Room for the series line too (shown for books in a series).
    author_h = author_h + KoboldWidgets.lineHeight(KoboldWidgets.face(12))
        + Screen:scaleBySize(2)
    L.title_max_h = two:getSize().h
    if L.title_max_h + author_h > L.row_h - 2 * L.row_pad then
        L.title_max_h = one:getSize().h
    end
    two:free()
    one:free()
    self.L = L

    -- Swipe down from the top edge opens the KOReader menu.
    KoboldTaps.topMenu(self)
    -- Tabs, pills and rows change with the view, so each band has one tap
    -- zone that looks up what is under the finger when it fires.
    KoboldTaps.add(self, "KoboldTabs", 0, L.y_tabs, W, L.tabs_h, function(ges)
        local i = hitIndex(self.tab_hits, ges.pos)
        if i and self:inCollection() then
            self:closeGroup()
        elseif i then
            self:showTab(visibleTabs()[i].id)
        end
    end)
    KoboldTaps.add(self, "KoboldPills", 0, L.y_pills, W, L.pills_h, function(ges)
        local i = hitIndex(self.pill_hits, ges.pos)
        if i then self.pill_actions[i]() end
    end)
    local split_x = L.x_bar - math.floor(L.bar_gap / 2)
    KoboldTaps.add(self, "KoboldList", 0, L.y_list, split_x, L.list_h, function(ges)
        self:onListTap(ges.pos)
    end)
    KoboldTaps.add(self, "KoboldSideBar", split_x, L.y_list, W - split_x, L.list_h, function(ges)
        self:onBarTap(ges.pos)
    end)
    KoboldTaps.hold(self, "KoboldListHold", 0, L.y_list, split_x, L.list_h, function(ges)
        self:onListHold(ges.pos)
    end)
    self:registerTouchZones({
        {
            id = "KoboldListSwipe",
            ges = "swipe",
            screen_zone = {
                ratio_x = 0, ratio_y = L.y_list / H,
                ratio_w = 1, ratio_h = L.list_h / H,
            },
            handler = function(ges)
                -- Like scrolling: swipe up for the next page, down for the
                -- previous one. Sideways swipes do nothing.
                -- Other directions (diagonals) are left for KOReader's own
                -- gestures (see addScreenEvents).
                local d = ges.direction
                local grid = self:isGrid()
                if d == "north" or (grid and d == "west") then
                    self:goToPage(self.page + 1)
                elseif d == "south" or (grid and d == "east") then
                    self:goToPage(self.page - 1)
                else
                    return false
                end
                return true
            end,
        },
    })

    self:hookFileManager()
    self:restoreState(self.restore)
    self:applyList()
    self[1] = self:build()
    self:ensureCovers()
end

-- What to restore when coming back from a book opened here (session.lua).
function KoboldMyBooks:getReturnState()
    return {
        tab = self.tab,
        group_key = self.group and self.group.key,
        page = self.page,
        group_page = self.group_page,
        folder = self.folder,
    }
end

-- Puts back the tab, open group and page from getReturnState(). The page is
-- clamped by applyList afterwards, in case the list got shorter.
function KoboldMyBooks:restoreState(state)
    if type(state) ~= "table" then return end
    for _i, tab in ipairs(visibleTabs()) do
        if tab.id == state.tab then self.tab = tab.id end
    end
    if self.tab ~= "books" and state.group_key then
        for _i, g in ipairs(KoboldMyBooksData.getGroups(self.books, self.tab)) do
            if g.key == state.group_key then self.group = g break end
        end
    end
    self.folder = type(state.folder) == "string" and state.folder or nil
    self.page = tonumber(state.page) or 1
    self.group_page = tonumber(state.group_page)
end

-- True on the Authors, Series and Collections lists (not inside a group).
function KoboldMyBooks:showsGroups()
    return self.tab ~= "books" and self.tab ~= "files" and not self.group
end

-- Rows per page, slot height and row height for the current view. The
-- Series list shows a cover on each row, so it uses the taller book rows.
function KoboldMyBooks:rowSize()
    local L = self.L
    if self:showsGroups() and self.tab ~= "series" then
        return L.gper_page, L.gslot_h, L.grow_h
    end
    return L.per_page, L.slot_h, L.row_h
end

function KoboldMyBooks:perPage()
    if self:isGrid() then return self.L.grid_per_page end
    return (self:rowSize())
end

-- True on the Books and Series tabs when grid view is chosen. On Series it
-- covers both the series list and the books of one series.
function KoboldMyBooks:isGrid()
    if self:inCollection() then return self:collView().view == "grid" end
    return self.view == "grid" and (self.tab == "books" or self.tab == "series")
end

-- Recomputes the list for the current view and clamps the page to it.
function KoboldMyBooks:applyList()
    if self.tab == "files" then
        self.list = self:listFolder(self:currentFolder())
    elseif self.tab == "books" then
        local list = KoboldMyBooksData.filter(self.books, self.filter)
        self.list = KoboldMyBooksData.sort(list, self.sort)
    elseif self:inCollection() then
        local v = self:collView()
        self.list = KoboldMyBooksData.sort(KoboldMyBooksData.filter(self.group.books, v.filter), v.sort)
    elseif self.group then
        self.list = self.group.books
    else
        local groups = KoboldMyBooksData.getGroups(self.books, self.tab)
        self.list = KoboldMyBooksData.sortGroups(groups, self.group_sort)
    end
    self.pages = math.max(1, math.ceil(#self.list / self:perPage()))
    self.page = math.max(1, math.min(self.page, self.pages))
end

-- Rebuilds the whole screen for the current view and page.
function KoboldMyBooks:build()
    local L = self.L
    local per_page = self:perPage()
    local first = (self.page - 1) * per_page
    self.page_items = {}
    for i = 1, per_page do
        self.page_items[i] = self.list[first + i]
    end
    -- Book rows need their reading status; read it for this page only.
    if not self:showsGroups() then
        local books = {}
        for _i, item in ipairs(self.page_items) do
            if not item.is_dir then books[#books + 1] = item end
        end
        KoboldMyBooksData.resolve(books)
    end

    local body = FrameContainer:new{
        width = L.W, bordersize = 0, padding = L.margin, padding_bottom = 0,
        VerticalGroup:new{
            align = "left",
            KoboldWidgets.statusBarFrame(self, L.margin, L.content_w, L.status_h),
            VerticalSpan:new{ width = L.tabs_gap },
            self:buildTabs(),
            VerticalSpan:new{ width = L.pills_gap },
            self:buildPills(),
            VerticalSpan:new{ width = L.list_gap },
            self:isGrid() and VerticalGroup:new{
                align = "left",
                self:buildGrid(),
                self:buildFooter(),
            } or HorizontalGroup:new{
                align = "top",
                self:buildList(),
                HorizontalSpan:new{ width = L.bar_gap },
                self:buildSidebar(),
            },
        },
    }

    return FrameContainer:new{
        width = L.W,
        height = L.H,
        bordersize = 0,
        padding = 0,
        background = Blitbuffer.COLOR_WHITE,
        OverlapGroup:new{
            dimen = Geom:new{ w = L.W, h = L.H },
            body,
            KoboldNav.attach(self, L.W, L.H, "books"),
        },
    }
end

function KoboldMyBooks:refresh()
    self[1] = self:build()
    UIManager:setDirty(self, "ui")
    self:ensureCovers()
end

-- Redraws for a new page: only the list and side bar change, so only that
-- band of the screen is refreshed.
--
-- Page turns use the quiet "ui" refresh, which slowly leaves ghosting on
-- e-ink. Every 10th one flashes ("flashui") to clear it.
function KoboldMyBooks:refreshList()
    local L = self.L
    self[1] = self:build()
    self.quiet_turns = (self.quiet_turns or 0) + 1
    local mode = "ui"
    if self.quiet_turns >= PAGE_TURNS_PER_FLASH then
        self.quiet_turns = 0
        mode = "flashui"
    end
    UIManager:setDirty(self, function()
        return mode, Geom:new{ x = 0, y = L.y_list, w = L.W, h = L.list_h }
    end)
    self:ensureCovers()
end

-- Background extraction for covers on this page that the cover browser does
-- not have yet (book rows, and the first book of each series row).
function KoboldMyBooks:ensureCovers()
    if self:showsGroups() and self.tab ~= "series" then return end
    local files = {}
    for _i, item in ipairs(self.page_items) do
        local file = item.file or (item.books and item.books[1] and item.books[1].file)
        if file then files[#files + 1] = file end
    end
    KoboldCovers.ensure(files)
end

-- KoboldCoversUpdated: covers finished extracting, redraw the rows.
function KoboldMyBooks:refreshCovers()
    if not self.closed then self:refreshList() end
end

-- The four tabs over a full-width light rule. The selected tab is bold with
-- a black bar that sits on the rule. Records each tab's tap rectangle.
function KoboldMyBooks:buildTabs()
    local L = self.L
    if self:inCollection() then
        -- Inside a collection the tabs make way for a back arrow and the
        -- collection's name; the whole row goes back to the list.
        local arrow = Screen:scaleBySize(24)
        self.tab_hits = { Geom:new{ x = 0, y = L.y_tabs, w = L.W, h = L.tabs_h } }
        return OverlapGroup:new{
            dimen = Geom:new{ w = L.content_w, h = L.tabs_h },
            VerticalGroup:new{
                VerticalSpan:new{ width = L.tabs_h - L.tab_rule_h },
                LineWidget:new{ dimen = Geom:new{ w = L.content_w, h = L.tab_rule_h }, background = Blitbuffer.COLOR_DARK_GRAY },
            },
            LeftContainer:new{
                dimen = Geom:new{ w = L.content_w, h = L.tabs_h },
                HorizontalGroup:new{
                    align = "center",
                    KoboldWidgets.icon("chevron.left", arrow),
                    HorizontalSpan:new{ width = Screen:scaleBySize(10) },
                    TextWidget:new{ text = self.group.name, face = KoboldWidgets.face(17), max_width = L.content_w - 2 * arrow },
                },
            },
        }
    end
    local row = HorizontalGroup:new{}
    local x = L.margin
    self.tab_hits = {}
    for i, tab in ipairs(visibleTabs()) do
        local selected = tab.id == self.tab
        local text = TextWidget:new{ text = tab.text, face = KoboldWidgets.face(17), bold = selected }
        local w = text:getSize().w
        if i > 1 then row[#row + 1] = HorizontalSpan:new{ width = L.tab_gap } end
        row[#row + 1] = VerticalGroup:new{
            align = "left",
            CenterContainer:new{
                dimen = Geom:new{ w = w, h = L.tabs_h - L.tab_bar_h },
                text,
            },
            selected and LineWidget:new{
                dimen = Geom:new{ w = w, h = L.tab_bar_h },
                background = Blitbuffer.COLOR_BLACK,
            } or VerticalSpan:new{ width = L.tab_bar_h },
        }
        -- Tap area reaches halfway into the gaps on both sides.
        local half = math.floor(L.tab_gap / 2)
        self.tab_hits[i] = Geom:new{ x = x - half, y = L.y_tabs, w = w + 2 * half, h = L.tabs_h }
        x = x + w + L.tab_gap
    end
    return OverlapGroup:new{
        dimen = Geom:new{ w = L.content_w, h = L.tabs_h },
        VerticalGroup:new{
            VerticalSpan:new{ width = L.tabs_h - L.tab_rule_h },
            LineWidget:new{
                dimen = Geom:new{ w = L.content_w, h = L.tab_rule_h },
                background = Blitbuffer.COLOR_LIGHT_GRAY,
            },
        },
        row,
    }
end

-- One rounded gray pill, exactly pills_h tall. `icon` is a widget placed
-- after the label, or before it when `icon_first` is set. `max_text_w`
-- shortens long labels.
function KoboldMyBooks:buildPill(label, icon, icon_first, max_text_w)
    local L = self.L
    local text = TextWidget:new{ text = label, face = KoboldWidgets.face(15), max_width = max_text_w }
    local gap = HorizontalSpan:new{ width = Screen:scaleBySize(6) }
    local content = icon_first
        and HorizontalGroup:new{ align = "center", icon, gap, text }
        or HorizontalGroup:new{ align = "center", text, gap, icon }
    local content_h = content:getSize().h
    local pad_top = math.floor((L.pills_h - content_h) / 2)
    local pill = FrameContainer:new{
        bordersize = 0,
        radius = math.floor(L.pills_h / 2),
        background = pillColor(),
        padding = 0,
        padding_left = L.pill_pad,
        padding_right = L.pill_pad,
        padding_top = pad_top,
        padding_bottom = L.pills_h - content_h - pad_top,
        content,
    }
    return pill, pill:getSize().w
end

-- The pills for the current view, left to right. Records each pill's tap
-- rectangle and action.
function KoboldMyBooks:buildPills()
    local L = self.L
    local icon_size = Screen:scaleBySize(18)
    local specs
    if self.tab == "files" then
        -- Back pill to the parent folder, also above the home folder; at
        -- the top of the file system a plain label.
        local dir = self:currentFolder()
        local name = dir:match("([^/]+)/*$") or dir
        if dir == "/" then
            specs = { { label = name, plain = true, action = function() end } }
        else
            specs = { { label = name, back = true, action = function() self:openFolder(self:parentFolder()) end } }
        end
    elseif self.tab == "books" then
        specs = {
            { label = _.T(_("Filter: %1"), FILTER_LABELS[self.filter]), action = function() self:showFilterDialog() end },
            { label = _.T(_("Sort: %1"), SORT_LABELS[self.sort].pill), action = function() self:showSortDialog() end },
        }
    elseif self:inCollection() then
        local v = self:collView()
        specs = {
            { label = _.T(_("Filter: %1"), FILTER_LABELS[v.filter]), action = function() self:showCollFilterDialog() end },
            { label = _.T(_("Sort: %1"), SORT_LABELS[v.sort].pill), action = function() self:showCollSortDialog() end },
        }
    elseif self.group then
        specs = { {
            label = self.group.name, back = true,
            action = function() self:closeGroup() end,
        } }
    else
        specs = {
            { label = _.T(_("Sort: %1"), GROUP_SORT_LABELS[self.group_sort].pill), action = function() self:showGroupSortDialog() end },
        }
    end

    local row = HorizontalGroup:new{ align = "center" }
    local x = L.margin
    self.pill_hits, self.pill_actions = {}, {}
    for i, spec in ipairs(specs) do
        local pill, w
        if spec.plain then
            pill, w = self:buildPill(spec.label,
                KoboldWidgets.icon("home", icon_size, { fallback = "appbar.filebrowser" }), true,
                L.content_w - 2 * L.pill_pad - icon_size - Screen:scaleBySize(6))
        elseif spec.back then
            -- Back pill: left chevron and the group's name, cut to fit.
            local max_text = L.content_w - 2 * L.pill_pad - icon_size - Screen:scaleBySize(6)
            if self.tab == "collections" or self.tab == "series" then
                max_text = max_text - Screen:scaleBySize(40) - 3 * L.pill_gap
            end
            pill, w = self:buildPill(spec.label, KoboldWidgets.icon("chevron.left", icon_size), true, max_text)
        else
            pill, w = self:buildPill(spec.label, KoboldWidgets.chevronDown(icon_size))
        end
        if i > 1 then row[#row + 1] = HorizontalSpan:new{ width = L.pill_gap } end
        row[#row + 1] = pill
        self.pill_hits[i] = Geom:new{ x = x, y = L.y_pills, w = w, h = L.pills_h }
        self.pill_actions[i] = spec.action
        x = x + w + L.pill_gap
    end

    -- "..." at the right end: list or grid view on Books and Series; the
    -- collection menu on Collections.
    if self.tab == "books" or self.tab == "series" or self.tab == "collections" then
        local dots = TextWidget:new{ text = "…", face = KoboldWidgets.face(20), bold = true }
        local dots_w = dots:getSize().w
        -- Kept a little in from the right edge.
        local inset = Screen:scaleBySize(14)
        local used = x - L.margin - L.pill_gap
        row[#row + 1] = HorizontalSpan:new{ width = math.max(0, L.content_w - used - dots_w - inset) }
        row[#row + 1] = dots
        local dots_x = L.margin + L.content_w - dots_w - inset
        self.pill_hits[#self.pill_hits + 1] = Geom:new{
            x = dots_x - 2 * L.pill_gap, y = L.y_pills,
            w = dots_w + inset + 3 * L.pill_gap, h = L.pills_h,
        }
        local dots_rect = Geom:new{ x = dots_x, y = L.y_pills, w = dots_w, h = L.pills_h }
        self.pill_actions[#self.pill_actions + 1] = function()
            if self.tab == "collections" then self:showCollectionsMenu(dots_rect) else self:showViewMenu(dots_rect) end
        end
    end

    return row
end

-- Item under `pos` in the list, or nil (same rows as onListTap).
function KoboldMyBooks:itemAt(pos)
    local _n, slot_h = self:rowSize()
    local i = math.floor((pos.y - self.L.y_list) / slot_h) + 1
    return self.page_items and self.page_items[i]
end

-- True inside one collection (Collections tab, a collection opened).
function KoboldMyBooks:inCollection()
    return self.tab == "collections" and self.group ~= nil
end

-- Long-press: a collection's menu on the Collections list; a book's menu in
-- the Files tab.
function KoboldMyBooks:onListHold(pos)
    local item = self:itemAt(pos)
    if not item then return end
    if self.tab == "files" then
        if item.is_dir then self:showFolderMenu(item.path) else self:openBookMenu(item.file, self:rowRect(pos), "side") end
    elseif self.tab == "collections" and not self.group then
        local L = self.L
        local _n, slot_h, row_h = self:rowSize()
        local i = math.floor((pos.y - L.y_list) / slot_h)
        self:showCollectionOptions(item, Geom:new{
            x = L.margin, y = L.y_list + i * slot_h, w = math.floor(L.list_w * 0.4), h = row_h,
        })
    end
end

-- A tap on the grid: the footer halves turn pages; on a cell, the "..." line
-- opens the book menu and anything else opens the book.
function KoboldMyBooks:onGridTap(pos)
    local L = self.L
    if pos.y >= L.y_footer then
        self:goToPage(self.page + (pos.x < L.W / 2 and -1 or 1))
        return
    end
    local rel_x, rel_y = pos.x - L.margin, pos.y - L.y_list
    if rel_x < 0 then return end
    local col = math.floor(rel_x / (L.grid_cell_w + L.grid_gap_x))
    local row = math.floor(rel_y / (L.grid_cell_h + L.grid_gap_y))
    if col >= L.grid_cols or row >= L.grid_rows then return end
    local in_x = rel_x - col * (L.grid_cell_w + L.grid_gap_x)
    local in_y = rel_y - row * (L.grid_cell_h + L.grid_gap_y)
    if in_x > L.grid_cell_w or in_y > L.grid_cell_h then return end
    local item = self.page_items[row * L.grid_cols + col + 1]
    if not item then return end
    if item.books then
        self:openGroup(item)
    elseif in_y >= L.grid_cover_h + L.grid_text_gap + L.grid_status_h then
        local cell_x = L.margin + col * (L.grid_cell_w + L.grid_gap_x)
        self:openBookMenu(item.file, Geom:new{
            x = cell_x, y = L.y_list + row * (L.grid_cell_h + L.grid_gap_y) + L.grid_cover_h,
            w = L.grid_cell_w, h = L.grid_cell_h - L.grid_cover_h,
        }, col < L.grid_cols / 2 and "left" or "right")
    else
        KoboldReader.tapOpen(self, item.file)
    end
end

-- A tap on the side bar: the arrows turn one page, a tap on the track jumps
-- to the page at that height.
function KoboldMyBooks:onBarTap(pos)
    -- In grid view this strip is part of the grid and footer.
    if self:isGrid() then return self:onGridTap(pos) end
    local page = KoboldWidgets.pageBarTarget(pos.y - self.L.y_list - self.L.bar_inset, self:barOpts())
    if page then self:goToPage(page) end
end

-- A tap in the list: opens the group or book under it. On a book row, the
-- right edge (the "…") opens the book menu instead.
function KoboldMyBooks:onListTap(pos)
    if self:isGrid() then return self:onGridTap(pos) end
    local L = self.L
    local groups = self:showsGroups()
    local _n, slot_h = self:rowSize()
    local i = math.floor((pos.y - L.y_list) / slot_h) + 1
    local item = self.page_items and self.page_items[i]
    if not item then return end
    if item.is_dir then
        self:openFolder(item.path)
    elseif groups then
        self:openGroup(item)
    elseif pos.x >= L.margin + L.list_w - L.dots_w then
        -- A small anchor right on the "..." (see buildBookRow).
        local dots_h = Screen:scaleBySize(20)
        local dy = item.dots_y or math.floor(slot_h / 2)
        self:openBookMenu(item.file, Geom:new{
            x = L.margin + L.list_w - L.dots_w, y = L.y_list + (i - 1) * slot_h + dy - math.floor(dots_h / 2),
            w = L.dots_w, h = dots_h,
        }, "side")
    else
        KoboldReader.tapOpen(self, item.file)
    end
end

function KoboldMyBooks:onNextListPage()
    self:goToPage(self.page + 1)
    return true
end

function KoboldMyBooks:onPrevListPage()
    self:goToPage(self.page - 1)
    return true
end

function KoboldMyBooks:goToPage(page)
    page = math.max(1, math.min(self.pages, page))
    if page == self.page then return end
    self.page = page
    self:refreshList()
end


function KoboldMyBooks:showTab(id)
    if id == self.tab and not self.group then return end
    self.tab = id
    self.group = nil
    self.page = 1
    self:applyList()
    self:refresh()
end

-- Shows the books of one author, series or collection. The group list page
-- is remembered so the back pill returns to it.
function KoboldMyBooks:openGroup(group)
    self.group = group
    self.group_page = self.page
    self.page = 1
    self:applyList()
    self:refresh()
end

function KoboldMyBooks:closeGroup()
    self.group = nil
    self.page = self.group_page or 1
    self:applyList()
    self:refresh()
end

-- Popup with one button per choice; the current choice is marked with a check.
-- `ids` are in menu order, `label(id)` gives each button's text.
function KoboldMyBooks:showChoiceDialog(title, ids, current, label, on_pick)
    local dialog
    local buttons = {}
    for _i, id in ipairs(ids) do
        buttons[#buttons + 1] = {{
            text = (id == current and "✓  " or "") .. label(id),
            callback = function()
                UIManager:close(dialog)
                if id ~= current then on_pick(id) end
            end,
        }}
    end
    dialog = ButtonDialog:new{
        title = title,
        width = math.floor(Screen:getWidth() * 0.6),
        buttons = buttons,
    }
    UIManager:show(dialog)
end

-- Saves a new filter or sort choice and redraws the list from page 1.
function KoboldMyBooks:setChoice(field, key, id)
    self[field] = id
    G_reader_settings:saveSetting(key, id)
    self.page = 1
    self:applyList()
    self:refresh()
end

function KoboldMyBooks:showFilterDialog()
    self:showChoiceDialog(_("Filter"), KoboldMyBooksData.FILTERS, self.filter,
        function(id) return FILTER_LABELS[id] end,
        function(id) self:setChoice("filter", FILTER_KEY, id) end)
end

function KoboldMyBooks:showSortDialog()
    self:showChoiceDialog(_("Sort"), KoboldMyBooksData.SORTS, self.sort,
        function(id) return SORT_LABELS[id].menu end,
        function(id) self:setChoice("sort", SORT_KEY, id) end)
end

-- The Books tab's "...": list or grid view.
-- The "..." beside the pills (Books and Series): a dropdown under it with
-- the one view to switch to, Cover view or List view, as inside a collection.
function KoboldMyBooks:showViewMenu(anchor)
    local grid = self.view == "grid"
    require("kobold.ui.menu").show{
        anchor = anchor, align = "right",
        items = { { text = grid and _("List view") or _("Cover view"), callback = function()
            self:setChoice("view", VIEW_KEY, grid and "list" or "grid")
        end } },
    }
end

function KoboldMyBooks:showGroupSortDialog()
    self:showChoiceDialog(_("Sort"), KoboldMyBooksData.GROUP_SORTS, self.group_sort,
        function(id) return GROUP_SORT_LABELS[id].menu end,
        function(id) self:setChoice("group_sort", GROUP_SORT_KEY, id) end)
end

fileChooser = function()
    local ok, FileManager = pcall(require, "apps/filemanager/filemanager")
    local fm = ok and FileManager and FileManager.instance
    return fm and fm.file_chooser
end

-- KOReader's book menu for `file`: the dialog the file browser shows on a
-- long-press (book status, delete, book information, and so on). It opens on
-- top of this screen; changes it makes are picked up by hookFileManager.
-- Kobold's book menu (Read now, View Details, KOReader Details), pointing
-- at `anchor` (a Geom on screen). Changes made from it reload the list.
-- `align` "side" opens it beside the anchor (book rows, as on the e-reader).
function KoboldMyBooks:openBookMenu(file, anchor, align)
    require("kobold.ui.book_menu").show{
        file = file, screen = self, anchor = anchor,
        align = align ~= "side" and align or nil, side = align == "side",
        on_change = function() self:scheduleReload() end,
        home_show = true,
    }
end

-- Screen rectangle of the "..." column of the list row under `pos`.
function KoboldMyBooks:rowRect(pos)
    local L = self.L
    local _n, slot_h, row_h = self:rowSize()
    local i = math.floor((pos.y - L.y_list) / slot_h)
    return Geom:new{ x = L.margin + L.list_w - L.dots_w, y = L.y_list + i * slot_h, w = L.dots_w, h = row_h }
end

function KoboldMyBooks:showBookMenu(file)
    local fc = fileChooser()
    local show = fc and (fc.showFileDialog or fc.onFileHold)
    local ok = false
    if show then
        local item = { path = file, file = file, is_file = true, text = file:match("[^/]+$") }
        ok = pcall(show, fc, item)
    end
    if not ok then
        UIManager:show(InfoMessage:new{ text = _("The book menu is not available.") })
    end
end

-- The file browser refreshes its file list after every change made from the
-- book menu (status, delete, reset, ...). While this screen is open, that
-- refresh also reloads My Books (see hooks.lua). Undone in onCloseWidget.
function KoboldMyBooks:hookFileManager()
    local KoboldHooks = require("kobold.ui.hooks")
    local fc = KoboldHooks.fileChooser()
    if not KoboldHooks.onRefresh(fc, "mybooks", function() self:scheduleReload() end) then return end
    self.unhook = function() KoboldHooks.onRefresh(fc, "mybooks", nil) end
end

-- Reloads once on the next tick, however many refreshes come in together.
function KoboldMyBooks:scheduleReload()
    if self.reload_pending or self.closed then return end
    self.reload_pending = true
    UIManager:nextTick(function()
        self.reload_pending = false
        if not self.closed then self:reload() end
    end)
end

-- Reads the library again and redraws the current view. An open group is
-- found again by its key; if it is gone, the group list is shown instead.
function KoboldMyBooks:reload()
    KoboldLibrary.invalidate()
    self.books = KoboldMyBooksData.getBooks()
    if self.group then
        local key = self.group.key
        self.group = nil
        for _i, g in ipairs(KoboldMyBooksData.getGroups(self.books, self.tab)) do
            if g.key == key then self.group = g break end
        end
        if not self.group then self.page = self.group_page or 1 end
    end
    self:applyList()
    self:refresh()
end

-- Back from a book on a parked screen (session.lua). The file browser was
-- replaced while reading, so the refresh hook moves to the new one; then
-- the list is read again for the new progress and status.
function KoboldMyBooks:onKoboldReturn()
    if self.unhook then self.unhook() self.unhook = nil end
    self:hookFileManager()
    self:scheduleReload()
end

function KoboldMyBooks:onCloseWidget()
    self.closed = true
    if self.unhook then
        self.unhook()
        self.unhook = nil
    end
end

function KoboldMyBooks:onClose()
    UIManager:close(self)
    return true
end

-- The rest of the screen lives in kobold/ui/mybooks/: collections, the list
-- and grid rows, and the Files tab. Each adds its methods to this class.
local shared = {
    COVER_RATIO = COVER_RATIO,
    FILTER_LABELS = FILTER_LABELS,
    SORT_LABELS = SORT_LABELS,
    countText = countText,
    fileChooser = fileChooser,
}
for _i, part in ipairs({ "collections", "rows", "files" }) do
    require("kobold.ui.mybooks." .. part)(KoboldMyBooks, shared)
end

return KoboldMyBooks
