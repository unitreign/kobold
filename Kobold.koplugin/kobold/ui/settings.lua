-- kobold/ui/settings.lua — Kobold
-- Kobold Settings, opened from the More tab: a full-screen page in the style
-- of the e-reader's own settings. "Settings" and a close button at the top,
-- the page heading, then sections of rows. Tapping a row opens its editor;
-- the page redraws with the new value afterwards.

local Blitbuffer      = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device          = require("device")
local Event           = require("ui/event")
local FrameContainer  = require("ui/widget/container/framecontainer")
local Geom            = require("ui/geometry")
local InfoMessage     = require("ui/widget/infomessage")
local HorizontalSpan  = require("ui/widget/horizontalspan")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local InputContainer  = require("ui/widget/container/inputcontainer")
local LeftContainer   = require("ui/widget/container/leftcontainer")
local OverlapGroup    = require("ui/widget/overlapgroup")
local RightContainer  = require("ui/widget/container/rightcontainer")
local TextWidget      = require("ui/widget/textwidget")
local UIManager       = require("ui/uimanager")
local VerticalGroup   = require("ui/widget/verticalgroup")
local VerticalSpan    = require("ui/widget/verticalspan")
local _               = require("gettext")
local KoboldCovers    = require("kobold.data.covers")
local KoboldLibrary   = require("kobold.data.library")
local KoboldPrefs     = require("kobold.data.prefs")
local KoboldPopup     = require("kobold.ui.popup")
local KoboldEditors   = require("kobold.ui.editors")
local KoboldSettingsList = require("kobold.ui.settings_list")
local KoboldStatsSettings = require("kobold.ui.stats_settings")
local KoboldTaps      = require("kobold.ui.taps")
local KoboldWidgets   = require("kobold.ui.widgets")

local Screen = Device.screen

local BATTERY_LABELS = { fill = _("Fill"), percent = _("Percentage") }
local TAP_LABELS = { koreader = _("KOReader default"), single = _("Single tap"), double = _("Double tap") }

local KoboldSettings = InputContainer:extend{
    -- Not modal: its editors and the stats popup open on top of it.
    -- A panel over the screen it was opened from, not a full screen.
    name = "kobold_settings",
}

-- Open Kobold screens redraw their status bar (the battery style changed).
local function broadcastChange()
    UIManager:broadcastEvent(Event:new("KoboldSettingsChanged"))
end

local function prepareCovers()
    local files = {}
    for i, book in ipairs(KoboldLibrary.scan()) do files[i] = book.file end
    local n = KoboldCovers.prepareAll(files)
    local text
    if n == nil then
        text = _("Covers cannot be prepared right now. The cover browser is busy or not enabled.")
    elseif n == 0 then
        text = _("Every book already has its cover.")
    else
        text = string.format(_("Preparing %d covers in the background."), n)
    end
    UIManager:show(InfoMessage:new{ text = text })
end

