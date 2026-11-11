-- kobold/ui/brightness.lua — Kobold
-- Brightness popup opened from the brightness icon in the status bar, in the
-- e-reader's style: a Brightness slider, a Natural light slider (with an
-- AUTO switch for KOReader's AutoWarmth) on devices that have it, and Night
-- mode. Tap the small or large icon to step, or the track to jump. Tap
-- outside the box to close it.

local Blitbuffer      = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device          = require("device")
local FrameContainer  = require("ui/widget/container/framecontainer")
local Geom            = require("ui/geometry")
local GestureRange    = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan  = require("ui/widget/horizontalspan")
local InputContainer  = require("ui/widget/container/inputcontainer")
local LineWidget      = require("ui/widget/linewidget")
local OverlapGroup    = require("ui/widget/overlapgroup")
local TextWidget      = require("ui/widget/textwidget")
local UIManager       = require("ui/uimanager")
local VerticalGroup   = require("ui/widget/verticalgroup")
local VerticalSpan    = require("ui/widget/verticalspan")
local KoboldPopup     = require("kobold.ui.popup")
local KoboldSwitch    = require("kobold.ui.switch")
local Kit             = require("kobold.ui.popup_kit")
local Widget          = require("ui/widget/widget")
local KoboldWidgets   = require("kobold.ui.widgets")
local _               = require("kobold.l10n")

local Screen = Device.screen

local KoboldBrightness = InputContainer:extend{
    modal = true,
    name = "kobold_brightness",
    kobold_tool = "brightness",
}

-- Sliders for this device. Natural light is added only when the device has it.
-- Brightness starts at 1, because 0 would toggle the frontlight off.
function KoboldBrightness:buildSliders()
    local powerd = Device:getPowerDevice()
    local sliders = {
        {
            title = _("Brightness"), min = math.max(powerd.fl_min, 1), max = powerd.fl_max,
            get = function() return powerd:frontlightIntensity() end,
            set = function(v)
                powerd:setIntensity(v)
                powerd:updateResumeFrontlightState()
            end,
        },
    }
    if Device:hasNaturalLight() then
        sliders[#sliders + 1] = {
            title = _("Natural light"), min = powerd.fl_warmth_min, max = powerd.fl_warmth_max,
            get = function() return powerd:toNativeWarmth(powerd:frontlightWarmth()) end,
            set = function(v) powerd:setWarmth(powerd:fromNativeWarmth(v)) end,
        }
    end
    return sliders
end

-- The slider knob: the ringed circle the switches use (switch.lua).
local Knob = Widget:extend{ d = 0 }
function Knob:getSize() return Geom:new{ w = self.d, h = self.d } end
function Knob:paintTo(bb, x, y) KoboldSwitch.paintKnob(bb, x, y, self.d) end

-- KOReader's AutoWarmth plugin (automatic natural light), when running.
local function autoWarmth()
    local FileManager = package.loaded["apps/filemanager/filemanager"]
    local fm = FileManager and FileManager.instance
    return fm and fm.autowarmth
end

