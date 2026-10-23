-- kobold/ui/book_menu.lua — Kobold
-- The small menu for one book: Read now, View Details (Kobold's details
-- page) and KOReader Details (the file browser's own book menu). Opened
-- from a book's "..." in My Books and by holding one of Home's recent books.
-- A square box with the popup arrow pointing at what opened it: below it
-- when there is room, otherwise above it.

local Blitbuffer      = require("ffi/blitbuffer")
local Device          = require("device")
local Font            = require("ui/font")
local FrameContainer  = require("ui/widget/container/framecontainer")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan  = require("ui/widget/horizontalspan")
local Geom            = require("ui/geometry")
local GestureRange    = require("ui/gesturerange")
local InputContainer  = require("ui/widget/container/inputcontainer")
local LeftContainer   = require("ui/widget/container/leftcontainer")
local LineWidget      = require("ui/widget/linewidget")
local TextWidget      = require("ui/widget/textwidget")
local UIManager       = require("ui/uimanager")
local VerticalGroup   = require("ui/widget/verticalgroup")
local _               = require("gettext")
local KoboldPopup     = require("kobold.ui.popup")
local KoboldWidgets   = require("kobold.ui.widgets")

local Screen = Device.screen

local KoboldBookMenu = InputContainer:extend{
    modal = true,
    name = "kobold_book_menu",
    file = nil,
    screen = nil,   -- the Kobold screen it opened from
    anchor = nil,   -- Geom of what it points at (a cover, a "..."), screen coordinates
    align = "right", -- "right": box ends at the anchor's right edge; "left": starts at its left
    side = false,    -- true: beside the anchor (to its left), arrow pointing right
    on_change = nil, -- runs after the KOReader menu changed something
}

local function italicFace(size)
    local ok, face = pcall(function() return KoboldWidgets.italicFace(size) end)
    if ok and face then return face end
    return KoboldWidgets.face(size)
end

function KoboldBookMenu:build()
    local W, H = Screen:getWidth(), Screen:getHeight()
    local pad, border = Screen:scaleBySize(4), Screen:scaleBySize(2)
    local row_h = Screen:scaleBySize(42)
    local text_pad = Screen:scaleBySize(14)
    local line_h = Screen:scaleBySize(1)
    local fw = math.floor(W * 0.45)
    local inner = fw - 2 * (pad + border)
    local margin = Screen:scaleBySize(12)
    local arrow_h = KoboldPopup.arrowHeight()

    local items = {
        { text = _("Read now"), action = "read" },
        { text = _("View Details"), action = "details" },
        { text = _("KOReader Details"), action = "koreader" },
    }
    local list = VerticalGroup:new{ align = "left" }
    for i, item in ipairs(items) do
        if i > 1 then
            list[#list + 1] = LineWidget:new{
                dimen = Geom:new{ w = inner, h = line_h }, background = Blitbuffer.COLOR_LIGHT_GRAY,
            }
        end
        list[#list + 1] = KoboldWidgets.fixed(inner, row_h, LeftContainer:new{
            dimen = Geom:new{ w = inner, h = row_h },
            HorizontalGroup:new{
                HorizontalSpan:new{ width = text_pad },
                TextWidget:new{ text = item.text, face = italicFace(17), max_width = inner - 2 * text_pad },
            },
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
    if self.side then
        -- Beside the anchor, to its left, with the box centred on it (the
        -- "..." sits at the box's middle), moved only as far as needed to
        -- stay on screen; the arrow points at the anchor's middle.
        local mid = a.y + math.floor(a.h / 2)
        local fx = math.max(margin, a.x - arrow_h - fw)
        local fy = math.max(margin, math.min(H - margin - fh, mid - math.floor(fh / 2)))
        self.frame_dimen = Geom:new{ x = fx, y = fy, w = fw, h = fh }
        self:recordRows(fx, fy, border, pad, row_h, line_h, items)
        return KoboldPopup.placeSide(self.dimen, fx, fy, box, mid)
    end

    -- Below the anchor when it fits, else above it; never off screen.
    local below = a.y + a.h + arrow_h + fh + margin <= H
    local fy = below and (a.y + a.h + arrow_h) or (a.y - arrow_h - fh)
    local fx = self.align == "left" and a.x or (a.x + a.w - fw)
    fx = math.max(margin, math.min(W - margin - fw, fx))
    fy = math.max(margin, fy)

    self.frame_dimen = Geom:new{ x = fx, y = fy, w = fw, h = fh }
    self:recordRows(fx, fy, border, pad, row_h, line_h, items)
    return KoboldPopup.place(self.dimen, fx, fy, box, a.x + math.floor(a.w / 2), not below)
end

-- Tap rectangle of each row, in screen coordinates.
function KoboldBookMenu:recordRows(fx, fy, border, pad, row_h, line_h, items)
    self.rows = {}
    local y = fy + border + pad
    for i, item in ipairs(items) do
        self.rows[i] = { rect = Geom:new{ x = fx, y = y, w = self.frame_dimen.w, h = row_h }, action = item.action }
        y = y + row_h + line_h
    end
end

function KoboldBookMenu:init()
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

function KoboldBookMenu:onTapMenu(_, ges)
    for _i, row in ipairs(self.rows) do
        if ges.pos:intersectWith(row.rect) then
            self:onClose()
            UIManager:nextTick(function() self:run(row.action) end)
            return true
        end
    end
    -- Outside the rows: just close.
    return self:onClose()
end

function KoboldBookMenu:run(action)
    if action == "read" then
        require("kobold.ui.reader").open(self.screen, self.file)
    elseif action == "details" then
        require("kobold.ui.book_details").show(self.file, self.screen, self.on_change)
    elseif action == "koreader" then
        if not KoboldWidgets.showBookMenu(self.file, self.on_change) then
            UIManager:show(require("ui/widget/infomessage"):new{
                text = _("The KOReader book menu is not available."),
            })
        end
    end
end

function KoboldBookMenu:onClose()
    KoboldPopup.close(self)
    return true
end

-- Opens the menu. opts = { file, screen, anchor (Geom), align, side, on_change }.
-- With Kobold Settings > Book menu set to KOReader, KOReader's own book menu
-- opens directly instead.
function KoboldBookMenu.show(opts)
    if require("kobold.data.prefs").get("book_menu") == "koreader" then
        if not KoboldWidgets.showBookMenu(opts.file, opts.on_change) then
            UIManager:show(require("ui/widget/infomessage"):new{
                text = _("The KOReader book menu is not available."),
            })
        end
        return
    end
    KoboldPopup.show(KoboldBookMenu:new(opts))
end

return KoboldBookMenu
