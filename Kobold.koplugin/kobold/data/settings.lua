-- kobold/data/settings.lua — Kobold
-- Reads KOReader's global settings for display. Builds no widgets.

local KoboldSettings = {}

local MAX_VALUE_LEN = 40

local function formatValue(v)
    local t = type(v)
    if t == "boolean" then return v and "On" or "Off" end
    if t == "table" then return "(table)" end
    local s = tostring(v)
    if #s > MAX_VALUE_LEN then s = s:sub(1, MAX_VALUE_LEN - 3) .. "..." end
    return s
end

-- Every key stored in G_reader_settings (sorted), with its current value.
-- Returns menu rows: { text = key, mandatory = value }.
function KoboldSettings.getKOReaderItems()
    local items = {}
    local data = (G_reader_settings and G_reader_settings.data) or {}

    local keys = {}
    for key in pairs(data) do
        if type(key) == "string" then keys[#keys + 1] = key end
    end
    table.sort(keys)

    for _, key in ipairs(keys) do
        items[#items + 1] = { text = key, mandatory = formatValue(data[key]) }
    end
    return items
end

return KoboldSettings