-- One slider, in the e-reader's style: the percentage over the knob, then
-- a small icon (step down), the track (black up to the ringed knob, a thin
-- line after it) and a large icon (step up). Returns a kit row.
function KoboldBrightness:sliderRow(i, inner, icons)
    local s = self.sliders[i]
    local frac = (s.get() - s.min) / math.max(s.max - s.min, 1)
    frac = math.max(0, math.min(1, frac))
    local knob = Screen:scaleBySize(30)
    local icon_w = Screen:scaleBySize(34)
    local row_h = knob + Screen:scaleBySize(4)
    local track_w = inner - 2 * icon_w
    local kx = math.floor(frac * (track_w - knob))
    local thick, thin = Screen:scaleBySize(4), Screen:scaleBySize(1)
    local pct = TextWidget:new{ text = math.floor(frac * 100 + 0.5) .. "%", face = KoboldWidgets.serifFace(14) }
    local pct_x = math.max(0, math.min(inner - pct:getSize().w,
        icon_w + kx + math.floor((knob - pct:getSize().w) / 2)))

    local function line(x, w, h)
        return VerticalGroup:new{ align = "left",
            VerticalSpan:new{ width = math.floor((row_h - h) / 2) },
            HorizontalGroup:new{ HorizontalSpan:new{ width = x },
                LineWidget:new{ dimen = Geom:new{ w = math.max(1, w), h = h }, background = Blitbuffer.COLOR_BLACK } } }
    end
    local track = OverlapGroup:new{
        dimen = Geom:new{ w = track_w, h = row_h },
        line(0, track_w, thin),
        line(0, kx + math.floor(knob / 2), thick),
        VerticalGroup:new{ align = "left",
            VerticalSpan:new{ width = math.floor((row_h - knob) / 2) },
            HorizontalGroup:new{ HorizontalSpan:new{ width = kx }, Knob:new{ d = knob } } },
    }
    local function icon(name, size)
        return CenterContainer:new{ dimen = Geom:new{ w = icon_w, h = row_h },
            KoboldWidgets.customIcon(name, size, "appbar.contrast") }
    end
    local pct_h = pct:getSize().h
    local widget = VerticalGroup:new{
        align = "left",
        HorizontalGroup:new{ HorizontalSpan:new{ width = pct_x }, pct },
        HorizontalGroup:new{
            align = "center",
            icon(icons[1], Screen:scaleBySize(18)), track, icon(icons[2], Screen:scaleBySize(24)),
        },
    }
    -- Kobold Settings > Toolbar > Light steps: percent of the range per tap
    -- on an icon (1% by default), at least one unit.
    local function step(sign)
        local pct_step = tonumber(require("kobold.data.prefs").get("light_step")) or 1
        local unit = math.max(1, math.floor((s.max - s.min) * pct_step / 100 + 0.5))
        self:setValue(i, s.get() + sign * unit)
    end
    return Kit.custom(widget, {
        { rect = Geom:new{ x = 0, y = pct_h, w = icon_w, h = row_h }, on_tap = function() step(-1) end },
        { rect = Geom:new{ x = inner - icon_w, y = pct_h, w = icon_w, h = row_h }, on_tap = function() step(1) end },
        { rect = Geom:new{ x = icon_w, y = pct_h, w = track_w, h = row_h }, on_tap = function(pos, rect)
            local f = math.max(0, math.min(1, (pos.x - rect.x) / rect.w))
            self:setValue(i, s.min + f * (s.max - s.min))
        end },
    })
end

