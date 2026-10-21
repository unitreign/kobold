-- main.lua — Kobold
-- Plugin entry point. Adds a "Kobold Home" entry to the file browser main menu
-- and a "Kobold Home" option to the "Start with" menu. When that option is
-- selected, Kobold Home opens once at boot. Nothing else is changed.

local WidgetContainer = require("ui/widget/container/widgetcontainer")
local InfoMessage     = require("ui/widget/infomessage")
local UIManager       = require("ui/uimanager")
local _               = require("gettext")

local START_WITH_VALUE = "kobold_home"
local boot_handled = false  -- set once per KOReader session, on the file browser

local Kobold = WidgetContainer:extend{
    name = "kobold",
}

-- Adds the "Kobold Home" radio item to the "Start with" submenu. Patched once
-- per session. The native items are left untouched; each radio item reads the
-- setting directly, so the checkmarks stay in sync.
local function patchStartWithMenu()
    local ok, FileManagerMenu = pcall(require, "apps/filemanager/filemanagermenu")
    if not ok or not FileManagerMenu then return end
    if FileManagerMenu._kobold_startwith_patched then return end

    local orig_fn = FileManagerMenu.getStartWithMenuTable
    if not orig_fn then return end
    FileManagerMenu._kobold_startwith_patched = true

    FileManagerMenu.getStartWithMenuTable = function(fmm_self)
        local result = orig_fn(fmm_self)
        local sub = result.sub_item_table
        if type(sub) ~= "table" then return result end

        local item_text = _("Kobold Home")
        for _i, item in ipairs(sub) do
            if item.text == item_text then return result end
        end

        table.insert(sub, math.max(1, #sub), {
            text = item_text,
            checked_func = function()
                return G_reader_settings:readSetting("start_with") == START_WITH_VALUE
            end,
            callback = function()
                G_reader_settings:saveSetting("start_with", START_WITH_VALUE)
            end,
            radio = true,
        })

        local orig_text_func = result.text_func
        result.text_func = function()
            if G_reader_settings:readSetting("start_with") == START_WITH_VALUE then
                return _("Start with") .. ": " .. item_text
            end
            return orig_text_func and orig_text_func() or _("Start with")
        end
        return result
    end
end

-- This plugin was called Booko before. Moves its saved settings to the new
-- names once, so the Start with choice and My Books filters are kept.
local function migrateOldSettings()
    if not G_reader_settings then return end
    if G_reader_settings:readSetting("start_with") == "boo" .. "ko_home" then
        G_reader_settings:saveSetting("start_with", START_WITH_VALUE)
    end
    for _i, suffix in ipairs({ "mybooks_filter", "mybooks_sort", "mybooks_group_sort" }) do
        local old_key = "boo" .. "ko_" .. suffix
        local old = G_reader_settings:readSetting(old_key)
        if old ~= nil then
            if G_reader_settings:readSetting("kobold_" .. suffix) == nil then
                G_reader_settings:saveSetting("kobold_" .. suffix, old)
            end
            G_reader_settings:delSetting(old_key)
        end
    end
end

