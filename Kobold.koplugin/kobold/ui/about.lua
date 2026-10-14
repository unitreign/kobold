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
local KoboldPrefs     = require("kobold.data.prefs")
local KoboldSettingsList = require("kobold.ui.settings_list")
local KoboldTaps      = require("kobold.ui.taps")
local KoboldWidgets   = require("kobold.ui.widgets")

local Screen = Device.screen

local KoboldAbout = InputContainer:extend{
    covers_fullscreen = true,
    name = "kobold_about",
}

local function image(file, size)
    if not file then return nil end
    local ok, widget = pcall(function()
        return ImageWidget:new{ file = file, width = size, height = size, alpha = true }
    end)
    return ok and widget or nil
end

-- A widget centred in a box `w` wide.
local function centred(w, widget)
    return CenterContainer:new{ dimen = Geom:new{ w = w, h = widget:getSize().h }, widget }
end

function KoboldAbout:build()
    local W, H = Screen:getWidth(), Screen:getHeight()
    local margin    = Screen:scaleBySize(30)
    local content_w = W - 2 * margin
    local top_h     = Screen:scaleBySize(44)
    local close_sz  = Screen:scaleBySize(28)
    local gap       = Screen:scaleBySize(10)

    self.close_rect = Geom:new{
        x = margin + content_w - close_sz - gap, y = margin - gap,
        w = close_sz + 2 * gap, h = top_h + gap,
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
    local icon = image(KoboldMeta.icon("kobold.svg"), icon_size)
    if icon then page[#page + 1] = centred(content_w, icon) end
    -- Tap area of the logo, for the debug mode toggle.
    self.logo_rect = Geom:new{
        x = math.floor((W - icon_size) / 2), y = margin + top_h + gap,
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

    local list = KoboldSettingsList.build({
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
    }, 0, 0, content_w)
    page[#page + 1] = list

    -- QR code to the project page, as large as fits above the bottom margin
    -- (at most 150 px before scaling), with a caption. Left out when there
    -- is no room for a scannable size.
    local caption = TextWidget:new{
        text = _("Scan to open the project page"),
        face = KoboldWidgets.face(13),
        fgcolor = KoboldWidgets.subtitleColor(),
    }
    local room = H - margin - page:getSize().h - 3 * gap - caption:getSize().h
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

    return FrameContainer:new{
        width = W, height = H, bordersize = 0, padding = 0,
        background = Blitbuffer.COLOR_WHITE,
        OverlapGroup:new{
            dimen = Geom:new{ w = W, h = H },
            FrameContainer:new{
                bordersize = 0, padding = margin, padding_bottom = 0,
                page,
            },
        },
    }
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
    UIManager:close(self)
    return true
end

function KoboldAbout.show()
    UIManager:show(KoboldAbout:new{})
end

return KoboldAbout
