-- kobold/ui/about.lua — Kobold
-- About Kobold, opened from the More tab, in the same full-screen style as
-- Kobold Settings: the Kobold icon centred at the top, name, version and a
-- few words on what it is, the project rows, and a QR code to the project
-- page (an e-reader cannot open links, a phone can scan it).

local Blitbuffer      = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device          = require("device")
local FrameContainer  = require("ui/widget/container/framecontainer")
local Geom            = require("ui/geometry")
local ImageWidget     = require("ui/widget/imagewidget")
local InputContainer  = require("ui/widget/container/inputcontainer")
local OverlapGroup    = require("ui/widget/overlapgroup")
local RightContainer  = require("ui/widget/container/rightcontainer")
local TextBoxWidget   = require("ui/widget/textboxwidget")
local TextWidget      = require("ui/widget/textwidget")
local UIManager       = require("ui/uimanager")
local VerticalGroup   = require("ui/widget/verticalgroup")
local VerticalSpan    = require("ui/widget/verticalspan")
local _               = require("gettext")
local InfoMessage     = require("ui/widget/infomessage")
local KoboldMeta      = require("kobold.meta")
local KoboldPopup     = require("kobold.ui.popup")
local KoboldPrefs     = require("kobold.data.prefs")
local KoboldSettingsList = require("kobold.ui.settings_list")
local KoboldTaps      = require("kobold.ui.taps")
local KoboldWidgets   = require("kobold.ui.widgets")

local Screen = Device.screen

local KoboldAbout = InputContainer:extend{
    -- A panel over the screen it was opened from, not a full screen.
    name = "kobold_about",
}

-- `follow_night` lets the image invert with the page in night mode (the
-- logo is a black drawing; kept original it would vanish on the black page).
-- The QR code keeps its original colors so it still scans.
local function image(file, size, follow_night)
    if not file then return nil end
    local ok, widget = pcall(function()
        return ImageWidget:new{
            file = file, width = size, height = size, alpha = true,
            original_in_nightmode = not follow_night,
        }
    end)
    return ok and widget or nil
end

-- A widget centred in a box `w` wide.
local function centred(w, widget)
    return CenterContainer:new{ dimen = Geom:new{ w = w, h = widget:getSize().h }, widget }
end

