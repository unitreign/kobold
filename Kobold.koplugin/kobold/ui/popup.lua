-- kobold/ui/popup.lua — Kobold
-- Placement and refresh for the small status bar popups (brightness, Wi-Fi).
-- The box is half the screen wide, right-aligned with the status bar icons,
-- just under the status bar. Showing and closing refresh only the box area.

local Device          = require("device")
local Geom            = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan  = require("ui/widget/horizontalspan")
local OverlapGroup    = require("ui/widget/overlapgroup")
local UIManager       = require("ui/uimanager")
local VerticalGroup   = require("ui/widget/verticalgroup")
local VerticalSpan    = require("ui/widget/verticalspan")

local Screen = Device.screen

local KoboldPopup = {}

-- Same margin and status bar height as the Kobold screens.
local function margin() return Screen:scaleBySize(30) end
local function statusH() return Screen:scaleBySize(40) end

-- Corner radius of the popup box.
function KoboldPopup.radius()
    return Screen:scaleBySize(14)
end

function KoboldPopup.width()
    return math.floor(Screen:getWidth() / 2)
end

-- Top-left corner of a box `fw` wide: its right edge lines up with the right
-- edge of the status bar.
function KoboldPopup.origin(fw)
    local x = Screen:getWidth() - margin() - fw
    local y = margin() + statusH() + Screen:scaleBySize(8)
    return x, y
end

-- Full-screen transparent layer with `box` drawn at (fx, fy).
function KoboldPopup.place(dimen, fx, fy, box)
    return OverlapGroup:new{
        dimen = dimen,
        VerticalGroup:new{
            align = "left",
            VerticalSpan:new{ width = fy },
            HorizontalGroup:new{ HorizontalSpan:new{ width = fx }, box },
        },
    }
end

-- Shows `popup` and refreshes only its box (popup.frame_dimen).
function KoboldPopup.show(popup)
    UIManager:show(popup, "ui", popup.frame_dimen)
end

-- Closes `popup`. The screen below is repainted and the box area refreshed,
-- so no trace of the box is left on e-ink.
function KoboldPopup.close(popup)
    UIManager:close(popup, "ui", popup.frame_dimen)
end

return KoboldPopup
