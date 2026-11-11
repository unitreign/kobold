-- kobold/ui/battery_popup.lua — Kobold
-- Battery popup opened from the battery icon in the status bar, in the
-- e-reader's style: "eReader: 75%" (and whether it is charging), the time
-- left from KOReader's Battery statistics when it has enough data, how the
-- status bar shows the battery, and a link to the full statistics.

local Device          = require("device")
local Event           = require("ui/event")
local Geom            = require("ui/geometry")
local GestureRange    = require("ui/gesturerange")
local InputContainer  = require("ui/widget/container/inputcontainer")
local UIManager       = require("ui/uimanager")
local _               = require("kobold.l10n")
local KoboldBattery   = require("kobold.ui.battery")
local KoboldBatteryStats = require("kobold.data.battery_stats")
local KoboldPopup     = require("kobold.ui.popup")
local KoboldPrefs     = require("kobold.data.prefs")
local Kit             = require("kobold.ui.popup_kit")

local Screen = Device.screen

local KoboldBatteryPopup = InputContainer:extend{
    modal = true,
    name = "kobold_battery",
    kobold_tool = "battery",
}

function KoboldBatteryPopup:build()
    local level, charging = KoboldBattery.state()
    local pct = level and (math.floor(level + 0.5) .. "%") or _("Unknown")
    local rows = {
        Kit.text(_.T(_("eReader: %1"), pct), 18),
    }
    if charging then
        rows[#rows + 1] = Kit.text(_("Charging"), 14, true)
    else
        local left = KoboldBatteryStats.timeLeft()
        if left then rows[#rows + 1] = Kit.text(_.T(_("About %1 left"), left), 14, true) end
    end
    rows[#rows + 1] = Kit.line()
    local percent = KoboldPrefs.get("battery") == "percent"
    rows[#rows + 1] = Kit.value(_("Show as"), percent and _("Percentage") or _("Icon fill"), function()
        KoboldPrefs.set("battery", percent and "fill" or "percent")
        -- Open Kobold screens redraw their status bar.
        UIManager:broadcastEvent(Event:new("KoboldSettingsChanged"))
        self:refresh()
    end)
    if KoboldBatteryStats.available() then
        rows[#rows + 1] = Kit.line()
        rows[#rows + 1] = Kit.link(_("Battery statistics"), function()
            self:onClose()
            KoboldBatteryStats.open()
        end)
    end
    return Kit.build(self, "battery", rows)
end

function KoboldBatteryPopup:init()
    local W, H = Screen:getWidth(), Screen:getHeight()
    self.dimen = Geom:new{ x = 0, y = 0, w = W, h = H }
    self[1] = self:build()
    if Device:hasKeys() then
        self.key_events = { Close = { { Device.input.group.Back } } }
    end
    if Device:isTouchDevice() then
        self.ges_events = { TapBattery = { GestureRange:new{ ges = "tap", range = self.dimen } } }
    end
end

function KoboldBatteryPopup:refresh()
    self[1] = self:build()
    UIManager:setDirty(self, function() return "ui", self.frame_dimen end)
end

function KoboldBatteryPopup:onTapBattery(_, ges)
    return Kit.tap(self, ges.pos)
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
