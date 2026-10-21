-- kobold/ui/wifi.lua — Kobold
-- Wi-Fi popup opened from the Wi-Fi icon in the status bar, in the same box
-- style as the brightness popup: a switch to turn Wi-Fi on or off, the
-- connected network, and a link to the list of networks. The work is
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
local LineWidget      = require("ui/widget/linewidget")
local LeftContainer   = require("ui/widget/container/leftcontainer")
local InfoMessage     = require("ui/widget/infomessage")
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

-- On/off switch, as on the brightness popup: black with "On" when on.
local function switch(on)
    local sw_w, sw_h = Screen:scaleBySize(64), Screen:scaleBySize(30)
    return FrameContainer:new{
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
    }, sw_w
end

-- Builds the box, in the e-reader's style: a switch row ("WI-FI: ENABLED"),
-- the network row, and a "Wi-Fi Settings" link at the bottom. Records each
-- row's tap rectangle, in screen coordinates.
function KoboldWifi:build()
    local pad    = Screen:scaleBySize(16)
    local border = Screen:scaleBySize(2)
    local row_h  = Screen:scaleBySize(52)
    local line_h = Screen:scaleBySize(1)
    local gap    = Screen:scaleBySize(12)

    local fw    = KoboldPopup.width()
    local inner = fw - 2 * (pad + border)
    local fx, fy = KoboldPopup.origin(fw)
    local x0, y0 = fx + border + pad, fy + border + pad
    local state = self.state
    self.rows = {}

    local function line()
        return LineWidget:new{ dimen = Geom:new{ w = inner, h = line_h }, background = Blitbuffer.COLOR_LIGHT_GRAY }
    end
    local function row(widget)
        return KoboldWidgets.fixed(inner, row_h, LeftContainer:new{
            dimen = Geom:new{ w = inner, h = row_h }, widget,
        })
    end

    local content = VerticalGroup:new{ align = "left" }
    local y = y0
    if not state.available then
        content[#content + 1] = TextBoxWidget:new{
            text = _("Wi-Fi is not available on this device."),
            face = KoboldWidgets.face(15), width = inner,
        }
    else
        -- Switch row: tap anywhere on it to turn Wi-Fi on or off.
        local sw, sw_w = switch(state.on)
        content[#content + 1] = row(HorizontalGroup:new{
            align = "center",
            sw,
            HorizontalSpan:new{ width = gap },
            TextWidget:new{
                text = state.on and _("WI-FI: ENABLED") or _("WI-FI: DISABLED"),
                face = KoboldWidgets.face(15), max_width = inner - sw_w - gap,
            },
        })
        self.rows.toggle = Geom:new{ x = x0, y = y, w = inner, h = row_h }
        y = y + row_h

        if state.on then
            -- Network row: the connected network, or "Not connected" (tap
            -- to join a known network or pick one).
            content[#content + 1] = line()
            y = y + line_h
            local icon_size = Screen:scaleBySize(22)
            local label = state.connected and (state.ssid or _("Connected")) or _("Not connected")
            local status = TextWidget:new{
                text = state.connected and _("Connected") or _("Connect"),
                face = KoboldWidgets.face(13), fgcolor = KoboldWidgets.subtitleColor(),
            }
            local name_w = inner - icon_size - gap - status:getSize().w - gap
            local name = TextWidget:new{ text = label, face = KoboldWidgets.face(16), max_width = name_w }
            content[#content + 1] = row(HorizontalGroup:new{
                align = "center",
                KoboldWidgets.customIcon(KoboldWidgets.wifiIconName(), icon_size, "wifi.open.100"),
                HorizontalSpan:new{ width = gap },
                name,
                HorizontalSpan:new{ width = math.max(0, name_w - name:getSize().w + gap) },
                status,
            })
            if not state.connected then
                self.rows.connect = Geom:new{ x = x0, y = y, w = inner, h = row_h }
            end
            y = y + row_h

            -- Link to KOReader's list of networks, in italics.
            content[#content + 1] = line()
            y = y + line_h
            local face = KoboldWidgets.face(16)
            local ok_f, italic = pcall(function() return require("ui/font"):getFace("infont", 16) end)
            if ok_f and italic then face = italic end
            content[#content + 1] = row(TextWidget:new{ text = _("Wi-Fi Settings"), face = face })
            self.rows.settings = Geom:new{ x = x0, y = y, w = inner, h = row_h }
        end
    end

    local box = FrameContainer:new{
        width = fw, bordersize = border, padding = pad,
        radius = KoboldPopup.radius(),
        background = Blitbuffer.COLOR_WHITE,
        content,
    }
    self.frame_dimen = Geom:new{ x = fx, y = fy, w = fw, h = box:getSize().h }
    return KoboldPopup.place(self.dimen, fx, fy, box, KoboldPopup.anchor("wifi"))
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
-- are not hidden under it, then runs `fn` with NetworkMgr. The status bar
-- icon updates from the NetworkConnected / NetworkDisconnected events
-- KOReader sends afterwards.
function KoboldWifi:runAfterClose(fn)
    self:onClose()
    local NetworkMgr = networkMgr()
    if not NetworkMgr then return end
    UIManager:nextTick(function() pcall(fn, NetworkMgr) end)
end

-- The switch: Wi-Fi on (KOReader then connects to a known network) or off.
function KoboldWifi:toggle()
    local on = self.state.on
    self:runAfterClose(function(NetworkMgr)
        if on then
            if NetworkMgr.toggleWifiOff then NetworkMgr:toggleWifiOff(nil, true) else NetworkMgr:turnOffWifi() end
        else
            if NetworkMgr.toggleWifiOn then NetworkMgr:toggleWifiOn(nil, false, true) else NetworkMgr:turnOnWifi() end
        end
    end)
end

-- "Not connected": join a known network, or pick one from the list.
function KoboldWifi:connect()
    self:runAfterClose(function(NetworkMgr) NetworkMgr:reconnectOrShowNetworkMenu(nil, true) end)
end

-- "Wi-Fi Settings": KOReader's list of networks, to pick another one.
-- Scans first, like KOReader's own menu.
function KoboldWifi:showNetworks()
    self:runAfterClose(function(NetworkMgr)
        local ok = pcall(function()
            local info = InfoMessage:new{ text = _("Scanning for networks…") }
            UIManager:show(info)
            UIManager:forceRePaint()
            local list, err = NetworkMgr:getNetworkList()
            UIManager:close(info)
            if not list then
                UIManager:show(InfoMessage:new{ text = tostring(err) })
                return
            end
            table.sort(list, function(l, r) return (l.signal_quality or 0) > (r.signal_quality or 0) end)
            UIManager:show(require("ui/widget/networksetting"):new{ network_list = list })
        end)
        if not ok then NetworkMgr:reconnectOrShowNetworkMenu(nil, true) end
    end)
end

-- Taps on a row run it; taps outside the box close the popup.
function KoboldWifi:onTapWifi(_, ges)
    local pos = ges.pos
    local rows = self.rows or {}
    if not pos:intersectWith(self.frame_dimen) then
        self:onClose()
    elseif rows.toggle and pos:intersectWith(rows.toggle) then
        self:toggle()
    elseif rows.connect and pos:intersectWith(rows.connect) then
        self:connect()
    elseif rows.settings and pos:intersectWith(rows.settings) then
        self:showNetworks()
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
