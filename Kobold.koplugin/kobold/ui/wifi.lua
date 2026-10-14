-- kobold/ui/wifi.lua — Kobold
-- Wi-Fi popup opened from the Wi-Fi icon in the status bar, in the same box
-- style as the brightness popup. It shows whether Wi-Fi is on and which
-- network is connected, with one Connect or Disconnect button. The work is
-- done by KOReader's NetworkMgr, which shows its own progress messages and
-- network list. Tap outside the box to close it.

local Blitbuffer      = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device          = require("device")
local FrameContainer  = require("ui/widget/container/framecontainer")
local Geom            = require("ui/geometry")
local GestureRange    = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan  = require("ui/widget/horizontalspan")
local InputContainer  = require("ui/widget/container/inputcontainer")
local TextBoxWidget   = require("ui/widget/textboxwidget")
local TextWidget      = require("ui/widget/textwidget")
local UIManager       = require("ui/uimanager")
local VerticalGroup   = require("ui/widget/verticalgroup")
local VerticalSpan    = require("ui/widget/verticalspan")
local KoboldPopup     = require("kobold.ui.popup")
local KoboldWidgets   = require("kobold.ui.widgets")
local _               = require("gettext")

local Screen = Device.screen

local KoboldWifi = InputContainer:extend{
    modal = true,
    name = "kobold_wifi",
}

local function networkMgr()
    local ok, NetworkMgr = pcall(require, "ui/network/manager")
    if ok then return NetworkMgr end
    return nil
end

-- { available, on, connected, ssid } read from NetworkMgr. Every call is
-- guarded, since not every device or KOReader version has all of them.
local function readState()
    local NetworkMgr = networkMgr()
    local has_toggle = Device.hasWifiToggle == nil or Device:hasWifiToggle()
    if not NetworkMgr or not has_toggle then return { available = false } end
    local function ask(method)
        if not NetworkMgr[method] then return nil end
        local ok, v = pcall(NetworkMgr[method], NetworkMgr)
        if ok then return v end
        return nil
    end
    local on = ask("isWifiOn") and true or false
    local connected = on and ask("isConnected") and true or false
    local network = connected and ask("getCurrentNetwork")
    local ssid = type(network) == "table" and network.ssid or nil
    if ssid == "" then ssid = nil end
    return { available = true, on = on, connected = connected, ssid = ssid }
end

-- Builds the box and records the button rectangle, in screen coordinates.
function KoboldWifi:build()
    local pad      = Screen:scaleBySize(16)
    local border   = Screen:scaleBySize(2)
    local title_h  = Screen:scaleBySize(30)
    local gap      = Screen:scaleBySize(14)
    local button_h = Screen:scaleBySize(44)

    local fw    = KoboldPopup.width()
    local inner = fw - 2 * (pad + border)
    local fx, fy = KoboldPopup.origin(fw)
    local state = self.state

    -- Title row: "Wi-Fi" on the left, On / Off on the right.
    local title = TextWidget:new{ text = _("Wi-Fi"), face = KoboldWidgets.face(18) }
    local on_off = TextWidget:new{
        text = not state.available and "" or (state.on and _("On") or _("Off")),
        face = KoboldWidgets.face(14),
        fgcolor = KoboldWidgets.subtitleColor(),
    }
    local status_text
    if not state.available then
        status_text = _("Wi-Fi is not available on this device.")
    elseif state.connected then
        status_text = state.ssid and (_("Connected to ") .. state.ssid) or _("Connected")
    elseif state.on then
        status_text = _("Not connected")
    else
        status_text = _("Wi-Fi is off")
    end
    local status = TextBoxWidget:new{
        text = status_text,
        face = KoboldWidgets.face(14),
        fgcolor = KoboldWidgets.subtitleColor(),
        width = inner,
        alignment = "left",
    }

    local content = VerticalGroup:new{
        align = "left",
        KoboldWidgets.fixed(inner, title_h, HorizontalGroup:new{
            title,
            HorizontalSpan:new{ width = math.max(0, inner - title:getSize().w - on_off:getSize().w) },
            on_off,
        }),
        status,
    }

    -- One full-width button: Disconnect when connected, otherwise Connect.
    self.button = nil
    if state.available then
        local label = state.connected and _("Disconnect") or _("Connect")
        local button_y = fy + border + pad + title_h + status:getSize().h + gap
        content[#content + 1] = VerticalSpan:new{ width = gap }
        content[#content + 1] = FrameContainer:new{
            width = inner, height = button_h,
            bordersize = border, radius = Screen:scaleBySize(8), padding = 0,
            background = Blitbuffer.COLOR_WHITE,
            CenterContainer:new{
                dimen = Geom:new{ w = inner - 2 * border, h = button_h - 2 * border },
                TextWidget:new{ text = label, face = KoboldWidgets.face(16), bold = true },
            },
        }
        self.button = Geom:new{ x = fx + border + pad, y = button_y, w = inner, h = button_h }
    end

    local box = FrameContainer:new{
        width = fw, bordersize = border, padding = pad,
        radius = KoboldPopup.radius(),
        background = Blitbuffer.COLOR_WHITE,
        content,
    }
    self.frame_dimen = Geom:new{ x = fx, y = fy, w = fw, h = box:getSize().h }
    return KoboldPopup.place(self.dimen, fx, fy, box)
end

function KoboldWifi:init()
    local W, H = Screen:getWidth(), Screen:getHeight()
    self.dimen = Geom:new{ x = 0, y = 0, w = W, h = H }
    self.state = readState()
    self[1] = self:build()

    if Device:hasKeys() then
        self.key_events = {
            Close = { { Device.input.group.Back } },
        }
    end
    if Device:isTouchDevice() then
        self.ges_events = {
            TapWifi = {
                GestureRange:new{
                    ges = "tap",
                    range = self.dimen,
                },
            },
        }
    end
end

-- Closes the popup first, so KOReader's own Wi-Fi messages and network list
-- are not hidden under it, then asks NetworkMgr to connect or disconnect.
-- The status bar icon updates from the NetworkConnected / NetworkDisconnected
-- events KOReader sends afterwards.
function KoboldWifi:toggle()
    local state = self.state
    self:onClose()
    local NetworkMgr = networkMgr()
    if not NetworkMgr then return end
    UIManager:nextTick(function()
        pcall(function()
            if state.connected then
                if NetworkMgr.toggleWifiOff then
                    NetworkMgr:toggleWifiOff(nil, true)
                else
                    NetworkMgr:turnOffWifi()
                end
            elseif state.on and NetworkMgr.reconnectOrShowNetworkMenu then
                -- On but not connected: join a known network, or pick one.
                NetworkMgr:reconnectOrShowNetworkMenu(nil, true)
            elseif NetworkMgr.toggleWifiOn then
                NetworkMgr:toggleWifiOn(nil, false, true)
            else
                NetworkMgr:turnOnWifi()
            end
        end)
    end)
end

-- Taps on the button connect or disconnect. Taps outside the box close the
-- popup. Other taps inside the box do nothing.
function KoboldWifi:onTapWifi(_, ges)
    local pos = ges.pos
    if not pos:intersectWith(self.frame_dimen) then
        self:onClose()
    elseif self.button and pos:intersectWith(self.button) then
        self:toggle()
    end
    return true
end

function KoboldWifi:onClose()
    KoboldPopup.close(self)
    return true
end

-- Opens the popup. Called from the Wi-Fi icon in the status bar.
function KoboldWifi.show()
    KoboldPopup.show(KoboldWifi:new{})
end

return KoboldWifi
