-- kobold/ui/menu.lua — Kobold
-- A small dropdown menu in the e-reader's style: a square box of italic
-- rows with the popup arrow pointing at what opened it (a "..." button, a
-- book, a collection). Used by the book menu, the "..." buttons of My Books
-- and the collection menu.
--
-- Placement (opts.place):
--   nil      below the anchor when it fits, else above; arrow up or down
--   "left"   beside the anchor, to its left, centred on it; arrow points right
--   "right"  beside the anchor, to its right, centred on it; arrow points left

local Blitbuffer      = require("ffi/blitbuffer")
local Device          = require("device")
local FrameContainer  = require("ui/widget/container/framecontainer")
local Geom            = require("ui/geometry")
local GestureRange    = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan  = require("ui/widget/horizontalspan")
local InputContainer  = require("ui/widget/container/inputcontainer")
local LeftContainer   = require("ui/widget/container/leftcontainer")
local LineWidget      = require("ui/widget/linewidget")
local TextWidget      = require("ui/widget/textwidget")
local UIManager       = require("ui/uimanager")
local VerticalGroup   = require("ui/widget/verticalgroup")
local KoboldPopup     = require("kobold.ui.popup")
local KoboldWidgets   = require("kobold.ui.widgets")

local Screen = Device.screen

local KoboldMenu = InputContainer:extend{
    modal = true,
    name = "kobold_menu",
    items = nil,     -- { { text, checked = bool, callback = fn }, ... }
    anchor = nil,    -- Geom on screen of what it points at
    place = nil,     -- nil, "left" or "right" (see above)
    align = "right", -- below/above only: "right" ends at the anchor's right edge, "left" starts at its left
    width = nil,     -- box width; default 45% of the screen
    on_close = nil,  -- runs when the menu closes (picked or not)
}

function KoboldMenu:build()
    local W, H = Screen:getWidth(), Screen:getHeight()
    local pad, border = Screen:scaleBySize(4), Screen:scaleBySize(2)
    local row_h = Screen:scaleBySize(42)
    local text_pad = Screen:scaleBySize(14)
    local check_w = Screen:scaleBySize(22)
    local line_h = Screen:scaleBySize(1)
    local fw = self.width or math.floor(W * 0.45)
    local inner = fw - 2 * (pad + border)
    local margin = Screen:scaleBySize(12)
    local arrow_h = KoboldPopup.arrowHeight()
    local any_check = false
    for _i, item in ipairs(self.items) do if item.checked ~= nil then any_check = true end end

    local list = VerticalGroup:new{ align = "left" }
    for i, item in ipairs(self.items) do
        if i > 1 then
            list[#list + 1] = LineWidget:new{
                dimen = Geom:new{ w = inner, h = line_h }, background = Blitbuffer.COLOR_LIGHT_GRAY,
            }
        end
        local row = HorizontalGroup:new{ align = "center", HorizontalSpan:new{ width = text_pad } }
        if any_check then
            -- A tick before the chosen item, room kept on the others.
            row[#row + 1] = KoboldWidgets.fixed(check_w, row_h, LeftContainer:new{
                dimen = Geom:new{ w = check_w, h = row_h },
                TextWidget:new{ text = item.checked and "✓" or "", face = KoboldWidgets.face(16) },
            })
        end
        row[#row + 1] = TextWidget:new{
            text = item.text, face = KoboldWidgets.italicFace(17),
            max_width = inner - 2 * text_pad - (any_check and check_w or 0),
        }
        list[#list + 1] = KoboldWidgets.fixed(inner, row_h, LeftContainer:new{
            dimen = Geom:new{ w = inner, h = row_h }, row,
        })
    end
    local box = FrameContainer:new{
        bordersize = border, padding = pad,
        radius = KoboldPopup.radius(),
        background = Blitbuffer.COLOR_WHITE,
        list,
    }
    local fh = box:getSize().h
    local a = self.anchor

    local fx, fy, layer
    if self.place == "left" or self.place == "right" then
        local mid = a.y + math.floor(a.h / 2)
        if self.place == "left" then
            fx = a.x - arrow_h - fw
        else
            fx = a.x + a.w + arrow_h
        end
        fx = math.max(margin, math.min(W - margin - fw, fx))
        fy = math.max(margin, math.min(H - margin - fh, mid - math.floor(fh / 2)))
        layer = KoboldPopup.placeSide(self.dimen, fx, fy, box, mid, self.place == "right")
    else
        local below = a.y + a.h + arrow_h + fh + margin <= H
        fy = below and (a.y + a.h + arrow_h) or (a.y - arrow_h - fh)
        fx = self.align == "left" and a.x or (a.x + a.w - fw)
        fx = math.max(margin, math.min(W - margin - fw, fx))
        fy = math.max(margin, fy)
        layer = KoboldPopup.place(self.dimen, fx, fy, box, a.x + math.floor(a.w / 2), not below)
    end

    self.frame_dimen = Geom:new{ x = fx, y = fy, w = fw, h = fh }
    self.rows = {}
    local y = fy + border + pad
    for i, item in ipairs(self.items) do
        self.rows[i] = { rect = Geom:new{ x = fx, y = y, w = fw, h = row_h }, item = item }
        y = y + row_h + line_h
    end
    return layer
end

function KoboldMenu:init()
    local W, H = Screen:getWidth(), Screen:getHeight()
    self.dimen = Geom:new{ x = 0, y = 0, w = W, h = H }
    self[1] = self:build()
    if Device:hasKeys() then
        self.key_events = { Close = { { Device.input.group.Back } } }
    end
    if Device:isTouchDevice() then
        self.ges_events = {
            TapMenu = { GestureRange:new{ ges = "tap", range = self.dimen } },
        }
    end
end

-- A row runs its callback (after the menu has closed); anywhere else closes.
function KoboldMenu:onTapMenu(_, ges)
    for _i, row in ipairs(self.rows) do
        if ges.pos:intersectWith(row.rect) then
            self:onClose()
            if row.item.callback then UIManager:nextTick(row.item.callback) end
            return true
        end
    end
    return self:onClose()
end

function KoboldMenu:onClose()
    if self.closed then return true end
    self.closed = true
    KoboldPopup.close(self)
    if self.on_close then self.on_close() end
    return true
end

-- Opens a menu. opts: items, anchor, place, align, width, on_close.
function KoboldMenu.show(opts)
    local menu = KoboldMenu:new(opts)
    KoboldPopup.show(menu)
    return menu
end

return KoboldMenu
