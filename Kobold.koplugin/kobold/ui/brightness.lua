-- kobold/ui/brightness.lua — Kobold
-- Brightness popup opened from the contrast icon in the status bar. It has a
-- frontlight slider, plus a natural light slider only on devices that have one.
-- Tap the minus or plus to step, or tap the track to jump. Tap outside the box
-- to close it.

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
local KoboldWidgets   = require("kobold.ui.widgets")
local _               = require("gettext")

local Screen = Device.screen

local KoboldBrightness = InputContainer:extend{
    modal = true,
    name = "kobold_brightness",
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

-- Builds the popup box and records each slider's touch rectangles, in screen
-- coordinates. The box sits just under the status bar, right-aligned with it.
function KoboldBrightness:build()
    local pad       = Screen:scaleBySize(16)
    local border    = Screen:scaleBySize(2)
    local title_h   = Screen:scaleBySize(30)
    local row_h     = Screen:scaleBySize(44)
    local sec_gap   = Screen:scaleBySize(14)
    local label_w   = Screen:scaleBySize(28)
    local slide_gap = Screen:scaleBySize(10)
    local knob      = Screen:scaleBySize(22)
    local track_h   = Screen:scaleBySize(4)

    local fw    = KoboldPopup.width()
    local inner = fw - 2 * (pad + border)
    local track_w = inner - 2 * (label_w + slide_gap)
    local n  = #self.sliders
    local fh = n * (title_h + row_h) + (n - 1) * sec_gap + 2 * (pad + border)
    local fx, fy = KoboldPopup.origin(fw)
    local x0 = fx + border + pad
    local y0 = fy + border + pad
    self.frame_dimen = Geom:new{ x = fx, y = fy, w = fw, h = fh }
    self.hit = {}

    local function label(text)
        return CenterContainer:new{
            dimen = Geom:new{ w = label_w, h = row_h },
            TextWidget:new{ text = text, face = KoboldWidgets.face(20) },
        }
    end

    local sections = VerticalGroup:new{ align = "left" }
    for i, s in ipairs(self.sliders) do
        local frac = (s.get() - s.min) / math.max(s.max - s.min, 1)
        frac = math.max(0, math.min(1, frac))
        local row_y = y0 + (i - 1) * (title_h + row_h + sec_gap) + title_h

        -- Title row: name on the left, percentage on the right.
        local title = TextWidget:new{ text = s.title, face = KoboldWidgets.face(18) }
        local pct = TextWidget:new{
            text = math.floor(frac * 100 + 0.5) .. "%",
            face = KoboldWidgets.face(14),
            fgcolor = KoboldWidgets.subtitleColor(),
        }
        local gap = math.max(0, inner - title:getSize().w - pct:getSize().w)
        sections[#sections + 1] = KoboldWidgets.fixed(inner, title_h,
            HorizontalGroup:new{ title, HorizontalSpan:new{ width = gap }, pct })

        -- Slider row: grey track, black fill up to the knob, and a black knob.
        local kx = math.max(0, math.min(track_w - knob,
            math.floor(frac * track_w) - math.floor(knob / 2)))
        local fill_w = math.max(1, kx + math.floor(knob / 2))
        local track = OverlapGroup:new{
            dimen = Geom:new{ w = track_w, h = row_h },
            VerticalGroup:new{
                align = "left",
                VerticalSpan:new{ width = math.floor((row_h - track_h) / 2) },
                LineWidget:new{ dimen = Geom:new{ w = track_w, h = track_h }, background = Blitbuffer.COLOR_LIGHT_GRAY },
            },
            VerticalGroup:new{
                align = "left",
                VerticalSpan:new{ width = math.floor((row_h - track_h) / 2) },
                LineWidget:new{ dimen = Geom:new{ w = fill_w, h = track_h }, background = Blitbuffer.COLOR_BLACK },
            },
            VerticalGroup:new{
                align = "left",
                VerticalSpan:new{ width = math.floor((row_h - knob) / 2) },
                HorizontalGroup:new{
                    HorizontalSpan:new{ width = kx },
                    FrameContainer:new{
                        width = knob, height = knob, bordersize = 0, padding = 0,
                        radius = math.floor(knob / 2), background = Blitbuffer.COLOR_BLACK,
                        HorizontalSpan:new{ width = knob },
                    },
                },
            },
        }
        sections[#sections + 1] = HorizontalGroup:new{
            label("-"), HorizontalSpan:new{ width = slide_gap }, track,
            HorizontalSpan:new{ width = slide_gap }, label("+"),
        }
        if i < n then sections[#sections + 1] = VerticalSpan:new{ width = sec_gap } end

        self.hit[i] = {
            minus = Geom:new{ x = x0, y = row_y, w = label_w, h = row_h },
            plus  = Geom:new{ x = x0 + inner - label_w, y = row_y, w = label_w, h = row_h },
            track = Geom:new{ x = x0 + label_w + slide_gap, y = row_y, w = track_w, h = row_h },
        }
    end

    local box = FrameContainer:new{
        width = fw, bordersize = border, padding = pad,
        radius = KoboldPopup.radius(),
        background = Blitbuffer.COLOR_WHITE,
        sections,
    }
    return KoboldPopup.place(self.dimen, fx, fy, box)
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

-- Taps on -/+ step by a tenth of the range. Taps on the track jump to that point.
-- Taps outside the box close the popup. Taps inside the box but off a control do nothing.
function KoboldBrightness:onTapBrightness(_, ges)
    local pos = ges.pos
    if not pos:intersectWith(self.frame_dimen) then
        self:onClose()
        return true
    end
    for i, s in ipairs(self.sliders) do
        local hit = self.hit[i]
        if hit then
            local step = math.max(1, math.floor((s.max - s.min) / 10 + 0.5))
            local current = s.get()
            if pos:intersectWith(hit.minus) then
                self:setValue(i, current - step)
                return true
            elseif pos:intersectWith(hit.plus) then
                self:setValue(i, current + step)
                return true
            elseif pos:intersectWith(hit.track) then
                local frac = (pos.x - hit.track.x) / hit.track.w
                frac = math.max(0, math.min(1, frac))
                self:setValue(i, s.min + frac * (s.max - s.min))
                return true
            end
        end
    end
    return true
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