function Kobold:init()
    migrateOldSettings()
    patchStartWithMenu()
    -- Windows hidden under Kobold must not refresh the screen (see the module).
    pcall(function() require("kobold.ui.repaint_guard").install() end)

    if self.ui and self.ui.menu then
        self.ui.menu:registerToMainMenu(self)
    end

    -- Back from a book that was opened from Kobold: closing the book builds a
    -- new file browser, which runs this init again. Reopen the Kobold screen
    -- the book was opened from, on top of it.
    if self.ui and not self.ui.document then
        local back = require("kobold.ui.session").take()
        if back then
            boot_handled = true
            -- The screen parked under the book is lifted above this new file
            -- browser as it is shown, so it appears with no rebuild; its data
            -- (progress, last book) is refreshed just after. Without one, the
            -- tab is built fresh. Both use a full refresh, which clears what
            -- the book page left on the screen.
            local Session = require("kobold.ui.session")
            self:showWithFileManager(function()
                local parked = back.screen
                require("kobold.ui.transition").close()
                if parked and Session.raise(parked) then
                    -- KOReader runs waiting tasks before it repaints, so
                    -- the screen is painted first here; only then is its
                    -- data read again (that takes a moment).
                    UIManager:nextTick(function()
                        UIManager:forceRePaint()
                        if parked.onKoboldReturn then parked:onKoboldReturn() end
                    end)
                else
                    self:showTab(back.tab, back.state, "full")
                end
            end)
            return
        end
    end

    -- Boot-time open. Runs only in the file browser (no document open), and
    -- only for the first Kobold init of the session, so returning to the file
    -- browser some other way does not reopen Kobold Home.
    if self.ui and not self.ui.document and not boot_handled then
        boot_handled = true
        if G_reader_settings:readSetting("start_with") == START_WITH_VALUE then
            self:showWithFileManager(function()
                if not self:showHome() then
                    -- Turn the boot open off so a broken screen can't reopen
                    -- on every start. The user can select Kobold Home again.
                    G_reader_settings:saveSetting("start_with", "filemanager")
                end
            end)
        end
    end
end

-- Runs `open` (which shows a Kobold screen) right when KOReader puts this
-- file browser on screen, in the same step, so the browser is never painted
-- before Kobold covers it (it used to flash for a moment when a book
-- closed). UIManager:show is wrapped once for that; the wrapper steps aside
-- after use. If the browser is shown some other way, `open` still runs on
-- the next tick.
function Kobold:showWithFileManager(open)
    local fm = self.ui
    local done = false
    local function run()
        if done then return end
        done = true
        open()
    end
    local orig_show = UIManager.show
    local wrapper
    wrapper = function(um, widget, ...)
        local result = orig_show(um, widget, ...)
        if widget == fm and not done then
            -- Unwrap only if nothing wrapped show after us.
            if UIManager.show == wrapper then UIManager.show = orig_show end
            run()
        end
        return result
    end
    UIManager.show = wrapper
    UIManager:scheduleIn(0, function()
        if UIManager.show == wrapper then UIManager.show = orig_show end
        run()
    end)
end

-- In the reader: the book is closing. When it was opened from Kobold (so
-- Kobold comes back), show the "Closing book" panel while KOReader closes it.
function Kobold:onCloseDocument()
    local Session = require("kobold.ui.session")
    if Session.returning() then
        local _ = require("gettext")
        require("kobold.ui.transition").show(_("Closing Book"))
    end
end

function Kobold:addToMainMenu(menu_items)
    menu_items.kobold_home = {
        text = _("Kobold Home"),
        sorting_hint = "tools",
        callback = function()
            self:showHome()
        end,
    }
end

-- Opens Kobold Home. Errors are caught and shown as a message so a broken
-- screen can't crash KOReader (the menu path and the boot path both use this).
function Kobold:showHome()
    return self:showTab("home")
end

-- Opens the Kobold screen for `tab` ("home", "books" or "more"), with an
-- optional saved state to restore and e-ink refresh type (see router.lua).
-- Errors are shown, not raised.
function Kobold:showTab(tab, state, refresh)
    -- Opened over a book: close the book first, the way KOReader's Home
    -- does. The file browser that replaces it opens Kobold (see init), and
    -- Kobold then has the file browser's menus to work with.
    local ReaderUI = package.loaded["apps/reader/readerui"]
    if ReaderUI and ReaderUI.instance and ReaderUI.instance.onHome then
        require("kobold.ui.session").rememberTab(tab, state)
        local closed = pcall(function() ReaderUI.instance:onHome() end)
        if closed then return true end
        require("kobold.ui.session").take()
    end
    local ok, err = pcall(function()
        require("kobold.ui.router").show(tab, nil, state, refresh)
    end)
    if not ok then
        UIManager:show(InfoMessage:new{
            text = _("Kobold Home failed to open.") .. "\n" .. tostring(err),
        })
    end
    return ok
end

return Kobold
