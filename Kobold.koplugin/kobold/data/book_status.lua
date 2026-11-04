-- kobold/data/book_status.lua — Kobold
-- Changing a book's reading state from Kobold's book menu: mark it finished,
-- mark it unread, or reset it. Written the same way KOReader's own book menu
-- writes them (the book's sidecar), so KOReader agrees. Builds no widgets.

local Event           = require("ui/event")
local UIManager       = require("ui/uimanager")
local logger          = require("logger")
local KoboldLibrary   = require("kobold.data.library")

local KoboldBookStatus = {}

-- Reading progress kept in the sidecar. Mark as unread removes these, so
-- the book opens at the start again; highlights and notes stay.
local PROGRESS_KEYS = { "percent_finished", "last_xpointer", "last_page", "last_epubcfi" }

local function docSettings()
    local ok, DocSettings = pcall(require, "docsettings")
    return ok and DocSettings or nil
end

-- KOReader's cache of book facts for its file lists (newer builds only).
local function setListCache(file, key, value)
    pcall(function() require("ui/widget/booklist").setBookInfoCacheProperty(file, key, value) end)
end

-- Kobold's remembered book facts are read again after a change.
local function forget()
    KoboldLibrary.forgetDocInfo()
    require("kobold.data.mybooks").forget()
end

-- "unread", "reading" or "finished", the way My Books counts them.
function KoboldBookStatus.get(file)
    local info = KoboldLibrary.getDocInfo(file)
    if not info then return "unread" end
    if info.status == "complete" then return "finished" end
    if (info.percent and info.percent > 0) or info.status == "reading"
        or info.status == "abandoned" then
        return "reading"
    end
    return "unread"
end

-- True when the book has been opened (it has a sidecar), so there is
-- something to reset.
function KoboldBookStatus.hasSidecar(file)
    return KoboldLibrary.sidecarStamp(file) ~= nil
end

-- Runs `fn(ds)` on the book's sidecar (created if needed) and saves it.
local function edit(file, fn)
    local DocSettings = docSettings()
    if not DocSettings then return false end
    local ok, err = pcall(function()
        local ds = DocSettings:open(file)
        fn(ds)
        ds:flush()
    end)
    if not ok then logger.warn("Kobold: could not change the status of", file, tostring(err)) end
    forget()
    return ok
end

local function setStatus(ds, status)
    local summary = ds:readSetting("summary") or {}
    summary.status = status
    summary.modified = os.date("%Y-%m-%d", os.time())
    ds:saveSetting("summary", summary)
end

function KoboldBookStatus.markFinished(file)
    local ok = edit(file, function(ds) setStatus(ds, "complete") end)
    if ok then setListCache(file, "status", "complete") end
    return ok
end

-- Clears the status and the reading progress (highlights and notes stay).
function KoboldBookStatus.markUnread(file)
    local ok = edit(file, function(ds)
        setStatus(ds, nil)
        for _i, key in ipairs(PROGRESS_KEYS) do ds:delSetting(key) end
    end)
    if ok then
        setListCache(file, "status", nil)
        setListCache(file, "percent_finished", nil)
    end
    return ok
end

-- What a reset can remove, for the reset dialog: { settings, cover,
-- metadata }, each true when the book has it.
function KoboldBookStatus.resetParts(file)
    local DocSettings = docSettings()
    local parts = { settings = KoboldBookStatus.hasSidecar(file) }
    if DocSettings then
        pcall(function()
            parts.cover = DocSettings:findCustomCoverFile(file) and true or false
            parts.metadata = DocSettings:findCustomMetadataFile(file) and true or false
        end)
    end
    return parts
end

-- Resets the book the way KOReader's Reset does. `purge` = { settings,
-- cover, metadata }, each true to remove that part.
function KoboldBookStatus.reset(file, purge)
    local DocSettings = docSettings()
    if not DocSettings then return false end
    local ok, err = pcall(function()
        local data = {
            doc_settings = purge.settings or false,
            custom_cover_file = purge.cover and DocSettings:findCustomCoverFile(file) or false,
            custom_metadata_file = purge.metadata and DocSettings:findCustomMetadataFile(file) or false,
        }
        DocSettings:open(file):purge(nil, data)
        if data.custom_cover_file or data.custom_metadata_file then
            UIManager:broadcastEvent(Event:new("InvalidateMetadataCache", file))
        end
        if data.doc_settings then
            setListCache(file, "been_opened", false)
            require("readhistory"):fileSettingsPurged(file)
        end
    end)
    if not ok then logger.warn("Kobold: could not reset", file, tostring(err)) end
    forget()
    require("kobold.data.bookinfo").forget()
    return ok
end

return KoboldBookStatus
