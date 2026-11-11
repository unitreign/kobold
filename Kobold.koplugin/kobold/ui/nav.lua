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
local _               = require("kobold.l10n")
local KoboldRouter    = require("kobold.ui.router")
local KoboldTaps      = require("kobold.ui.taps")
local KoboldWidgets   = require("kobold.ui.widgets")

local Screen = Device.screen

local KoboldNav = {}

-- The built-in tabs. `icon` is one of Kobold's own icons (an outline;
-- "<icon>-filled" is shown when the tab is selected); `fallback` is the
-- KOReader icon used when that file is missing.
local TABS = {
    home  = { text = _("Home"),     icon = "home",     fallback = "home" },
    books = { text = _("My Books"), icon = "my-books", fallback = "library" },
    more  = { text = _("More"),     icon = "more",     fallback = "appbar.menu" },
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
-- widget, pushed to the bottom edge. Use it inside an OverlapGroup. The tabs
-- are the nav bar's items (Kobold Settings > Nav bar): built-in tabs open
-- their screen and show as selected on it; custom actions are buttons that
-- run their action.
function KoboldNav.attach(screen, W, H, active)
    local KoboldBars = require("kobold.data.bars")
    local items = KoboldBars.items("nav")
    local nav_h = KoboldNav.height()
    local bar_h = Screen:scaleBySize(3)
    local tab_w = math.floor(W / #items)
    local nav_top = H - nav_h
    local icon_size = Screen:scaleBySize(24)

    local row = HorizontalGroup:new{}
    for i, id in ipairs(items) do
        local tab = TABS[id]
        local selected = id == active
        local icon, text
        if tab then
            -- The selected tab shows the filled version of its icon.
            icon = KoboldWidgets.customIcon(selected and tab.icon .. "-filled" or tab.icon,
                icon_size, tab.fallback)
            text = tab.text
        else
            local c = KoboldBars.custom(id)
            icon = KoboldWidgets.iconFromSpec(c and c.icon, icon_size)
            text = c and c.name or ""
        end
        -- The tab inverts while pressed, then opens (or runs) on release.
        KoboldTaps.pressable(screen, "KoboldNav" .. i, (i - 1) * tab_w, nav_top, tab_w, nav_h, function()
            if tab then KoboldRouter.show(id, screen) else KoboldBars.runCustom(id) end
        end)
        row[#row + 1] = VerticalGroup:new{
            tabBar(tab_w, bar_h, selected),
            CenterContainer:new{
                dimen = Geom:new{ w = tab_w, h = nav_h - bar_h },
                VerticalGroup:new{
                    icon,
                    VerticalSpan:new{ width = Screen:scaleBySize(3) },
                    TextWidget:new{
                        text = text,
                        face = KoboldWidgets.face(16),
                        bold = selected,
                        max_width = tab_w - Screen:scaleBySize(8),
                    },
                },
            },
        }
    end
    -- Zones of tabs an earlier build had and this one does not.
    for i = #items + 1, screen._kobold_nav_n or 0 do
        if screen.unRegisterTouchZones then
            screen:unRegisterTouchZones({ { id = "KoboldNav" .. i } })
        end
    end
    screen._kobold_nav_n = #items

    return VerticalGroup:new{
        VerticalSpan:new{ width = nav_top },
        row,
    }
end

return KoboldNav
