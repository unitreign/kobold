-- kobold/data/plugins.lua — Kobold
-- KOReader plugins (and the file browser's own tools) for custom actions:
-- every entry they put in KOReader's main menu that does something when
-- tapped, and running one of them. Builds no widgets.
--
-- A plugin adds its menu entries in addToMainMenu(menu_items). Calling that
-- on an empty table shows what it would add, without touching the real
-- menu; an entry with a callback is something a button can run.

local logger          = require("logger")

local KoboldPlugins = {}

local function fileBrowser()
    local FileManager = package.loaded["apps/filemanager/filemanager"]
    return FileManager and FileManager.instance
end

-- The entries `module` adds to the main menu: { [key] = item }, or nil.
local function menuEntries(module)
    if type(module) ~= "table" or type(module.addToMainMenu) ~= "function" then return nil end
    local items = {}
    local ok = pcall(module.addToMainMenu, module, items)
    if not ok then return nil end
    return items
end

local function entryTitle(item, fallback)
    local text = item.text
    if not text and type(item.text_func) == "function" then
        local ok, t = pcall(item.text_func)
        if ok then text = t end
    end
    return (type(text) == "string" and text ~= "") and text or fallback
end

-- Every runnable menu entry, sorted by title:
-- { { module = key in the file browser, entry = menu key, title }, ... }.
function KoboldPlugins.list()
    local fm = fileBrowser()
    if not fm then return {} end
    local out, seen = {}, {}
    for key, module in pairs(fm) do
        if type(key) == "string" and not seen[module] then
            local entries = menuEntries(module)
            if entries then
                seen[module] = true
                for entry_key, item in pairs(entries) do
                    if type(item) == "table" and type(item.callback) == "function" then
                        out[#out + 1] = {
                            module = key, entry = entry_key,
                            title = entryTitle(item, entry_key),
                        }
                    end
                end
            end
        end
    end
    table.sort(out, function(a, b) return a.title:lower() < b.title:lower() end)
    return out
end

-- Runs menu entry `entry` of the file browser module `module`. False when
-- it is gone (the plugin was turned off or removed) or failed.
function KoboldPlugins.run(module, entry)
    local fm = fileBrowser()
    local entries = fm and menuEntries(fm[module])
    local item = entries and entries[entry]
    if not (item and type(item.callback) == "function") then return false end
    local ok, err = pcall(item.callback)
    if not ok then logger.warn("Kobold: plugin action failed:", module, entry, tostring(err)) end
    return ok
end

return KoboldPlugins
