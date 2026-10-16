-- kobold/updater.lua — Kobold
-- Check for updates and install them over the air, from the More tab.
-- Asks GitHub for the latest release, compares it with KoboldMeta.VERSION,
-- and on request downloads Kobold.koplugin.zip (which holds a
-- Kobold.koplugin folder), unpacks it to a temporary folder and copies it
-- over this plugin's own folder, then offers a KOReader restart.
-- Based on the Mythos updater.

local ConfirmBox  = require("ui/widget/confirmbox")
local DataStorage = require("datastorage")
local InfoMessage = require("ui/widget/infomessage")
local UIManager   = require("ui/uimanager")
local lfs         = require("libs/libkoreader-lfs")
local logger      = require("logger")
local _           = require("gettext")
local KoboldMeta  = require("kobold.meta")

local KoboldUpdater = {}

local ASSET_NAME = "Kobold.koplugin.zip"
local API_URL = "https://api.github.com/repos/unitreign/kobold/releases/latest"

-- True when version string a is newer than b ("v1.2" > "1.1.9").
local function newer(a, b)
    local function parts(v)
        v = (v or ""):match("^v?(.-)[-+]") or (v or ""):match("^v?(.+)$") or ""
        local t = {}
        for n in (v .. "."):gmatch("(%d+)%.") do t[#t + 1] = tonumber(n) or 0 end
        while #t < 3 do t[#t + 1] = 0 end
        return t
    end
    local pa, pb = parts(a), parts(b)
    for i = 1, 3 do
        if pa[i] ~= pb[i] then return pa[i] > pb[i] end
    end
    return false
end

local function request(url, sink, headers)
    local https = require("ssl.https")
    local http = require("socket.http")
    local req = url:match("^https") and https or http
    local h = { ["User-Agent"] = "KOReader-Kobold-Updater" }
    for k, v in pairs(headers or {}) do h[k] = v end
    return req.request{ url = url, sink = sink, headers = h }
end

local function httpGet(url)
    local ltn12 = require("ltn12")
    local out = {}
    local ok, code = request(url, ltn12.sink.table(out), { ["Accept"] = "application/vnd.github.v3+json" })
    if not ok or code ~= 200 then return nil, tostring(code) end
    return table.concat(out)
end

-- Release assets redirect to GitHub's file server; one redirect is followed.
local function download(url, dest)
    local ltn12 = require("ltn12")
    local ok, code, headers = request(url, ltn12.sink.table({}))
    local final = url
    if code == 301 or code == 302 or code == 303 or code == 307 or code == 308 then
        final = headers and (headers.location or headers.Location)
        if not final then return nil, "redirect without a location" end
    elseif not ok or code ~= 200 then
        return nil, tostring(code)
    end
    local fh, err = io.open(dest, "wb")
    if not fh then return nil, tostring(err) end
    local ok2, code2 = request(final, ltn12.sink.file(fh))
    if not ok2 or code2 ~= 200 then
        pcall(os.remove, dest)
        return nil, tostring(code2)
    end
    return true
end

-- { version, url, notes } of the latest release, or nil and a reason.
-- Notes are the text between <!--kobold--> and <!--/kobold--> in the
-- release description, or the start of the description.
local function latestRelease()
    local body, err = httpGet(API_URL)
    if not body then return nil, err end
    local ok, JSON = pcall(require, "rapidjson")
    if not ok then ok, JSON = pcall(require, "json") end
    if not ok then return nil, "no JSON reader" end
    local ok_d, data = pcall(JSON.decode, body)
    if not ok_d or type(data) ~= "table" or not data.tag_name then return nil, "bad release data" end
    local url
    for _i, asset in ipairs(data.assets or {}) do
        if asset.name == ASSET_NAME then url = asset.browser_download_url break end
    end
    local raw = (data.body or ""):gsub("\r\n", "\n")
    local notes = raw:match("<!%-%-kobold%-%->(.-)<!%-%-/kobold%-%->")
    if not notes or not notes:match("%S") then
        notes = #raw > 600 and (raw:sub(1, 600) .. "...") or raw
    end
    notes = notes:match("^%s*(.-)%s*$")
    return { version = data.tag_name:match("^v?(.*)$"), url = url, notes = notes ~= "" and notes or nil }
end

local function sh(cmd)
    local ret = os.execute(cmd)
    return ret == 0 or ret == true
end

-- Downloads and installs `release`. Runs after a short delay so the
-- "Downloading" message is on screen first.
local function install(release)
    local dir = KoboldMeta.DIR
    if not dir then
        UIManager:show(InfoMessage:new{ text = _("Cannot find Kobold's folder. Please update manually.") })
        return
    end
    local work = DataStorage:getSettingsDir() .. "/kobold_update"
    local zip = work .. ".zip"
    local progress = InfoMessage:new{ text = string.format(_("Downloading Kobold %s…"), release.version), timeout = 120 }
    UIManager:show(progress)
    UIManager:scheduleIn(0.3, function()
        local ok, err = download(release.url, zip)
        UIManager:close(progress)
        if not ok then
            UIManager:show(InfoMessage:new{ text = _("Download failed: ") .. tostring(err), timeout = 5 })
            return
        end
        sh(string.format("rm -rf %q", work))
        lfs.mkdir(work)
        local unzipped = sh(string.format("unzip -o -q %q -d %q", zip, work))
        os.remove(zip)
        -- The zip holds one *.koplugin folder; its contents go over ours.
        local inner
        for name in lfs.dir(work) do
            if name:match("%.koplugin$") then inner = work .. "/" .. name end
        end
        local copied = unzipped and inner and sh(string.format("cp -rf %q/. %q/", inner, dir))
        sh(string.format("rm -rf %q", work))
        if not copied then
            logger.err("Kobold: update install failed", tostring(unzipped), tostring(inner))
            UIManager:show(InfoMessage:new{ text = _("Installing the update failed. Please update manually."), timeout = 5 })
            return
        end
        UIManager:show(ConfirmBox:new{
            text = string.format(_("Kobold %s is installed.\n\nRestart KOReader to use it?"), release.version),
            ok_text = _("Restart now"),
            cancel_text = _("Later"),
            ok_callback = function() UIManager:restartKOReader() end,
        })
    end)
end

-- Checks GitHub for a newer release and offers to install it. Turns Wi-Fi
-- on first when needed, the way KOReader's own network features do.
function KoboldUpdater.check()
    local NetworkMgr = require("ui/network/manager")
    NetworkMgr:runWhenOnline(function()
        local checking = InfoMessage:new{ text = _("Checking for updates…"), timeout = 15 }
        UIManager:show(checking)
        UIManager:scheduleIn(0.3, function()
            local release, err = latestRelease()
            UIManager:close(checking)
            if not release then
                UIManager:show(InfoMessage:new{ text = _("Could not check for updates: ") .. tostring(err), timeout = 4 })
                return
            end
            local current = KoboldMeta.VERSION
            if not newer(release.version, current) then
                UIManager:show(InfoMessage:new{
                    text = string.format(_("Kobold is up to date (%s)."), current), timeout = 3,
                })
                return
            end
            if not release.url then
                UIManager:show(InfoMessage:new{
                    text = string.format(_("Kobold %s is out, but its download is not ready yet."), release.version),
                })
                return
            end
            UIManager:show(ConfirmBox:new{
                text = string.format(_("Kobold %s is available. You have %s."), release.version, current)
                    .. (release.notes and ("\n\n" .. release.notes) or "")
                    .. "\n\n" .. _("Download and install now?"),
                ok_text = _("Install"),
                ok_callback = function() install(release) end,
            })
        end)
    end)
end

return KoboldUpdater
