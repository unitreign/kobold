-- kobold/ui/clock_popup.lua — Kobold
-- Clock popup, opened by tapping the time in the status bar. Left-aligned
-- under the bar, in the same box style as the other popups, with a switch
-- for 24-hour time. Until it is used, the clock follows KOReader's setting.

local Blitbuffer      = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device          = require("device")
local Event           = require("ui/event")
local FrameContainer  = require("ui/widget/container/framecontainer")
local Geom            = require("ui/geometry")
local GestureRange    = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan  = require("ui/widget/horizontalspan")
local InputContainer  = require("ui/widget/container/inputcontainer")
local TextWidget      = require("ui/widget/textwidget")
local UIManager       = require("ui/uimanager")
local VerticalGroup   = require("ui/widget/verticalgroup")
local VerticalSpan    = require("ui/widget/verticalspan")
local _               = require("gettext")
local KoboldPrefs     = require("kobold.data.prefs")
local KoboldPopup     = require("kobold.ui.popup")
local KoboldWidgets   = require("kobold.ui.widgets")

local Screen = Device.screen

local KoboldClockPopup = InputContainer:extend{
    modal = true,
    name = "kobold_clock",
}

function KoboldClockPopup:build()
    local pad, border = Screen:scaleBySize(16), Screen:scaleBySize(2)
    local row_h = Screen:scaleBySize(40)
    local gap = Screen:scaleBySize(6)
    local fw = KoboldPopup.width()
    local inner = fw - 2 * (pad + border)
    local fx, fy = KoboldPopup.originLeft()

    local on = KoboldWidgets.clock24()
    local sw_w, sw_h = Screen:scaleBySize(64), Screen:scaleBySize(30)
    local switch = FrameContainer:new{
        bordersize = Screen:scaleBySize(2), padding = 0,
        radius = math.floor(sw_h / 2),
        background = on and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_WHITE,
        CenterContainer:new{
            dimen = Geom:new{ w = sw_w - Screen:scaleBySize(4), h = sw_h - Screen:scaleBySize(4) },
            TextWidget:new{
                text = on and _("On") or _("Off"), face = KoboldWidgets.face(14), bold = true,
                fgcolor = on and Blitbuffer.COLOR_WHITE or Blitbuffer.COLOR_BLACK,
            },
        },
    }
    local time = TextWidget:new{ text = KoboldWidgets.clockText(), face = KoboldWidgets.face(30), bold = true }
    local label = TextWidget:new{ text = _("24-hour clock"), face = KoboldWidgets.face(18) }
    local content = VerticalGroup:new{
        align = "left",
        time,
        VerticalSpan:new{ width = gap },
        KoboldWidgets.fixed(inner, row_h, HorizontalGroup:new{
            align = "center",
            label,
            HorizontalSpan:new{ width = math.max(0, inner - label:getSize().w - sw_w) },
            switch,
        }),
    }
    local box = FrameContainer:new{
        bordersize = border, padding = pad,
        radius = KoboldPopup.radius(),
        background = Blitbuffer.COLOR_WHITE,
        content,
    }
    local fh = box:getSize().h
    self.frame_dimen = Geom:new{ x = fx, y = fy, w = fw, h = fh }
    self.switch_rect = Geom:new{
        x = fx + border + pad, y = fy + border + pad + time:getSize().h + gap,
        w = inner, h = row_h,
    }
    return KoboldPopup.place(self.dimen, fx, fy, box, KoboldPopup.anchor("clock"))
end

function KoboldClockPopup:init()
    local W, H = Screen:getWidth(), Screen:getHeight()
    self.dimen = Geom:new{ x = 0, y = 0, w = W, h = H }
    self[1] = self:build()
    if Device:hasKeys() then
        self.key_events = { Close = { { Device.input.group.Back } } }
    end
    if Device:isTouchDevice() then
        self.ges_events = {
            TapClock = { GestureRange:new{ ges = "tap", range = self.dimen } },
        }
    end
end

function KoboldClockPopup:onTapClock(_, ges)
    if not ges.pos:intersectWith(self.frame_dimen) then return self:onClose() end
    if ges.pos:intersectWith(self.switch_rect) then
        KoboldPrefs.set("clock_24h", not KoboldWidgets.clock24())
        -- Open Kobold screens redraw their status bar with the new format.
        UIManager:broadcastEvent(Event:new("KoboldSettingsChanged"))
        self[1] = self:build()
        UIManager:setDirty(self, function() return "ui", self.frame_dimen end)
    end
    return true
end

function KoboldClockPopup:onClose()
    KoboldPopup.close(self)
    return true
end

function KoboldClockPopup.show()
    KoboldPopup.show(KoboldClockPopup:new{})
end

return KoboldClockPopup
