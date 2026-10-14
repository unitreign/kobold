-- kobold/ui/taps.lua — Kobold
-- Registers named tap zones on a widget.

local Device          = require("device")

local Screen = Device.screen

local KoboldTaps = {}

-- Adds a tap zone at pixel rect (x, y, w, h) to an InputContainer `screen`.
-- KOReader's registerTouchZones expects screen_zone as ratios of the screen
-- size (ratio_x, ratio_y, ratio_w, ratio_h), so pixels are converted here.
-- `id` must be unique per screen; registering the same id again replaces the
-- zone. `handler` gets the gesture (ges.pos is the tap point).
function KoboldTaps.add(screen, id, x, y, w, h, handler)
    local sw, sh = Screen:getWidth(), Screen:getHeight()
    screen:registerTouchZones({
        {
            id = id,
            ges = "tap",
            screen_zone = {
                ratio_x = x / sw,
                ratio_y = y / sh,
                ratio_w = w / sw,
                ratio_h = h / sh,
            },
            handler = function(ges)
                handler(ges)
                return true
            end,
        },
    })
end

-- Like add(), for a long-press ("hold") instead of a tap.
function KoboldTaps.hold(screen, id, x, y, w, h, handler)
    local sw, sh = Screen:getWidth(), Screen:getHeight()
    screen:registerTouchZones({
        {
            id = id,
            ges = "hold",
            screen_zone = { ratio_x = x / sw, ratio_y = y / sh, ratio_w = w / sw, ratio_h = h / sh },
            handler = function(ges)
                handler(ges)
                return true
            end,
        },
    })
end

-- Swipe down from the top edge opens KOReader's file manager menu, the same
-- pull-down menu the file browser has. Kobold screens sit above the file
-- manager, so its own swipe zone never sees the gesture; this forwards it.
-- The zone height matches KOReader's default top menu zone (1/8 of the screen).
function KoboldTaps.topMenu(screen)
    screen:registerTouchZones({
        {
            id = "KoboldTopMenu",
            ges = "swipe",
            screen_zone = {
                ratio_x = 0,
                ratio_y = 0,
                ratio_w = 1,
                ratio_h = 1 / 8,
            },
            handler = function(ges)
                if ges.direction ~= "south" then return false end
                local ok, FileManager = pcall(require, "apps/filemanager/filemanager")
                local menu = ok and FileManager and FileManager.instance and FileManager.instance.menu
                if not menu then return false end
                if menu.onSwipeShowMenu then
                    return menu:onSwipeShowMenu(ges)
                end
                menu:onShowMenu()
                return true
            end,
        },
    })
end

return KoboldTaps