function KoboldSettings:spec()
    local done = function() self:refresh() end
    return {
        { section = _("Home") },
        {
            title = _("Reading stats"),
            desc = _("What the stats next to Continue Reading show, and what tapping them opens."),
            value = _("Edit"), action = true,
            on_tap = function() KoboldStatsSettings.show(self, done) end,
        },
        { section = _("My Books") },
        {
            title = _("Books per page"),
            desc = _("Rows on lists with covers: Books, Series, and the books of an author, series or collection."),
            value = tostring(KoboldPrefs.coverRows()),
            on_tap = function()
                KoboldEditors.number({
                    title = _("Books per page"),
                    value = KoboldPrefs.coverRows(),
                    min = KoboldPrefs.COVER_ROWS_MIN,
                    max = KoboldPrefs.COVER_ROWS_MAX,
                    default = 5,
                }, function(v) KoboldPrefs.set("cover_rows", v) end, done)
            end,
        },
        {
            title = _("Book menu"),
            desc = _("What the \"...\" on a book (and holding a book on Home) opens: Kobold's menu with Read now and View Details, or KOReader's book menu directly."),
            value = KoboldPrefs.get("book_menu") == "koreader" and _("KOReader") or _("Kobold"),
            on_tap = function()
                KoboldEditors.choose(_("Book menu"), {
                    { id = "kobold", label = _("Kobold") },
                    { id = "koreader", label = _("KOReader") },
                }, KoboldPrefs.get("book_menu") == "koreader" and "koreader" or "kobold", function(id)
                    KoboldPrefs.set("book_menu", id == "koreader" and "koreader" or nil)
                end, done)
            end,
        },
        {
            title = _("Open books with"),
            desc = _("How many taps open a book. KOReader default follows the browser double tap patch when it is installed, otherwise a single tap."),
            value = TAP_LABELS[KoboldPrefs.get("open_tap")] or TAP_LABELS.koreader,
            on_tap = function()
                KoboldEditors.choose(_("Open books with"), {
                    { id = "koreader", label = TAP_LABELS.koreader },
                    { id = "single", label = TAP_LABELS.single },
                    { id = "double", label = TAP_LABELS.double },
                }, KoboldPrefs.get("open_tap"), function(id)
                    KoboldPrefs.set("open_tap", id ~= "koreader" and id or nil)
                end, done)
            end,
        },
        {
            title = _("Opening and closing panel"),
            desc = _("Kobold's own \"Opening Book\" and \"Closing Book\" panel instead of KOReader's messages. Off: the same as KOReader."),
            value = KoboldPrefs.get("transition") == true and _("On") or _("Off"),
            on_tap = function()
                KoboldPrefs.set("transition", KoboldPrefs.get("transition") ~= true or nil)
                done()
            end,
        },
        {
            title = _("Files tab"),
            desc = _("A file browser tab in My Books, starting in your home folder. Hold a folder for its options."),
            value = KoboldPrefs.get("files_tab") and _("On") or _("Off"),
            on_tap = function()
                KoboldPrefs.set("files_tab", not KoboldPrefs.get("files_tab") or nil)
                done()
            end,
        },
        { section = _("Look") },
        {
            title = _("Icons"),
            desc = _("Kobold's own icons for the status bar and nav bar, or KOReader's default icons."),
            value = KoboldPrefs.get("icons") == "koreader" and _("KOReader") or _("Kobold"),
            on_tap = function()
                KoboldEditors.choose(_("Icons"), {
                    { id = "kobold", label = _("Kobold") },
                    { id = "koreader", label = _("KOReader") },
                }, KoboldPrefs.get("icons") == "koreader" and "koreader" or "kobold", function(id)
                    KoboldPrefs.set("icons", id == "koreader" and "koreader" or nil)
                    UIManager:broadcastEvent(Event:new("KoboldIconsChanged"))
                end, done)
            end,
        },
        { section = _("Toolbar") },
        {
            title = _("Search"),
            desc = _("What the search icon opens: Kobold's search page, or KOReader's file search."),
            value = KoboldPrefs.get("search") == "koreader" and _("KOReader") or _("Kobold"),
            on_tap = function()
                KoboldEditors.choose(_("Search"), {
                    { id = "kobold", label = _("Kobold") },
                    { id = "koreader", label = _("KOReader") },
                }, KoboldPrefs.get("search") == "koreader" and "koreader" or "kobold", function(id)
                    KoboldPrefs.set("search", id == "koreader" and "koreader" or nil)
                end, done)
            end,
        },
        {
            title = _("Light steps"),
            desc = _("How much each - or + tap changes brightness and natural light, in percent."),
            value = tostring(tonumber(KoboldPrefs.get("light_step")) or 1) .. "%",
            on_tap = function()
                KoboldEditors.number({
                    title = _("Light steps"),
                    value = tonumber(KoboldPrefs.get("light_step")) or 1,
                    min = 1, max = 20, default = 1,
                    info = _("Percent of the range per tap."),
                }, function(v) KoboldPrefs.set("light_step", v ~= 1 and v or nil) end, done)
            end,
        },
        { section = _("Status bar") },
        {
            title = _("Battery"),
            desc = _("Show the charge as a fill inside the icon, or as a number."),
            value = BATTERY_LABELS[KoboldPrefs.get("battery")] or BATTERY_LABELS.fill,
            on_tap = function()
                KoboldEditors.choose(_("Battery"), {
                    { id = "fill", label = BATTERY_LABELS.fill },
                    { id = "percent", label = BATTERY_LABELS.percent },
                }, KoboldPrefs.get("battery"), function(id)
                    KoboldPrefs.set("battery", id)
                    broadcastChange()
                end, done)
            end,
        },
        { section = _("Covers") },
        {
            title = _("Prepare covers"),
            desc = _("Read the cover of every book that has none yet, in the background. Can take several minutes."),
            value = _("Start"), action = true,
            on_tap = function()
                KoboldEditors.confirm(_("Prepare covers for all books now?"), _("Start"), prepareCovers)
            end,
        },
        { section = _("Reset") },
        {
            title = _("Reset to defaults"),
            desc = _("Put every Kobold setting back as it was when first installed."),
            value = _("Reset"), action = true,
            on_tap = function()
                KoboldEditors.confirm(_("Reset all Kobold settings?"), _("Reset"), function()
                    KoboldPrefs.resetAll()
                    broadcastChange()
                    UIManager:broadcastEvent(Event:new("KoboldIconsChanged"))
                end, done)
            end,
        },
    }