-- The box: Brightness, then Natural light (with AUTO when KOReader's
-- AutoWarmth is running) on devices that have it, then Night mode.
function KoboldBrightness:build()
    local fw = KoboldPopup.width()
    local inner = fw - 2 * (Kit.pad() + Screen:scaleBySize(2))
    local rows = {
        Kit.text(_("Brightness"), 18),
        self:sliderRow(1, inner, { "brightness", "brightness" }),
    }
    if self.sliders[2] then
        rows[#rows + 1] = Kit.line()
        local aw = autoWarmth()
        if aw then
            local on = (tonumber(G_reader_settings:readSetting("autowarmth_activate")) or 0) > 0
            rows[#rows + 1] = Kit.switch(_("Natural light"), on, function() self:toggleAutoWarmth() end, _("AUTO"))
        else
            rows[#rows + 1] = Kit.text(_("Natural light"), 18)
        end
        rows[#rows + 1] = self:sliderRow(2, inner, { "brightness", "moon" })
    end
    rows[#rows + 1] = Kit.line()
    rows[#rows + 1] = Kit.switch(_("Night mode"), G_reader_settings:isTrue("night_mode"),
        function() self:toggleNightMode() end)
    return Kit.build(self, "brightness", rows, fw)
end

-- AUTO: KOReader's AutoWarmth on (the way it was last used, by sun position
-- unless set otherwise) or off.
function KoboldBrightness:toggleAutoWarmth()
    local aw = autoWarmth()
    if not aw or not aw.onAutoWarmthMode then return end
    local prefs = require("kobold.data.prefs")
    local mode = tonumber(G_reader_settings:readSetting("autowarmth_activate")) or 0
    if mode > 0 then
        prefs.set("autowarmth_last", mode)
        pcall(aw.onAutoWarmthMode, aw, 0)
    else
        pcall(aw.onAutoWarmthMode, aw, tonumber(prefs.get("autowarmth_last")) or 1)
    end
    self[1] = self:build()
    UIManager:setDirty(self, function() return "ui", self.frame_dimen end)
end

function KoboldBrightness:init()
    local W, H = Screen:getWidth(), Screen:getHeight()
    self.dimen = Geom:new{ x = 0, y = 0, w = W, h = H }
    self.sliders = self:buildSliders()
    self[1] = self:build()

    if Device:hasKeys() then
        self.key_events = {
            Close = { { Device.input.group.Back } },
        }
    end
    if Device:isTouchDevice() then
        self.ges_events = {
            TapBrightness = {
                GestureRange:new{
                    ges = "tap",
                    range = self.dimen,
                },
            },
        }
    end
end

-- Applies a new value to slider i, then redraws the box with the new position.
function KoboldBrightness:setValue(i, value)
    local s = self.sliders[i]
    value = math.max(s.min, math.min(s.max, math.floor(value + 0.5)))
    s.set(value)
    self.changed = true
    self[1] = self:build()
    UIManager:setDirty(self, function()
        return "ui", self.frame_dimen
    end)
end

-- Taps: the icons step, the track jumps, the switches toggle (popup_kit);
-- outside the box closes it.
function KoboldBrightness:onTapBrightness(_, ges)
    return Kit.tap(self, ges.pos)
end

-- Writes the light level and warmth to KOReader's settings file right away.
-- Changing the light only changes the hardware; KOReader saves it on a clean
-- exit, so after a crash or a forced power-off the next start restored an
-- older level. powerd:saveSettings is KOReader's own save; the keys are
-- written directly when it is missing.
local function saveLight()
    local powerd = Device:getPowerDevice()
    local ok = powerd.saveSettings and pcall(powerd.saveSettings, powerd)
    if not ok and G_reader_settings then
        if powerd.fl_intensity then G_reader_settings:saveSetting("frontlight_intensity", powerd.fl_intensity) end
        if powerd.fl_warmth then G_reader_settings:saveSetting("frontlight_warmth", powerd.fl_warmth) end
    end
    if G_reader_settings and G_reader_settings.flush then
        pcall(G_reader_settings.flush, G_reader_settings)
    end
end

-- KOReader's own night mode toggle (the one in its menu and gestures),
-- sent to the file browser or reader that handles it. It refreshes the
-- whole screen itself; the popup is redrawn with the new state.
function KoboldBrightness:toggleNightMode()
    local Event = require("ui/event")
    local fm = package.loaded["apps/filemanager/filemanager"]
    local rui = package.loaded["apps/reader/readerui"]
    local target = (rui and rui.instance) or (fm and fm.instance)
    if target then
        target:handleEvent(Event:new("ToggleNightMode"))
    else
        UIManager:broadcastEvent(Event:new("ToggleNightMode"))
    end
    self[1] = self:build()
    UIManager:setDirty(self, "ui")
end

function KoboldBrightness:onClose()
    if self.changed then saveLight() end
    KoboldPopup.close(self)
    return true
end

-- Opens the popup. Called from the contrast icon in the status bar.
function KoboldBrightness.show()
    KoboldPopup.show(KoboldBrightness:new{})
end

return KoboldBrightness
