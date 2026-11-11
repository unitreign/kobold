-- kobold/ui/clock_popup.lua — Kobold
-- Clock popup, opened by tapping the time in the status bar, in the same
-- style as the toolbar popups: today's date and reading time, switches for
-- 24-hour time and the date in the status bar, and how soon the device
-- sleeps (KOReader's AutoSuspend setting).

local Device          = require("device")
local Event           = require("ui/event")
local Geom            = require("ui/geometry")
local GestureRange    = require("ui/gesturerange")
local InputContainer  = require("ui/widget/container/inputcontainer")
local UIManager       = require("ui/uimanager")
local _               = require("kobold.l10n")
local KoboldPrefs     = require("kobold.data.prefs")
local KoboldPopup     = require("kobold.ui.popup")
local KoboldWidgets   = require("kobold.ui.widgets")
local Kit             = require("kobold.ui.popup_kit")

local Screen = Device.screen

local KoboldClockPopup = InputContainer:extend{
    modal = true,
    name = "kobold_clock",
}

-- KOReader's AutoSuspend plugin, when it is running.
local function autoSuspend()
    local FileManager = package.loaded["apps/filemanager/filemanager"]
    local fm = FileManager and FileManager.instance
    return fm and fm.autosuspend
end

local SLEEP_CHOICES = { 5, 10, 15, 30, 60, 0 }  -- minutes; 0 = never

local function sleepLabel(minutes)
    if not minutes or minutes <= 0 then return _("Never") end
    if minutes >= 60 and minutes % 60 == 0 then return _.N("%1 hour", "%1 hours", minutes / 60) end
    return _.N("%1 minute", "%1 minutes", minutes)
end

-- Sets the auto-sleep timeout and restarts KOReader's timer with it.
local function setSleep(minutes)
    local seconds = minutes * 60
    G_reader_settings:saveSetting("auto_suspend_timeout_seconds", seconds)
    local plugin = autoSuspend()
    if plugin then
        plugin.auto_suspend_timeout_seconds = seconds
        pcall(function() plugin:_unschedule() end)
        pcall(function() plugin:_start() end)
    end
end

function KoboldClockPopup:build()
    -- "Thursday, 12 November"
    local date = os.date("%A, %d %B"):gsub(", 0", ", ")
    local rows = { Kit.text(date, 18) }
    local read = require("kobold.data.tokens").expand("[today_time]")
    if read ~= "–" then rows[#rows + 1] = Kit.text(_.T(_("Read today: %1"), read), 14, true) end
    rows[#rows + 1] = Kit.line()
    rows[#rows + 1] = Kit.switch(_("24-hour clock"), KoboldWidgets.clock24(), function()
        KoboldPrefs.set("clock_24h", not KoboldWidgets.clock24())
        self:changed()
    end)
    rows[#rows + 1] = Kit.switch(_("Date in status bar"), KoboldPrefs.get("status_date") == true, function()
        KoboldPrefs.set("status_date", KoboldPrefs.get("status_date") ~= true or nil)
        self:changed()
    end)
    local plugin = autoSuspend()
    if plugin then
        local minutes = math.floor((tonumber(plugin.auto_suspend_timeout_seconds) or 0) / 60)
        rows[#rows + 1] = Kit.line()
        rows[#rows + 1] = Kit.value(_("Sleep after"), sleepLabel(minutes), function()
            local choices = {}
            for i, m in ipairs(SLEEP_CHOICES) do choices[i] = { id = m, label = sleepLabel(m) } end
            require("kobold.ui.picker").choose(_("Sleep after"), choices, minutes, function(m)
                setSleep(m)
                self:refresh()
            end)
        end)
    end
    return Kit.build(self, "clock", rows)
end

function KoboldClockPopup:init()
    local W, H = Screen:getWidth(), Screen:getHeight()
    self.dimen = Geom:new{ x = 0, y = 0, w = W, h = H }
    self[1] = self:build()
    if Device:hasKeys() then
        self.key_events = { Close = { { Device.input.group.Back } } }
    end
    if Device:isTouchDevice() then
        self.ges_events = { TapClock = { GestureRange:new{ ges = "tap", range = self.dimen } } }
    end
end

function KoboldClockPopup:refresh()
    if self.closed then return end
    self[1] = self:build()
    UIManager:setDirty(self, function() return "ui", self.frame_dimen end)
end

-- Open Kobold screens redraw their status bar with the new format.
function KoboldClockPopup:changed()
    UIManager:broadcastEvent(Event:new("KoboldSettingsChanged"))
    self:refresh()
end

function KoboldClockPopup:onTapClock(_, ges)
    return Kit.tap(self, ges.pos)
end

function KoboldClockPopup:onClose()
    self.closed = true
    KoboldPopup.close(self)
    return true
end

function KoboldClockPopup.show()
    KoboldPopup.show(KoboldClockPopup:new{})
end

return KoboldClockPopup