-- A bordered panel inset from the screen edges, like Kobold Settings.
function KoboldAbout:build()
    local R = KoboldPopup.panelRect()
    local border    = Screen:scaleBySize(2)
    local pad       = Screen:scaleBySize(20)
    local content_w = R.w - 2 * (border + pad)
    local inner_h   = R.h - 2 * (border + pad)
    local x0, y0    = R.x + border + pad, R.y + border + pad
    local top_h     = Screen:scaleBySize(36)
    local close_sz  = Screen:scaleBySize(26)
    local gap       = Screen:scaleBySize(10)
    self.panel_rect = R

    self.close_rect = Geom:new{
        x = x0 + content_w - close_sz - pad, y = R.y,
        w = close_sz + 2 * pad, h = top_h + pad,
    }

    local page = VerticalGroup:new{
        align = "left",
        OverlapGroup:new{
            dimen = Geom:new{ w = content_w, h = top_h },
            CenterContainer:new{
                dimen = Geom:new{ w = content_w, h = top_h },
                TextWidget:new{ text = _("About"), face = KoboldWidgets.face(15) },
            },
            RightContainer:new{
                dimen = Geom:new{ w = content_w, h = top_h },
                KoboldWidgets.icon("close", close_sz),
            },
        },
        VerticalSpan:new{ width = gap },
    }
    local icon_size = Screen:scaleBySize(128)
    local icon = image(KoboldMeta.icon("kobold.svg"), icon_size, true)
    if icon then page[#page + 1] = centred(content_w, icon) end
    -- Tap area of the logo, for the debug mode toggle.
    self.logo_rect = Geom:new{
        x = x0 + math.floor((content_w - icon_size) / 2), y = y0 + top_h + gap,
        w = icon_size, h = icon_size,
    }
    page[#page + 1] = centred(content_w, TextWidget:new{
        text = _("Kobold"), face = KoboldWidgets.face(26), bold = true,
    })
    page[#page + 1] = centred(content_w, TextWidget:new{
        text = _("Version ") .. KoboldMeta.VERSION,
        face = KoboldWidgets.face(14),
        fgcolor = KoboldWidgets.subtitleColor(),
    })
    page[#page + 1] = VerticalSpan:new{ width = gap }
    page[#page + 1] = TextBoxWidget:new{
        text = _("A home screen for KOReader that brings back the calm, familiar look of "
            .. "your e-reader's original software. Made out of love for that look: your "
            .. "books up front, quiet pages, and everything one tap away."),
        face = KoboldWidgets.face(15),
        width = content_w,
        alignment = "center",
    }
    page[#page + 1] = VerticalSpan:new{ width = 2 * gap }

    -- Tap a row's name for its details (tooltip). The group's layout is
    -- measured here, so it is reset once everything is added (see the end).
    local list_y = y0 + page:getSize().h
    local list, hits = KoboldSettingsList.build({
        { section = _("Project") },
        {
            title = _("Source code"),
            desc = KoboldMeta.REPO:gsub("^https?://", ""),
            value = _("GitHub"),
        },
        {
            title = _("License"),
            desc = _("Free and open source software under the GNU General Public License, version 3."),
            value = KoboldMeta.LICENSE,
        },
    }, x0, list_y, content_w)
    self.hits = hits
    page[#page + 1] = list

    -- QR code to the project page, as large as fits above the bottom margin
    -- (at most 150 px before scaling), with a caption. Left out when there
    -- is no room for a scannable size.
    local caption = TextWidget:new{
        text = _("Scan to open the project page"),
        face = KoboldWidgets.face(13),
        fgcolor = KoboldWidgets.subtitleColor(),
    }
    page:resetLayout()
    local room = inner_h - page:getSize().h - 3 * gap - caption:getSize().h
    local qr_size = math.min(Screen:scaleBySize(150), room)
    if qr_size >= Screen:scaleBySize(90) then
        local qr = image(KoboldMeta.icon("kobold-qr.png"), qr_size)
        if qr then
            page[#page + 1] = VerticalSpan:new{ width = 2 * gap }
            page[#page + 1] = centred(content_w, qr)
            page[#page + 1] = VerticalSpan:new{ width = gap }
            page[#page + 1] = centred(content_w, caption)
            -- page:getSize() above cached the group's layout; drop it so the
            -- rows just added get laid out too (painting them crashed).
            page:resetLayout()
        end
    end

    page:resetLayout()
    local panel = FrameContainer:new{
        bordersize = border, padding = pad,
        radius = KoboldPopup.radius(),
        background = Blitbuffer.COLOR_WHITE,
        KoboldWidgets.fixed(content_w, inner_h, page),
    }
    return KoboldPopup.place(self.dimen, R.x, R.y, panel)
end

function KoboldAbout:init()
    local W, H = Screen:getWidth(), Screen:getHeight()
    self.dimen = Geom:new{ x = 0, y = 0, w = W, h = H }
    if Device:hasKeys() then
        self.key_events = { Close = { { Device.input.group.Back } } }
    end
    self[1] = self:build()
    KoboldTaps.add(self, "KoboldAboutTap", 0, 0, W, H, function(ges)
        if ges.pos:intersectWith(self.close_rect) then
            self:onClose()
        elseif ges.pos:intersectWith(self.logo_rect) then
            self:onLogoTap()
        else
            local on_tap = KoboldSettingsList.hit(self.hits, ges.pos)
            if on_tap then on_tap() end
        end
    end)
end

-- Ten taps on the logo, each within 3 seconds of the last, toggle debug
-- mode and save it.
function KoboldAbout:onLogoTap()
    local now = os.time()
    if not self.logo_taps or now - (self.logo_last or 0) > 3 then self.logo_taps = 0 end
    self.logo_taps = self.logo_taps + 1
    self.logo_last = now
    if self.logo_taps < 10 then return end
    self.logo_taps = 0
    local on = not KoboldMeta.debugOn()
    KoboldPrefs.set("debug", on)
    UIManager:show(InfoMessage:new{
        text = on and _("Debug mode on. Long-press the clock to save a screenshot.")
            or _("Debug mode off."),
        timeout = 2,
    })
end

function KoboldAbout:onClose()
    UIManager:close(self, "ui", self.panel_rect)
    return true
end

function KoboldAbout.show()
    local w = KoboldAbout:new{}
    UIManager:show(w, "ui", w.panel_rect)
end

return KoboldAbout