end

-- The panel: a bordered box inset from the screen edges, like the
-- e-reader's settings. The screen it was opened from shows around it.
function KoboldSettings:build()
    local R = KoboldPopup.panelRect()
    local border    = Screen:scaleBySize(2)
    local pad       = Screen:scaleBySize(20)
    local inner_w   = R.w - 2 * (border + pad)
    local inner_h   = R.h - 2 * (border + pad)
    local x0, y0    = R.x + border + pad, R.y + border + pad
    local top_h     = Screen:scaleBySize(40)
    local head_h    = Screen:scaleBySize(8)   -- small gap under the top bar
    local close_sz  = Screen:scaleBySize(26)
    local bar_w     = Screen:scaleBySize(24)
    local bar_gap   = Screen:scaleBySize(12)

    -- Pages that fit the panel; page_starts holds each page's first item.
    -- With one page the rows use the full width, the same padding on both
    -- sides; with more, the side bar takes the right edge.
    local list_y = y0 + top_h + head_h
    local max_h  = inner_h - top_h - head_h
    local spec = self:spec()
    local list_w
    local function paginate(w)
        local starts = { 1 }
        while true do
            local _l, _h, nxt = KoboldSettingsList.build(spec, x0, list_y, w,
                { from = starts[#starts], max_h = max_h })
            if not nxt then break end
            starts[#starts + 1] = nxt
        end
        return starts
    end
    self.page_starts = paginate(inner_w)
    list_w = inner_w
    if #self.page_starts > 1 then
        list_w = inner_w - bar_w - bar_gap
        self.page_starts = paginate(list_w)
    end
    self.pages = #self.page_starts
    self.page = math.max(1, math.min(self.page or 1, self.pages))
    local list, hits = KoboldSettingsList.build(spec, x0, list_y, list_w,
        { from = self.page_starts[self.page], max_h = max_h })
    self.hits = hits

    self.bar = { w = bar_w, h = max_h, page = self.page, pages = self.pages, arrow = Screen:scaleBySize(22) }
    self.bar_rect = Geom:new{ x = x0 + list_w, y = list_y, w = bar_w + bar_gap + pad, h = max_h }
    self.close_rect = Geom:new{ x = x0 + inner_w - close_sz - pad, y = R.y, w = close_sz + 2 * pad, h = top_h + pad }
    self.panel_rect = R

    local page_label = TextWidget:new{
        text = self.pages > 1 and string.format(_("Page %d of %d"), self.page, self.pages) or "",
        face = KoboldWidgets.face(14), fgcolor = KoboldWidgets.subtitleColor(),
    }
    local panel = FrameContainer:new{
        bordersize = border, padding = pad,
        radius = KoboldPopup.radius(),
        background = Blitbuffer.COLOR_WHITE,
        VerticalGroup:new{
            align = "left",
            -- Top bar: the page on the left, the title in the middle and a
            -- close button.
            OverlapGroup:new{
                dimen = Geom:new{ w = inner_w, h = top_h },
                LeftContainer:new{ dimen = Geom:new{ w = inner_w, h = top_h }, page_label },
                CenterContainer:new{
                    dimen = Geom:new{ w = inner_w, h = top_h },
                    TextWidget:new{ text = _("Settings"), face = KoboldWidgets.face(18) },
                },
                RightContainer:new{
                    dimen = Geom:new{ w = inner_w, h = top_h },
                    KoboldWidgets.icon("close", close_sz),
                },
            },
            VerticalSpan:new{ width = head_h },
            self.pages > 1 and HorizontalGroup:new{
                align = "top",
                KoboldWidgets.fixed(list_w, max_h, list),
                HorizontalSpan:new{ width = bar_gap },
                KoboldWidgets.pageBar(self.bar),
            } or KoboldWidgets.fixed(list_w, max_h, list),
        },
    }
    return KoboldPopup.place(self.dimen, R.x, R.y, panel)
end

function KoboldSettings:goToPage(page)
    page = math.max(1, math.min(self.pages or 1, page))
    if page == self.page then return end
    self.page = page
    self:refresh()
end

function KoboldSettings:onSettingsNextPage() self:goToPage(self.page + 1) return true end
function KoboldSettings:onSettingsPrevPage() self:goToPage(self.page - 1) return true end

function KoboldSettings:init()
    local W, H = Screen:getWidth(), Screen:getHeight()
    self.dimen = Geom:new{ x = 0, y = 0, w = W, h = H }
    if Device:hasKeys() then
        self.key_events = {
            Close = { { Device.input.group.Back } },
            SettingsNextPage = { { Device.input.group.PgFwd } },
            SettingsPrevPage = { { Device.input.group.PgBack } },
        }
    end
    self.start_revision = KoboldPrefs.revision()
    self[1] = self:build()
    -- One tap zone for the page; the handler finds the row or close button.
    KoboldTaps.add(self, "KoboldSettingsTap", 0, 0, W, H, function(ges)
        if ges.pos:intersectWith(self.close_rect) then
            self:onClose()
            return
        end
        if self.pages > 1 and ges.pos:intersectWith(self.bar_rect) then
            local page = KoboldWidgets.pageBarTarget(ges.pos.y - self.bar_rect.y, self.bar)
            if page then self:goToPage(page) end
            return
        end
        local on_tap = KoboldSettingsList.hit(self.hits, ges.pos)
        if on_tap then on_tap() end
    end)
    -- Swipe up for the next page, down for the previous one.
    self:registerTouchZones({
        {
            id = "KoboldSettingsSwipe",
            ges = "swipe",
            screen_zone = { ratio_x = 0, ratio_y = 0, ratio_w = 1, ratio_h = 1 },
            handler = function(ges)
                if ges.direction == "north" then
                    self:goToPage(self.page + 1)
                elseif ges.direction == "south" then
                    self:goToPage(self.page - 1)
                else
                    return false
                end
                return true
            end,
        },
    })
end

function KoboldSettings:refresh()
    if self.closed then return end
    self[1] = self:build()
    UIManager:setDirty(self, function() return "ui", self.panel_rect end)
end

-- Closing after a change refreshes the screen below in full, clearing what
-- the quick redraws of the rows and popups left behind.
function KoboldSettings:onClose()
    self.closed = true
    if KoboldPrefs.revision() ~= self.start_revision then
        UIManager:close(self, "full")
    else
        UIManager:close(self, "ui", self.panel_rect)
    end
    return true
end

function KoboldSettings.show()
    local w = KoboldSettings:new{}
    UIManager:show(w, "ui", w.panel_rect)
end

return KoboldSettings
