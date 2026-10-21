-- kobold/ui/popup.lua — Kobold
-- Placement and refresh for the small status bar popups (brightness, Wi-Fi,
-- battery, clock), in the e-reader's own style: a square-cornered box just
-- under the status bar, with a small arrow on top pointing at the icon that
-- opened it. Showing and closing refresh only the box and arrow.

local Blitbuffer      = require("ffi/blitbuffer")
local Device          = require("device")
local Geom            = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan  = require("ui/widget/horizontalspan")
local OverlapGroup    = require("ui/widget/overlapgroup")
local UIManager       = require("ui/uimanager")
local VerticalGroup   = require("ui/widget/verticalgroup")
local VerticalSpan    = require("ui/widget/verticalspan")
local Widget          = require("ui/widget/widget")

local Screen = Device.screen

local KoboldPopup = {}

-- Same margin and status bar height as the Kobold screens.
local function margin() return Screen:scaleBySize(30) end
local function statusH() return Screen:scaleBySize(40) end

-- Height of the arrow above the box, and its border (the box's border).
local function arrowH() return Screen:scaleBySize(12) end
local function border() return Screen:scaleBySize(2) end

-- Corner radius of popup boxes: square, as on the e-reader.
function KoboldPopup.radius()
    return 0
end

-- Screen area of a large panel (Kobold Settings, About): inset from the
-- screen edges, so the screen below shows around it.
function KoboldPopup.panelRect()
    local W, H = Screen:getWidth(), Screen:getHeight()
    local side = Screen:scaleBySize(22)
    local top = Screen:scaleBySize(36)
    return Geom:new{ x = side, y = top, w = W - 2 * side, h = H - top - side }
end

function KoboldPopup.width()
    return math.floor(Screen:getWidth() / 2)
end

-- Gap between the status bar and the box, room for the arrow.
local function topGap() return Screen:scaleBySize(4) + arrowH() end

-- Top-left corner for a popup left-aligned under the status bar (the clock).
function KoboldPopup.originLeft()
    return margin(), margin() + statusH() + topGap()
end

-- Top-left corner of a box `fw` wide: its right edge lines up with the right
-- edge of the status bar.
function KoboldPopup.origin(fw)
    local x = Screen:getWidth() - margin() - fw
    local y = margin() + statusH() + topGap()
    return x, y
end

-- Screen x of the middle of each status bar item, recorded when the bar is
-- built (widgets.lua): "clock", "brightness", "wifi", "battery", "search".
local anchors = {}

function KoboldPopup.setAnchor(name, x)
    anchors[name] = x
end

function KoboldPopup.anchor(name)
    return anchors[name]
end

-- The arrow: a triangle pointing up, outlined like the box, whose base
-- covers the box's top border so the two read as one shape.
local Arrow = Widget:extend{
    cx = 0,        -- screen x of the tip
    box_top = 0,   -- screen y of the box's top edge
}

function Arrow:paintTo(bb)
    local h, b = arrowH(), border()
    local inner = math.ceil(b * 1.42)  -- border measured across the slope
    local top = self.box_top - h
    for r = 0, h + b - 1 do
        local y = top + r
        if r < h then
            bb:paintRect(self.cx - r, y, 2 * r + 1, 1, Blitbuffer.COLOR_BLACK)
        end
        local half = r - inner
        if half >= 0 then
            bb:paintRect(self.cx - half, y, 2 * half + 1, 1, Blitbuffer.COLOR_WHITE)
        end
    end
end

function Arrow:getSize()
    return Geom:new{ w = 0, h = 0 }
end

-- Full-screen transparent layer with `box` drawn at (fx, fy). With
-- `arrow_x` (a screen x, see anchor), an arrow above the box points there;
-- it stays inside the box's width.
function KoboldPopup.place(dimen, fx, fy, box, arrow_x)
    local layer = OverlapGroup:new{
        dimen = dimen,
        VerticalGroup:new{
            align = "left",
            VerticalSpan:new{ width = fy },
            HorizontalGroup:new{ HorizontalSpan:new{ width = fx }, box },
        },
    }
    if arrow_x then
        local w = box:getSize().w
        local h = arrowH()
        local cx = math.max(fx + h + border(), math.min(fx + w - h - border(), arrow_x))
        layer[#layer + 1] = Arrow:new{ cx = cx, box_top = fy }
    end
    return layer
end

-- The part of the screen to refresh for `popup`: its box and the arrow.
local function region(popup)
    local d = popup.frame_dimen
    if not d then return nil end
    local h = arrowH()
    return Geom:new{ x = d.x, y = d.y - h, w = d.w, h = d.h + h }
end

-- Shows `popup` and refreshes only its box (popup.frame_dimen) and arrow.
function KoboldPopup.show(popup)
    UIManager:show(popup, "ui", region(popup))
end

-- Closes `popup`. The screen below is repainted and the box area refreshed,
-- so no trace of the box is left on e-ink.
function KoboldPopup.close(popup)
    UIManager:close(popup, "ui", region(popup))
end

return KoboldPopup
