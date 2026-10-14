-- kobold/ui/more.lua — Kobold
-- More screen, laid out like the Kobo More tab: the shared status bar, the
-- "More" title, then rows with a thin separator under each. Exit Kobold is the
-- last row. Bottom nav is shared with the other screens.

local Blitbuffer      = require("ffi/blitbuffer")
local Device          = require("device")
local FrameContainer  = require("ui/widget/container/framecontainer")
local Geom            = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan  = require("ui/widget/horizontalspan")
local ConfirmBox      = require("ui/widget/confirmbox")
local InfoMessage     = require("ui/widget/infomessage")
local InputContainer  = require("ui/widget/container/inputcontainer")
local LeftContainer   = require("ui/widget/container/leftcontainer")
local LineWidget      = require("ui/widget/linewidget")
local OverlapGroup    = require("ui/widget/overlapgroup")
local TextWidget      = require("ui/widget/textwidget")
local UIManager       = require("ui/uimanager")
local VerticalGroup   = require("ui/widget/verticalgroup")
local VerticalSpan    = require("ui/widget/verticalspan")
local _               = require("gettext")
local KoboldNav       = require("kobold.ui.nav")
local KoboldTaps      = require("kobold.ui.taps")
local KoboldWidgets   = require("kobold.ui.widgets")

local Screen = Device.screen

local KoboldMore = InputContainer:extend{
    -- Not modal: KOReader menus and dialogs (also non-modal) must be able to
    -- open on top of this screen.
    covers_fullscreen = true,
    name = "kobold_more",
    kobold_tab = "more",
}
KoboldWidgets.addScreenEvents(KoboldMore)

