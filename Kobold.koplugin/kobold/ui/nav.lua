-- kobold/ui/nav.lua — Kobold
-- Bottom navigation bar shared by the Kobold screens. Discover is omitted.
-- Each tab has a bar above it: black for the selected tab, light gray for the rest.

local Blitbuffer      = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device          = require("device")
local Geom            = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local LineWidget      = require("ui/widget/linewidget")
local TextWidget      = require("ui/widget/textwidget")
local VerticalGroup   = require("ui/widget/verticalgroup")
local VerticalSpan    = require("ui/widget/verticalspan")
local KoboldRouter    = require("kobold.ui.router")
local KoboldTaps      = require("kobold.ui.taps")
local KoboldWidgets   = require("kobold.ui.widgets")

local Screen = Device.screen

local KoboldNav = {}

-- `icon` is one of Kobold's own icons; `fallback` is the KOReader icon used
-- when that file is missing.
local TABS = {
    { id = "home",  text = "Home",     icon = "home",     fallback = "home",      event = "NavHome" },
    { id = "books", text = "My Books", icon = "my-books", fallback = "library",   event = "NavBooks" },
    { id = "more",  text = "More",     icon = "more",     fallback = "appbar.menu", event = "NavMore" },
}

function KoboldNav.height()
    return Screen:scaleBySize(72)
end

-- The bar above one tab: black when the tab is selected, light gray otherwise.
local function tabBar(tab_w, bar_h, selected)
    return LineWidget:new{
        dimen = Geom:new{ w = tab_w, h = bar_h },
        background = selected and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_LIGHT_GRAY,
    }
end

-- Registers the tab tap zones on `screen` (sized W x H) and returns the nav
-- widget, pushed to the bottom edge. Use it inside an OverlapGroup.
function KoboldNav.attach(screen, W, H, active)
    local nav_h = KoboldNav.height()
    local bar_h = Screen:scaleBySize(3)
    local tab_w = math.floor(W / #TABS)
    local nav_top = H - nav_h

    local row = HorizontalGroup:new{}
    for i, tab in ipairs(TABS) do
        local id = tab.id
        local selected = tab.id == active
        KoboldTaps.add(screen, tab.event, (i - 1) * tab_w, nav_top, tab_w, nav_h, function()
            KoboldRouter.show(id, screen)
        end)
        row[#row + 1] = VerticalGroup:new{
            tabBar(tab_w, bar_h, selected),
            CenterContainer:new{
                dimen = Geom:new{ w = tab_w, h = nav_h - bar_h },
                VerticalGroup:new{
                    KoboldWidgets.customIcon(tab.icon, Screen:scaleBySize(24), tab.fallback),
                    VerticalSpan:new{ width = Screen:scaleBySize(3) },
                    TextWidget:new{
                        text = tab.text,
                        face = KoboldWidgets.face(16),
                        bold = selected,
                    },
                },
            },
        }
    end

    return VerticalGroup:new{
        VerticalSpan:new{ width = nav_top },
        row,
    }
end

return KoboldNav
