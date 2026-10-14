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
local InputContainer  = require("ui/widget/container/inputcontainer")
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
local KoboldEditors   = require("kobold.ui.editors")
local KoboldSettingsList = require("kobold.ui.settings_list")
local KoboldStatsSettings = require("kobold.ui.stats_settings")
local KoboldTaps      = require("kobold.ui.taps")
local KoboldWidgets   = require("kobold.ui.widgets")

local Screen = Device.screen

local BATTERY_LABELS = { fill = _("Fill"), percent = _("Percentage") }

local KoboldSettings = InputContainer:extend{
    -- Not modal: its editors and the stats popup open on top of it.
    covers_fullscreen = true,
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
                end, done)
            end,
        },
    }
end

function KoboldSettings:build()
    local W, H = Screen:getWidth(), Screen:getHeight()
    local margin    = Screen:scaleBySize(30)
    local content_w = W - 2 * margin
    local top_h     = Screen:scaleBySize(44)
    local head_gap  = Screen:scaleBySize(10)
    local head_h    = Screen:scaleBySize(48)
    local close_sz  = Screen:scaleBySize(28)

    local list_y = margin + top_h + head_gap + head_h
    local list, hits = KoboldSettingsList.build(self:spec(), margin, list_y, content_w)
    self.hits = hits
    self.close_rect = Geom:new{
        x = margin + content_w - close_sz - Screen:scaleBySize(10), y = margin - Screen:scaleBySize(10),
        w = close_sz + Screen:scaleBySize(20), h = top_h + Screen:scaleBySize(10),
    }

    return FrameContainer:new{
        width = W, height = H, bordersize = 0, padding = 0,
        background = Blitbuffer.COLOR_WHITE,
        OverlapGroup:new{
            dimen = Geom:new{ w = W, h = H },
            FrameContainer:new{
                bordersize = 0, padding = margin, padding_bottom = 0,
                VerticalGroup:new{
                    align = "left",
                    -- Top bar: small centred title and a close button.
                    OverlapGroup:new{
                        dimen = Geom:new{ w = content_w, h = top_h },
                        CenterContainer:new{
                            dimen = Geom:new{ w = content_w, h = top_h },
                            TextWidget:new{ text = _("Settings"), face = KoboldWidgets.face(15) },
                        },
                        RightContainer:new{
                            dimen = Geom:new{ w = content_w, h = top_h },
                            KoboldWidgets.icon("close", close_sz),
                        },
                    },
                    VerticalSpan:new{ width = head_gap },
                    KoboldWidgets.fixed(content_w, head_h, TextWidget:new{
                        text = _("Kobold Settings"), face = KoboldWidgets.face(26),
                    }),
                    list,
                },
            },
        },
    }
end

function KoboldSettings:init()
    local W, H = Screen:getWidth(), Screen:getHeight()
    self.dimen = Geom:new{ x = 0, y = 0, w = W, h = H }
    if Device:hasKeys() then
        self.key_events = { Close = { { Device.input.group.Back } } }
    end
    self.start_revision = KoboldPrefs.revision()
    self[1] = self:build()
    -- One tap zone for the page; the handler finds the row or close button.
    KoboldTaps.add(self, "KoboldSettingsTap", 0, 0, W, H, function(ges)
        if ges.pos:intersectWith(self.close_rect) then
            self:onClose()
            return
        end
        local on_tap = KoboldSettingsList.hit(self.hits, ges.pos)
        if on_tap then on_tap() end
    end)
end

function KoboldSettings:refresh()
    if self.closed then return end
    self[1] = self:build()
    UIManager:setDirty(self, "ui")
end

-- Closing after a change refreshes the screen below in full, clearing what
-- the quick redraws of the rows and popups left behind.
function KoboldSettings:onClose()
    self.closed = true
    if KoboldPrefs.revision() ~= self.start_revision then
        UIManager:close(self, "full")
    else
        UIManager:close(self)
    end
    return true
end

function KoboldSettings.show()
    UIManager:show(KoboldSettings:new{})
end

return KoboldSettings
