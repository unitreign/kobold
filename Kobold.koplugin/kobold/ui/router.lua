-- kobold/ui/router.lua — Kobold
-- Switches between Kobold screens when a bottom-nav tab is tapped.

local UIManager       = require("ui/uimanager")

local KoboldRouter = {}

-- Tabs that have a screen.
local SCREENS = {
    home  = "kobold.ui.home",
    books = "kobold.ui.mybooks",
    more  = "kobold.ui.more",
}

-- Shows the screen for `tab`, closing `current` first. `restore` is a
-- screen's saved return state (see session.lua), or nil.
-- `refresh` is the e-ink refresh for the new screen. Switching screens
-- flashes once by default ("flashui"), like the e-reader's own software
-- does when changing tabs, so every screen starts free of ghosting.
function KoboldRouter.show(tab, current, restore, refresh)
    local module = SCREENS[tab]
    if not module then return end
    if current and current.kobold_tab == tab then return end

    if current then UIManager:close(current) end
    local ScreenClass = require(module)
    local screen = ScreenClass:new{ restore = restore }
    UIManager:show(screen, refresh or "flashui")
    return screen
end

return KoboldRouter
