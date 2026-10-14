-- kobold/ui/stats_settings.lua — Kobold
-- Popup for the Home reading stats, opened from Kobold Settings. Each of the
-- two lines is a preset stat or custom text, with its own tap action; the
-- label under them can be changed too, and everything reset at once.
--
-- Not modal: its editors (choice lists, keyboard, the action list) must open
-- on top of it, and KOReader puts non-modal widgets under modal ones.

local Blitbuffer      = require("ffi/blitbuffer")
local Device          = require("device")
local FrameContainer  = require("ui/widget/container/framecontainer")
local Geom            = require("ui/geometry")
local GestureRange    = require("ui/gesturerange")
local InputContainer  = require("ui/widget/container/inputcontainer")
local TextWidget      = require("ui/widget/textwidget")
local UIManager       = require("ui/uimanager")
local VerticalGroup   = require("ui/widget/verticalgroup")
local _               = require("gettext")
local KoboldPrefs     = require("kobold.data.prefs")
local KoboldStats     = require("kobold.data.stats")
local KoboldActions   = require("kobold.ui.actions")
local KoboldEditors   = require("kobold.ui.editors")
local KoboldPopup     = require("kobold.ui.popup")
local KoboldSettingsList = require("kobold.ui.settings_list")
local KoboldWidgets   = require("kobold.ui.widgets")

local Screen = Device.screen

local DEFAULT_LABEL = "Reading Stats"

local KoboldStatsSettings = InputContainer:extend{
    name = "kobold_stats_settings",
    under = nil,    -- the settings screen below, redrawn when this changes
    on_close = nil, -- called once this popup closes
}

local function statLabel(id)
    local line = KoboldStats.line(id)
    return line and line.label or tostring(id)
end

