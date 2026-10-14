-- kobold/ui/battery.lua — Kobold
-- Battery icon for the status bar: icons/battery.svg turned 180 degrees so
-- the tip faces left, with either a black fill that follows the charge or
-- the charge percentage written inside it (Kobold Settings > Battery).

local Blitbuffer      = require("ffi/blitbuffer")
local Device          = require("device")
local Font            = require("ui/font")
local Geom            = require("ui/geometry")
local IconWidget      = require("ui/widget/iconwidget")
local TextWidget      = require("ui/widget/textwidget")
local Widget          = require("ui/widget/widget")
local lfs             = require("libs/libkoreader-lfs")
local KoboldMeta      = require("kobold.meta")

local Screen = Device.screen

local SVG = KoboldMeta.icon("battery.svg")

-- Shown instead while charging, in fill mode only, when the file is present.
-- svgrepo's own download name is accepted too.
local CHARGING_NAMES = { "battery-charging.svg", "battery-charging-svgrepo-com.svg" }

local function chargingSvg()
    for _i, name in ipairs(CHARGING_NAMES) do
        local path = KoboldMeta.icon(name)
        if path and lfs.attributes(path, "mode") == "file" then return path end
    end
    return nil
end

-- Inside of the battery body in the SVG's 24 x 24 grid, after the 180 degree
-- turn: the body's inner edge is x 7..20, y 9..15. The fill keeps one unit
-- clear of the outline.
local INNER = { x = 7, y = 9, w = 13, h = 6 }
local FILL  = { x = 8, y = 10, w = 11, h = 4 }

-- Charge 0..100, or nil when the device does not report it.
local function capacity()
    local ok, level = pcall(function() return Device:getPowerDevice():getCapacity() end)
    if ok and tonumber(level) then return math.max(0, math.min(100, tonumber(level))) end
    return nil
end

local function charging()
    local ok, on = pcall(function() return Device:getPowerDevice():isCharging() end)
    return ok and on and true or false
end

local KoboldBattery = Widget:extend{
    size   = nil,     -- the SVG is drawn size x size
    slot_h = nil,     -- height given to the icon in the status bar row
    style  = "fill",  -- "fill" or "percent"
}

function KoboldBattery:init()
    self.level = capacity()
    local file = SVG
    -- In fill mode, charging shows the charging icon and no fill.
    local charging_svg = self.style ~= "percent" and charging() and chargingSvg()
    if charging_svg then
        file = charging_svg
        self.show_level = false
    else
        self.show_level = true
    end
    if file then
        local ok, icon = pcall(function()
            return IconWidget:new{
                file = file, width = self.size, height = self.size,
                alpha = true, rotation_angle = 180,
            }
        end)
        if ok then self.icon = icon end
    end
    self.dimen = Geom:new{ w = self.size, h = self.slot_h }
end

function KoboldBattery:getSize()
    return self.dimen
end

-- The SVG only uses the middle band of its square, so the square is centred
-- on the row; the transparent parts may reach past the row without showing.
function KoboldBattery:paintTo(bb, x, y)
    self.dimen.x, self.dimen.y = x, y
    local top = y + math.floor((self.slot_h - self.size) / 2)
    if self.icon then self.icon:paintTo(bb, x, top) end
    if not self.level or not self.show_level then return end

    local u = self.size / 24
    local function px(v) return math.floor(v * u + 0.5) end
    if self.style == "percent" then
        local inner_w, inner_h = px(INNER.w), px(INNER.h)
        local text = TextWidget:new{
            text = tostring(math.floor(self.level + 0.5)),
            face = Font:getFace("cfont", math.max(6, math.floor(inner_h * 0.75 / Screen:scaleBySize(1)))),
            bold = true,
            max_width = inner_w,
        }
        local ts = text:getSize()
        text:paintTo(bb, x + px(INNER.x) + math.floor((inner_w - ts.w) / 2),
            top + px(INNER.y) + math.floor((inner_h - ts.h) / 2))
        text:free()
    else
        -- Drains toward the tip: the full part stays on the right.
        local fill_w = px(FILL.w)
        local w = math.floor(fill_w * self.level / 100 + 0.5)
        if w > 0 then
            bb:paintRect(x + px(FILL.x) + fill_w - w, top + px(FILL.y), w, px(FILL.h),
                Blitbuffer.COLOR_BLACK)
        end
    end
end

-- Charge 0..100 (or nil) and whether the device is charging.
function KoboldBattery.state()
    return capacity(), charging()
end

function KoboldBattery:free()
    if self.icon then self.icon:free() end
end

return KoboldBattery
