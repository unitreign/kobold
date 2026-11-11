-- kobold/ui/switch.lua — Kobold
-- The on/off switch, in the e-reader's style: a rounded track with a round
-- knob that has a ring inside it. Off: white track, knob on the left. On:
-- black track, knob on the right. Used for every on/off in Kobold.

local Blitbuffer      = require("ffi/blitbuffer")
local Device          = require("device")
local Geom            = require("ui/geometry")
local Widget          = require("ui/widget/widget")

local Screen = Device.screen

local KoboldSwitch = Widget:extend{
    on = false,
    height = nil, -- the knob's size; the track is about twice as wide
}

function KoboldSwitch:init()
    self.height = self.height or Screen:scaleBySize(30)
    self.width = math.floor(self.height * 1.85)
    self.dimen = Geom:new{ w = self.width, h = self.height }
end

function KoboldSwitch:getSize()
    return self.dimen
end

-- A filled circle of diameter d at (x, y).
local function circle(bb, x, y, d, color)
    bb:paintRoundedRect(x, y, d, d, color, math.floor(d / 2))
end

-- The round knob alone (also the slider knob in the brightness popup): a
-- white circle of diameter d with a black rim and a ring inside.
function KoboldSwitch.paintKnob(bb, x, y, d)
    local b = math.max(1, Screen:scaleBySize(2))
    circle(bb, x, y, d, Blitbuffer.COLOR_BLACK)
    circle(bb, x + b, y + b, d - 2 * b, Blitbuffer.COLOR_WHITE)
    local ring = math.floor(d * 0.6)
    local rx, ry = x + math.floor((d - ring) / 2), y + math.floor((d - ring) / 2)
    circle(bb, rx, ry, ring, Blitbuffer.COLOR_BLACK)
    local thin = math.max(1, math.floor(b * 0.75))
    circle(bb, rx + thin, ry + thin, ring - 2 * thin, Blitbuffer.COLOR_WHITE)
end

function KoboldSwitch:paintTo(bb, x, y)
    self.dimen.x, self.dimen.y = x, y
    local w, h = self.width, self.height
    local b = math.max(1, Screen:scaleBySize(2))
    local r = math.floor(h / 2)
    -- Track: outline; filled black when on.
    bb:paintRoundedRect(x, y, w, h, Blitbuffer.COLOR_BLACK, r)
    if not self.on then
        bb:paintRoundedRect(x + b, y + b, w - 2 * b, h - 2 * b, Blitbuffer.COLOR_WHITE, r - b)
    end
    -- Knob: a white circle with a black rim and a ring inside.
    KoboldSwitch.paintKnob(bb, self.on and (x + w - h) or x, y, h)
end

return KoboldSwitch
