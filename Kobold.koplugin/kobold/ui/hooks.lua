-- kobold/ui/hooks.lua — Kobold
-- The one place Kobold listens to the file browser refreshing its list.
--
-- The file browser refreshes its list (refreshPath) after every change made
-- from KOReader's book menu: status, delete, reset, and so on. Several Kobold
-- screens want to know: My Books reloads while it is open, and the book menu
-- reloads whatever opened it. Each used to wrap refreshPath on its own, so
-- the wrappers could stack and be undone in the wrong order, leaving a dead
-- screen's hook behind.
--
-- Now refreshPath is wrapped once per file chooser, and the wrapper calls a
-- table of listeners. Adding or removing a listener never touches the
-- wrapper, so the order screens come and go in does not matter. The wrapper
-- holds only data, so it keeps working after Restart Kobold reloads the code.

local UIManager = require("ui/uimanager")

local KoboldHooks = {}

-- The file browser's file chooser, or nil.
function KoboldHooks.fileChooser()
    local FileManager = package.loaded["apps/filemanager/filemanager"]
    local fm = FileManager and FileManager.instance
    return fm and fm.file_chooser
end

-- Removes the wrapper from `fc` when no listener is left, unless something
-- wrapped refreshPath after Kobold did (then the wrapper stays, empty).
local function unwrap(fc, reg)
    if next(reg.listeners) ~= nil then return end
    if rawget(fc, "refreshPath") ~= reg.wrapper then return end
    fc.refreshPath = reg.own  -- nil restores the class method
    rawset(fc, "_kobold_refresh", nil)
end

-- Runs `fn` on the next tick after the file chooser `fc` refreshes its list.
-- `key` names the listener; adding again under the same key replaces it,
-- and `fn` nil removes it. With `once`, it is removed after it runs.
-- False when there is no file chooser to listen to.
function KoboldHooks.onRefresh(fc, key, fn, once)
    if not fc or not fc.refreshPath then return false end
    local reg = rawget(fc, "_kobold_refresh")
    if not reg then
        if not fn then return true end
        reg = { own = rawget(fc, "refreshPath"), orig = fc.refreshPath, listeners = {} }
        reg.wrapper = function(...)
            local result = reg.orig(...)
            for k, l in pairs(reg.listeners) do
                if l.once then reg.listeners[k] = nil end
                UIManager:nextTick(l.fn)
            end
            unwrap(fc, reg)
            return result
        end
        rawset(fc, "_kobold_refresh", reg)
        fc.refreshPath = reg.wrapper
    end
    reg.listeners[key] = fn and { fn = fn, once = once } or nil
    unwrap(fc, reg)
    return true
end

return KoboldHooks
