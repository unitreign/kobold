-- kobold/ui/battery_popup.lua — Kobold
-- Battery popup opened from the battery icon in the status bar, in the same
-- box style as the brightness and Wi-Fi popups: the charge in large type and
-- whether the device is charging. Tap anywhere to close it.

local Blitbuffer      = require("ffi/blitbuffer")
local Device          = require("device")
local FrameContainer  = require("ui/widget/container/framecontainer")
local Geom            = require("ui/geometry")
local GestureRange    = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan  = require("ui/widget/horizontalspan")
local InputContainer  = require("ui/widget/container/inputcontainer")
local TextWidget      = require("ui/widget/textwidget")
local VerticalGroup   = require("ui/widget/verticalgroup")
local VerticalSpan    = require("ui/widget/verticalspan")
local _               = require("gettext")
local KoboldBattery   = require("kobold.ui.battery")
local KoboldPopup     = require("kobold.ui.popup")
local KoboldWidgets   = require("kobold.ui.widgets")

local Screen = Device.screen

local KoboldBatteryPopup = InputContainer:extend{
    modal = true,
    name = "kobold_battery",
}

function KoboldBatteryPopup:build()
    local pad     = Screen:scaleBySize(16)
    local border  = Screen:scaleBySize(2)
    local title_h = Screen:scaleBySize(30)
    local gap     = Screen:scaleBySize(6)

    local fw    = KoboldPopup.width()
    local inner = fw - 2 * (pad + border)
    local fx, fy = KoboldPopup.origin(fw)

    local level, charging = KoboldBattery.state()
    local title = TextWidget:new{ text = _("Battery"), face = KoboldWidgets.face(18) }
    local state = TextWidget:new{
        text = charging and _("Charging") or _("Not charging"),
        face = KoboldWidgets.face(14),
        fgcolor = KoboldWidgets.subtitleColor(),
    }
    local content = VerticalGroup:new{
        align = "left",
        KoboldWidgets.fixed(inner, title_h, HorizontalGroup:new{
            title,
            HorizontalSpan:new{ width = math.max(0, inner - title:getSize().w - state:getSize().w) },
            state,
        }),
        VerticalSpan:new{ width = gap },
        TextWidget:new{
            text = level and (math.floor(level + 0.5) .. "%") or _("Unknown"),
            face = KoboldWidgets.face(36),
            bold = true,
        },
    }

    local box = FrameContainer:new{
        bordersize = border, padding = pad,
        radius = KoboldPopup.radius(),
        background = Blitbuffer.COLOR_WHITE,
        content,
    }
    self.frame_dimen = Geom:new{ x = fx, y = fy, w = fw, h = box:getSize().h }
    return KoboldPopup.place(self.dimen, fx, fy, box, KoboldPopup.anchor("battery"))
end

function KoboldBatteryPopup:init()
    local W, H = Screen:getWidth(), Screen:getHeight()
    self.dimen = Geom:new{ x = 0, y = 0, w = W, h = H }
    self[1] = self:build()

    if Device:hasKeys() then
        self.key_events = {
            Close = { { Device.input.group.Back } },
        }
    end
    if Device:isTouchDevice() then
        self.ges_events = {
            TapBattery = {
                GestureRange:new{ ges = "tap", range = self.dimen },
            },
        }
    end
end

-- Nothing to press in the box, so any tap closes it.
function KoboldBatteryPopup:onTapBattery()
    self:onClose()
    return true
end

function KoboldBatteryPopup:onClose()
    KoboldPopup.close(self)
    return true
end

-- Opens the popup. Called from the battery icon in the status bar.
function KoboldBatteryPopup.show()
    KoboldPopup.show(KoboldBatteryPopup:new{})
end

return KoboldBatteryPopup