-- Rows for one stats line ("stats_line1" or "stats_line2").
function KoboldStatsSettings:lineRows(pref, section)
    local is_text = KoboldPrefs.get(pref .. "_kind") == "text"
    local rows = {
        { section = section },
        {
            title = _("Shows"),
            value = is_text and _("Custom text") or _("A reading stat"),
            on_tap = function()
                KoboldEditors.choose(_("Shows"), {
                    { id = "stat", label = _("A reading stat") },
                    { id = "text", label = _("Custom text") },
                }, is_text and "text" or "stat",
                function(id) KoboldPrefs.set(pref .. "_kind", id) end,
                function() self:refresh() end)
            end,
        },
    }
    if is_text then
        local text = KoboldPrefs.get(pref .. "_text")
        rows[#rows + 1] = {
            title = _("Text"),
            value = text ~= "" and text or _("(empty)"),
            on_tap = function()
                KoboldEditors.text(_("Line text"), nil, text,
                    function(t) KoboldPrefs.set(pref .. "_text", t) end,
                    function() self:refresh() end)
            end,
        }
    else
        rows[#rows + 1] = {
            title = _("Stat"),
            value = statLabel(KoboldPrefs.get(pref)),
            on_tap = function()
                local choices = {}
                for _i, line in ipairs(KoboldStats.LINES) do
                    choices[#choices + 1] = { id = line.id, label = line.label }
                end
                KoboldEditors.choose(_("Stat"), choices, KoboldPrefs.get(pref),
                    function(id) KoboldPrefs.set(pref, id) end,
                    function() self:refresh() end)
            end,
        }
    end
    rows[#rows + 1] = {
        title = _("Tap action"),
        value = KoboldActions.title(KoboldPrefs.get(pref .. "_action")),
        on_tap = function()
            KoboldEditors.action(_("Tap action"), KoboldPrefs.get(pref .. "_action"),
                function(id) KoboldPrefs.set(pref .. "_action", id) end,
                function() self:refresh() end)
        end,
    }
    return rows
end

function KoboldStatsSettings:spec()
    local spec = {}
    local function append(rows) for _i, r in ipairs(rows) do spec[#spec + 1] = r end end
    append(self:lineRows("stats_line1", _("First line")))
    append(self:lineRows("stats_line2", _("Second line, when the book title takes two lines")))
    append({
        { section = _("Label") },
        {
            title = _("Text under the stats"),
            value = KoboldPrefs.get("stats_label") or DEFAULT_LABEL,
            on_tap = function()
                KoboldEditors.text(_("Label"), _("Leave empty for the default."),
                    KoboldPrefs.get("stats_label") or DEFAULT_LABEL,
                    function(t)
                        KoboldPrefs.set("stats_label", t ~= "" and t ~= DEFAULT_LABEL and t or nil)
                    end,
                    function() self:refresh() end)
            end,
        },
        { section = "" },
        {
            title = _("Reset reading stats"),
            desc = _("Put both lines, their actions and the label back to the defaults."),
            value = _("Reset"), action = true,
            on_tap = function()
                KoboldEditors.confirm(_("Reset the reading stats settings?"), _("Reset"),
                    function() KoboldPrefs.reset(KoboldPrefs.STATS_KEYS) end,
                    function() self:refresh() end)
            end,
        },
    })
    return spec
end

-- The box, centred on the screen: a title, the settings list, and tap
-- rectangles for its rows (self.hits).
function KoboldStatsSettings:build()
    local W, H = Screen:getWidth(), Screen:getHeight()
    local pad    = Screen:scaleBySize(18)
    local border = Screen:scaleBySize(2)
    local fw     = math.floor(W * 0.88)
    local inner  = fw - 2 * (pad + border)
    local title_h = Screen:scaleBySize(40)

    -- Height is only known after building, so build once to measure, then
    -- again at the final position for the right tap rectangles.
    local function layout(fy)
        local list, hits = KoboldSettingsList.build(self:spec(), 0, 0, inner)
        local fx = math.floor((W - fw) / 2)
        local x0, y0 = fx + border + pad, fy + border + pad + title_h
        for _i, h in ipairs(hits) do
            h.rect.x, h.rect.y = h.rect.x + x0, h.rect.y + y0
        end
        local box = FrameContainer:new{
            bordersize = border, padding = pad,
            radius = KoboldPopup.radius(),
            background = Blitbuffer.COLOR_WHITE,
            VerticalGroup:new{
                align = "left",
                KoboldWidgets.fixed(inner, title_h, TextWidget:new{
                    text = _("Reading stats"), face = KoboldWidgets.face(20), bold = true,
                }),
                list,
            },
        }
        return box, hits, fx
    end
    local probe = layout(0)
    local fh = probe:getSize().h
    local fy = math.max(0, math.floor((H - fh) / 2))
    local box, hits, fx = layout(fy)
    self.hits = hits
    self.frame_dimen = Geom:new{ x = fx, y = fy, w = fw, h = fh }
    return KoboldPopup.place(self.dimen, fx, fy, box)
end

function KoboldStatsSettings:init()
    local W, H = Screen:getWidth(), Screen:getHeight()
    self.dimen = Geom:new{ x = 0, y = 0, w = W, h = H }
    self[1] = self:build()
    if Device:hasKeys() then
        self.key_events = { Close = { { Device.input.group.Back } } }
    end
    if Device:isTouchDevice() then
        self.ges_events = {
            TapStats = { GestureRange:new{ ges = "tap", range = self.dimen } },
        }
    end
end

-- Redraws with the current values. The screen below is redrawn too, since
-- the box may have changed height.
function KoboldStatsSettings:refresh()
    if self.closed then return end
    self[1] = self:build()
    if self.under then UIManager:setDirty(self.under, "ui") end
    UIManager:setDirty(self, "ui")
end

-- Taps on a row open its editor; taps outside the box close the popup.
function KoboldStatsSettings:onTapStats(_, ges)
    if not ges.pos:intersectWith(self.frame_dimen) then
        self:onClose()
        return true
    end
    local on_tap = KoboldSettingsList.hit(self.hits, ges.pos)
    if on_tap then on_tap() end
    return true
end

function KoboldStatsSettings:onClose()
    self.closed = true
    UIManager:close(self, "ui", self.frame_dimen)
    if self.on_close then self.on_close() end
    return true
end

-- Opens the popup above `under` (the settings screen); on_close runs after.
function KoboldStatsSettings.show(under, on_close)
    UIManager:show(KoboldStatsSettings:new{ under = under, on_close = on_close })
end

return KoboldStatsSettings