function KoboldMore:init()
    local W, H = Screen:getWidth(), Screen:getHeight()
    self.dimen = Geom:new{ x = 0, y = 0, w = W, h = H }

    if Device:hasKeys() then
        self.key_events = {
            Close = { { Device.input.group.Back } },
        }
    end

    local margin    = Screen:scaleBySize(30)
    local content_w = W - 2 * margin
    local status_h  = Screen:scaleBySize(40)
    local title_gap = Screen:scaleBySize(20)
    local title_h   = Screen:scaleBySize(44)
    local row_h     = Screen:scaleBySize(56)
    local line_h    = Screen:scaleBySize(2)
    local icon_size = Screen:scaleBySize(24)
    -- Y of the first row: the body starts at `margin`, then status bar and title.
    local rows_top  = margin + status_h + title_gap + title_h

    -- Two groups with a gap between: Kobold's own rows, then KOReader's.
    local group_gap = Screen:scaleBySize(24)
    local groups = {
        {
            { label = _("Kobold Settings"), icon = "appbar.settings", action = function() self:showKoboldSettings() end },
            { label = _("About Kobold"), icon = "notice-info", fallback = "appbar.menu",
              action = function() self:showAbout() end },
            { label = _("Restart Kobold"), icon = "cre.render.reload", fallback = "tab_history",
              action = function() self:restartKobold() end },
            { label = _("Exit Kobold"), icon = "close", action = function() self:exitKobold() end },
        },
        {
            { label = _("Restart KOReader"), icon = "tab_history", fallback = "appbar.menu",
              action = function() self:confirmKOReader(true) end },
            { label = _("Exit KOReader"), icon = "exit", fallback = "close",
              action = function() self:confirmKOReader(false) end },
        },
    }

    local list = VerticalGroup:new{ align = "left" }
    local top = rows_top
    local n = 0
    for g, rows in ipairs(groups) do
        if g > 1 then
            list[#list + 1] = VerticalSpan:new{ width = group_gap }
            top = top + group_gap
        end
        for _i, row in ipairs(rows) do
            n = n + 1
            list[#list + 1] = self:buildRow(row_h, icon_size, row.icon, row.label, row.fallback)
            list[#list + 1] = LineWidget:new{
                dimen = Geom:new{ w = content_w, h = line_h },
                background = Blitbuffer.COLOR_LIGHT_GRAY,
            }
            KoboldTaps.add(self, "MoreRow" .. n, 0, top, W, row_h, row.action)
            top = top + row_h + line_h
        end
    end

    local body = FrameContainer:new{
        width = W, bordersize = 0, padding = margin, padding_bottom = 0,
        VerticalGroup:new{
            align = "left",
            KoboldWidgets.statusBarFrame(self, margin, content_w, status_h),
            VerticalSpan:new{ width = title_gap },
            LeftContainer:new{
                dimen = Geom:new{ w = content_w, h = title_h },
                TextWidget:new{ text = _("More"), face = KoboldWidgets.face(28) },
            },
            list,
        },
    }

    -- Swipe down from the top edge opens the KOReader menu.
    KoboldTaps.topMenu(self)

    self[1] = FrameContainer:new{
        width = W,
        height = H,
        bordersize = 0,
        padding = 0,
        background = Blitbuffer.COLOR_WHITE,
        OverlapGroup:new{
            dimen = Geom:new{ w = W, h = H },
            body,
            KoboldNav.attach(self, W, H, "more"),
        },
    }
end

-- One list row: KOReader icon (or `fallback` when missing) and a label, vertically centred in row_h.
function KoboldMore:buildRow(row_h, icon_size, icon, label, fallback)
    local text = TextWidget:new{ text = label, face = KoboldWidgets.face(18) }
    -- Centre the taller of icon and text inside the row height, so the row is
    -- exactly row_h tall and the tap zones line up with the separators.
    local content_h = math.max(icon_size, text:getSize().h)
    local top = math.floor((row_h - content_h) / 2)
    return VerticalGroup:new{
        align = "left",
        VerticalSpan:new{ width = top },
        HorizontalGroup:new{
            KoboldWidgets.icon(icon, icon_size, { fallback = fallback }),
            HorizontalSpan:new{ width = Screen:scaleBySize(18) },
            text,
        },
        VerticalSpan:new{ width = row_h - top - content_h },
    }
end

function KoboldMore:showKoboldSettings()
    require("kobold.ui.settings").show()
end

function KoboldMore:showAbout()
    require("kobold.ui.about").show()
end

-- Asks first, then restarts KOReader (the same restart as KOReader's own
-- Exit menu).
function KoboldMore:confirmKOReader(restart)
    UIManager:show(ConfirmBox:new{
        text = restart and _("Restart KOReader?") or _("Exit KOReader?"),
        ok_text = restart and _("Restart") or _("Exit"),
        ok_callback = function()
            if not self:exitKOReader(restart) then
                UIManager:show(InfoMessage:new{ text = _("KOReader cannot do that from here.") })
            end
        end,
    })
end

-- Exits or restarts KOReader the way its own Exit menu does, through the
-- file browser, so settings (the light level among them) are saved first.
-- Returns false when neither way is available.
function KoboldMore:exitKOReader(restart)
    local ok_fm, FileManager = pcall(require, "apps/filemanager/filemanager")
    local menu = ok_fm and FileManager and FileManager.instance and FileManager.instance.menu
    local after = restart and function() UIManager:restartKOReader() end or nil
    if menu and menu.exitOrRestart then
        UIManager:close(self)
        return (pcall(function() menu:exitOrRestart(after) end))
    end
    local ok = pcall(function()
        if restart then UIManager:restartKOReader() else UIManager:quit() end
    end)
    return ok
end

-- Restarts Kobold inside KOReader: closes it, forgets every loaded Kobold
-- module (so the code and its caches are read again from disk) and opens
-- Home fresh. KOReader itself keeps running.
function KoboldMore:restartKobold()
    UIManager:close(self)
    for name in pairs(package.loaded) do
        if name:match("^kobold%.") then package.loaded[name] = nil end
    end
    UIManager:nextTick(function()
        local ok, err = pcall(function() require("kobold.ui.router").show("home") end)
        if not ok then
            UIManager:show(InfoMessage:new{ text = _("Kobold failed to restart.") .. "\n" .. tostring(err) })
        end
    end)
end

-- Closes Kobold and returns to KOReader's file browser.
function KoboldMore:exitKobold()
    UIManager:close(self)
end

function KoboldMore:onClose()
    UIManager:close(self)
    return true
end

return KoboldMore
