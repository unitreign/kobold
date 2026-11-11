-- kobold/data/battery_stats.lua — Kobold
-- Battery facts from KOReader's Battery statistics plugin, when it is
-- turned on: the estimated time left since the last charge, and its own
-- statistics page. Builds no widgets.

local KoboldBatteryStats = {}

-- The plugin running in the file browser, or nil.
local function plugin()
    local FileManager = package.loaded["apps/filemanager/filemanager"]
    local fm = FileManager and FileManager.instance
    return fm and fm.batterystat
end

-- The plugin's rows ({ label, value }, ...), as its own page shows them.
local function rows()
    local p = plugin()
    if not p or type(p.stat) ~= "function" then return nil end
    local ok, out = pcall(function()
        local stat = p:stat()
        return stat and stat:dump()
    end)
    return ok and type(out) == "table" and out or nil
end

-- The estimated time left since the last charge ("3d 4h", in KOReader's
-- duration format), or nil when there is not enough data yet.
function KoboldBatteryStats.timeLeft()
    local list = rows()
    if not list then return nil end
    -- The last "remaining" row belongs to "Since last charge", which counts
    -- both awake and sleeping time.
    local found
    for _i, row in ipairs(list) do
        if type(row[1]) == "string" and row[1]:find("remaining") then found = row[2] end
    end
    if type(found) ~= "string" or found == "" or found:find("N/A") then return nil end
    return found
end

-- True unless the plugin is turned off in KOReader's plugin list (it ships
-- with KOReader and is on by default).
function KoboldBatteryStats.available()
    if plugin() then return true end
    local disabled = G_reader_settings and G_reader_settings:readSetting("plugins_disabled")
    return not (type(disabled) == "table" and disabled.batterystat)
end

-- Opens the plugin's own statistics page: directly, or through the event
-- its action uses (the same one gestures send).
function KoboldBatteryStats.open()
    local p = plugin()
    if p and p.onShowBatteryStatistics and pcall(p.onShowBatteryStatistics, p) then return end
    local UIManager = require("ui/uimanager")
    UIManager:broadcastEvent(require("ui/event"):new("ShowBatteryStatistics"))
end

return KoboldBatteryStats
