-- kobold/ui/widgets.lua — Kobold
-- Small widget helpers shared by the Kobold screens.

local Blitbuffer      = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device          = require("device")
local FrameContainer  = require("ui/widget/container/framecontainer")
local Font            = require("ui/font")
local Geom            = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan  = require("ui/widget/horizontalspan")
local IconWidget      = require("ui/widget/iconwidget")
local ImageWidget     = require("ui/widget/imagewidget")
local TextBoxWidget   = require("ui/widget/textboxwidget")
local TextWidget      = require("ui/widget/textwidget")
local UIManager       = require("ui/uimanager")
local VerticalGroup   = require("ui/widget/verticalgroup")
local VerticalSpan    = require("ui/widget/verticalspan")
local lfs             = require("libs/libkoreader-lfs")
local LineWidget      = require("ui/widget/linewidget")
local OverlapGroup    = require("ui/widget/overlapgroup")
local KoboldMeta      = require("kobold.meta")
local KoboldCovers    = require("kobold.data.covers")
local KoboldPrefs     = require("kobold.data.prefs")
local KoboldBattery   = require("kobold.ui.battery")
local KoboldTaps      = require("kobold.ui.taps")

local Screen = Device.screen

local KoboldWidgets = {}

-- A box exactly w x h with `child` drawn at its top-left corner. Use this
-- instead of FrameContainer width/height: FrameContainer:getSize() ignores
-- those and reports its content's size, so groups lay it out too small.
function KoboldWidgets.fixed(w, h, child)
    return OverlapGroup:new{
        dimen = Geom:new{ w = w, h = h },
        child,
    }
end

function KoboldWidgets.face(size)
    return Font:getFace("cfont", size)
end

function KoboldWidgets.bookTitle(file)
    local t = file:match("([^/]+)%.[^%.]+$") or file
    if #t > 40 then t = t:sub(1, 37) .. "..." end
    return t
end

-- Size of a real cover fitted inside w x h, keeping its aspect ratio.
-- Returns w, h unchanged when there is no cover (placeholder size).
function KoboldWidgets.coverSize(file, w, h)
    local sw, sh = KoboldCovers.fittedSize(file, w, h)
    if not sw then return w, h end
    return sw, sh
end

-- Real cover when KOReader has one, otherwise a bordered title placeholder.
-- A nil file yields a blank slot of the same w x h so rows stay aligned.
-- Covers come from the shared memory cache (data/covers.lua), so drawing the
-- same book again on another screen or page costs no decode.
-- opts.outline draws a thin dark line around the cover (Home), as the
-- e-reader's own home screen does; the cover shrinks to keep the outline
-- inside w x h.
function KoboldWidgets.makeCover(file, w, h, opts)
    if not file then
        return KoboldWidgets.fixed(w, h, HorizontalSpan:new{ width = w })
    end
    -- Every cover gets the thin outline unless a caller turns it off.
    local line = (opts and opts.outline == false) and 0 or Screen:scaleBySize(1)
    local bb = KoboldCovers.get(file, w, h)
    if bb then
        local sw, sh = KoboldCovers.fittedSize(file, w - 2 * line, h - 2 * line)
        local image = ImageWidget:new{
            image = bb,
            image_disposable = false,
            width = sw,
            height = sh,
            scale_factor = 0,
        }
        if line == 0 then return image end
        return FrameContainer:new{
            bordersize = line, padding = 0,
            color = Blitbuffer.COLOR_DARK_GRAY,
            image,
        }
    end
    -- Sized by its content: inner box + padding + border = exactly w x h.
    local pad = Screen:scaleBySize(8)
    local border = Screen:scaleBySize(1)
    return FrameContainer:new{
        bordersize = border,
        background = Blitbuffer.COLOR_LIGHT_GRAY,
        padding = pad,
        CenterContainer:new{
            dimen = Geom:new{ w = w - 2 * (pad + border), h = h - 2 * (pad + border) },
            TextBoxWidget:new{
                text = KoboldWidgets.bookTitle(file),
                face = KoboldWidgets.face(12),
                width = w - 3 * pad,
                alignment = "center",
            },
        },
    }
end

-- Row of n covers taken from `files`, separated by `gap`.
function KoboldWidgets.coverRow(files, n, w, h, gap)
    local row = HorizontalGroup:new{}
    for i = 1, n do
        if i > 1 then row[#row + 1] = HorizontalSpan:new{ width = gap } end
        row[#row + 1] = KoboldWidgets.makeCover(files[i], w, h)
    end
    return row
end

-- Folders IconWidget looks in for icons, user folder first.
local icon_dirs = nil
local function iconDirs()
    if icon_dirs then return icon_dirs end
    icon_dirs = {}
    local ok, DataStorage = pcall(require, "datastorage")
    if ok and DataStorage then icon_dirs[#icon_dirs + 1] = DataStorage:getDataDir() .. "/icons" end
    icon_dirs[#icon_dirs + 1] = "resources/icons/mdlight"
    icon_dirs[#icon_dirs + 1] = "resources/icons"
    return icon_dirs
end

-- True when an icon file with this name exists. IconWidget does not fail on
-- a missing icon (it draws a warning sign), so this is checked up front.
function KoboldWidgets.hasIcon(name)
    for _i, dir in ipairs(iconDirs()) do
        for _j, ext in ipairs({ ".svg", ".png" }) do
            if lfs.attributes(dir .. "/" .. name .. ext, "mode") == "file" then return true end
        end
    end
    return false
end

-- KOReader's built-in icon by name (e.g. "home", "appbar.settings"), sized
-- size x size. Falls back to an outlined placeholder if the icon fails to load.
-- opts (optional):
--   rotation = degrees, e.g. 180 turns chevron.up into a down chevron
--   fallback = icon used instead when `name` does not exist
-- Icons are drawn with alpha: IconWidget's default (alpha = false) flattens
-- the SVG onto white, which shows as a white box on the gray pills.
function KoboldWidgets.icon(name, size, opts)
    opts = opts or {}
    if opts.fallback and not KoboldWidgets.hasIcon(name) then name = opts.fallback end
    local ok, widget = pcall(function()
        return IconWidget:new{
            icon = name, width = size, height = size,
            rotation_angle = opts.rotation or 0,
            alpha = true,
        }
    end)
    if ok and widget then return widget end
    return KoboldWidgets.iconPlaceholder(size)
end

-- Path of an SVG icon file by name, or nil.
local function iconSvgPath(name)
    for _i, dir in ipairs(iconDirs()) do
        local path = dir .. "/" .. name .. ".svg"
        if lfs.attributes(path, "mode") == "file" then return path end
    end
    return nil
end

-- Writes a copy of SVG icon `name` turned by `degrees` around its centre to
-- Kobold's cache folder and returns its path, or nil. Bitmaps can only be
-- turned in steps of 90 degrees, so the turn is done in the SVG itself by
-- wrapping its drawing in a rotate transform.
local rotated_svgs = {}
local function rotatedSvg(name, degrees)
    local key = name .. "@" .. degrees
    if rotated_svgs[key] ~= nil then return rotated_svgs[key] or nil end
    rotated_svgs[key] = false
    local src = iconSvgPath(name)
    if not src then return nil end
    local ok, out = pcall(function()
        local f = assert(io.open(src, "rb"))
        local svg = f:read("*a")
        f:close()
        local s_tag, e_tag = svg:find("<svg[^>]*>")
        local close = svg:find("</svg>%s*$")
        if not s_tag or not close then return nil end
        local tag = svg:sub(s_tag, e_tag)
        local vx, vy, vw, vh = (tag:match('viewBox%s*=%s*"([^"]+)"') or ""):match(
            "([%-%d%.]+)[%s,]+([%-%d%.]+)[%s,]+([%-%d%.]+)[%s,]+([%-%d%.]+)")
        if not vx then
            vx, vy = 0, 0
            vw = tonumber((tag:match('width%s*=%s*"([%d%.]+)')))
            vh = tonumber((tag:match('height%s*=%s*"([%d%.]+)')))
            if not vw or not vh then return nil end
        end
        local cx = tonumber(vx) + tonumber(vw) / 2
        local cy = tonumber(vy) + tonumber(vh) / 2
        local turned = svg:sub(1, e_tag)
            .. string.format('<g transform="rotate(%s %s %s)">', degrees, cx, cy)
            .. svg:sub(e_tag + 1, close - 1) .. "</g></svg>\n"
        local DataStorage = require("datastorage")
        local cache = DataStorage:getDataDir() .. "/cache"
        local dir = cache .. "/kobold_icons"
        if lfs.attributes(cache, "mode") ~= "directory" then lfs.mkdir(cache) end
        if lfs.attributes(dir, "mode") ~= "directory" then lfs.mkdir(dir) end
        local path = dir .. "/" .. name .. "_r" .. degrees .. ".svg"
        local w = assert(io.open(path, "wb"))
        w:write(turned)
        w:close()
        return path
    end)
    if ok and out then
        rotated_svgs[key] = out
        return out
    end
    return nil
end

-- Plus sign for "add" buttons: KOReader's exit icon (an X) turned 45
-- degrees, which has heavier strokes than its plus icon. Falls back to the
-- plus icon when the exit icon cannot be turned.
function KoboldWidgets.plusIcon(size)
    local path = rotatedSvg("exit", 45)
    if path then
        local ok, widget = pcall(function()
            return IconWidget:new{ file = path, width = size, height = size, alpha = true }
        end)
        if ok and widget then return widget end
    end
    return KoboldWidgets.icon("plus", size)
end

-- Down chevron: KOReader has no chevron.down, so chevron.up is turned over.
function KoboldWidgets.chevronDown(size)
    return KoboldWidgets.icon("chevron.up", size, { rotation = 180 })
end

-- Side page bar that makes paged lists read like scrolling ones: an up
-- arrow, a track with a thumb showing where the current page sits, and a
-- down arrow. With a single page only a faint track is drawn.
--   opts = { w = column width, h = bar height, page, pages, arrow = size }
-- Exactly w x h.
function KoboldWidgets.pageBar(opts)
    local w, h, arrow = opts.w, opts.h, opts.arrow
    local line_w  = Screen:scaleBySize(2)
    local thumb_w = Screen:scaleBySize(8)
    local thumb_min_h = Screen:scaleBySize(24)
    local track_h = h - 2 * arrow
    local multi = opts.pages > 1
    local track = OverlapGroup:new{
        dimen = Geom:new{ w = w, h = track_h },
        CenterContainer:new{
            dimen = Geom:new{ w = w, h = track_h },
            LineWidget:new{
                dimen = Geom:new{ w = line_w, h = track_h },
                background = Blitbuffer.COLOR_LIGHT_GRAY,
            },
        },
    }
    if multi then
        local thumb_h = math.max(thumb_min_h, math.floor(track_h / opts.pages))
        local thumb_y = math.floor((track_h - thumb_h) * (opts.page - 1) / (opts.pages - 1))
        -- The thumb's size comes from its content: FrameContainer:getSize()
        -- ignores width/height.
        track[#track + 1] = VerticalGroup:new{
            align = "left",
            VerticalSpan:new{ width = thumb_y },
            HorizontalGroup:new{
                HorizontalSpan:new{ width = math.floor((w - thumb_w) / 2) },
                FrameContainer:new{
                    bordersize = 0, padding = 0,
                    radius = math.floor(thumb_w / 2),
                    background = Blitbuffer.COLOR_DARK_GRAY,
                    KoboldWidgets.fixed(thumb_w, thumb_h, HorizontalSpan:new{ width = 0 }),
                },
            },
        }
    end
    local function arrowCell(icon)
        return CenterContainer:new{
            dimen = Geom:new{ w = w, h = arrow },
            multi and icon or HorizontalSpan:new{ width = arrow },
        }
    end
    return VerticalGroup:new{
        arrowCell(KoboldWidgets.icon("chevron.up", arrow)),
        track,
        arrowCell(KoboldWidgets.chevronDown(arrow)),
    }
end

-- Page a tap on a pageBar asks for: `y` is measured from the bar's top. The
-- arrows step one page (taps above or below the bar count as them), the
-- track jumps to the page at that height. nil with a single page.
function KoboldWidgets.pageBarTarget(y, opts)
    if opts.pages <= 1 then return nil end
    if y < opts.arrow then return opts.page - 1 end
    if y >= opts.h - opts.arrow then return opts.page + 1 end
    local frac = (y - opts.arrow) / math.max(opts.h - 2 * opts.arrow, 1)
    return math.floor(frac * opts.pages) + 1
end

-- Square outlined placeholder, used as the fallback when an icon cannot load.
function KoboldWidgets.iconPlaceholder(size)
    local bs = Screen:scaleBySize(2)
    return FrameContainer:new{
        bordersize = bs,
        padding = 0,
        KoboldWidgets.fixed(size - 2 * bs, size - 2 * bs, HorizontalSpan:new{ width = 0 }),
    }
end

-- Subtitle gray: darker than the old COLOR_DARK_GRAY, lighter than the black
-- titles. Falls back to COLOR_DARK_GRAY if the Color8 constructor is missing.
function KoboldWidgets.subtitleColor()
    local ok, c = pcall(function() return Blitbuffer.Color8(0x22) end)
    if ok and c then return c end
    return Blitbuffer.COLOR_DARK_GRAY
end

-- Wi-Fi icon: wifi.open.100 when Wi-Fi is on, wifi.open.0 otherwise.
-- Only the on/off state is read from NetworkMgr; signal levels are not shown.
function KoboldWidgets.wifiIconName()
    local ok, NetworkMgr = pcall(require, "ui/network/manager")
    if not ok or not NetworkMgr then return "wifi.open.0" end
    local ok_on, on = pcall(function() return NetworkMgr:isWifiOn() end)
    if ok_on and on then return "wifi.open.100" end
    return "wifi.open.0"
end

local STATUS_ICON = 26  -- status bar icon size, before screen scaling
local STATUS_GAP  = 18

-- Widths of the status bar icons, left to right: contrast, Wi-Fi, battery,
-- search. The battery SVG only fills the middle of
-- its square, so it is drawn larger than the others (more so with the
-- percentage inside, to keep the number readable).
local function statusIconWidths()
    local size = Screen:scaleBySize(STATUS_ICON)
    local style = KoboldPrefs.get("battery")
    local battery = math.floor(size * (style == "percent" and 1.7 or 1.3))
    return { size, size, battery, size }, size, Screen:scaleBySize(STATUS_GAP), style
end

-- Shared top status bar: time on the left, then contrast, Wi-Fi, battery and
-- search icons on the right.
function KoboldWidgets.statusBar(content_w)
    local time_text = TextWidget:new{ text = KoboldWidgets.clockText(), face = KoboldWidgets.face(16) }
    local widths, size, gap, style = statusIconWidths()
    local icons = HorizontalGroup:new{
        KoboldWidgets.icon("appbar.contrast", size),
        HorizontalSpan:new{ width = gap },
        KoboldWidgets.icon(KoboldWidgets.wifiIconName(), size),
        HorizontalSpan:new{ width = gap },
        KoboldBattery:new{ size = widths[3], slot_h = size, style = style },
        HorizontalSpan:new{ width = gap },
        KoboldWidgets.icon("lookup.search", size, { fallback = "appbar.search" }),
    }
    local spacer = content_w - time_text:getSize().w - icons:getSize().w
    return HorizontalGroup:new{
        time_text,
        HorizontalSpan:new{ width = math.max(spacer, 0) },
        icons,
    }
end

-- Left edge and width of status bar icon `index` (1 = contrast ... 4 =
-- search), from the same sizes statusBar() uses. Icons sit at the right edge.
local function statusIconX(margin, content_w, index)
    local widths, _size, gap = statusIconWidths()
    local total = (#widths - 1) * gap
    for _i, w in ipairs(widths) do total = total + w end
    local x = margin + content_w - total
    for i = 1, index - 1 do x = x + widths[i] + gap end
    return x, widths[index], gap
end

-- The status bar in a fixed-size frame, for the top of a Kobold screen whose
-- body starts at (margin, margin). Also registers the tap zones over the
-- contrast icon (brightness popup), the Wi-Fi icon (Wi-Fi popup) and the
-- search icon (KOReader's file search). The frame is remembered on `screen`
-- so refreshStatusBar can redraw just the bar.
-- True when the clock shows 24-hour time: Kobold's own choice (clock
-- popup), or KOReader's clock setting when none was made.
function KoboldWidgets.clock24()
    local own = KoboldPrefs.get("clock_24h")
    if own ~= nil then return own == true end
    return not (G_reader_settings and G_reader_settings:isTrue("twelve_hour_clock"))
end

-- Current time for the status bar: "22:42" or "10:42 PM".
function KoboldWidgets.clockText()
    if KoboldWidgets.clock24() then return os.date("%H:%M") end
    return (os.date("%I:%M %p"):gsub("^0", ""))
end

function KoboldWidgets.statusBarFrame(screen, margin, content_w, status_h)
    local frame = KoboldWidgets.fixed(content_w, status_h, KoboldWidgets.statusBar(content_w))
    screen._kobold_status = {
        frame = frame,
        dimen = Geom:new{ x = margin, y = margin, w = content_w, h = status_h },
    }

    -- Icon index -> action, in icon order. Required on tap: the popups use
    -- these helpers themselves.
    local actions = {
        function() require("kobold.ui.brightness").show() end,
        function() require("kobold.ui.wifi").show() end,
        function() require("kobold.ui.battery_popup").show() end,
        KoboldWidgets.showFileSearch,
    }
    for i, action in ipairs(actions) do
        local x, icon_w, icon_gap = statusIconX(margin, content_w, i)
        KoboldTaps.add(screen, "KoboldStatusIcon" .. i, math.floor(x - icon_gap / 2), margin,
            icon_w + icon_gap, status_h, action)
    end
    -- The clock (left third of the bar): tap for the 12/24-hour popup.
    KoboldTaps.add(screen, "KoboldClockTap", margin, margin, math.floor(content_w / 3), status_h,
        function() require("kobold.ui.clock_popup").show() end)
    -- Debug mode: long-press the clock (left third of the bar) to screenshot.
    -- Always registered and checked when pressed, so toggling debug mode on
    -- the About page works on screens that are already open.
    KoboldTaps.hold(screen, "KoboldDebugShot", margin, margin, math.floor(content_w / 3), status_h,
        function()
            if KoboldMeta.debugOn() then KoboldWidgets.debugScreenshot() end
        end)
    return frame
end

-- Redraws the status bar of `screen` (time, Wi-Fi and battery) and refreshes
-- only that strip of the screen.
function KoboldWidgets.refreshStatusBar(screen)
    local s = screen._kobold_status
    if not s then return end
    s.frame[1] = KoboldWidgets.statusBar(s.dimen.w)
    UIManager:setDirty(screen, function() return "ui", s.dimen end)
end

-- Debug mode: saves the screen as it is, through KOReader's own
-- Screenshoter, so the file lands in the screenshot folder set in KOReader
-- and its "saved to..." message confirms it. (Saving with Screen:shot to our
-- own path left no trace when it failed.) The Screenshoter only reads
-- ui.document and ui.file_chooser, neither of which applies here, so it is
-- given an empty ui. Two seconds later a full refresh: the sign that it is
-- safe to let go.
function KoboldWidgets.debugScreenshot()
    local logger = require("logger")
    logger.info("[kobold] debug screenshot")
    local ok, err = pcall(function()
        local Screenshoter = require("ui/widget/screenshoter")
        Screenshoter:new{ ui = {} }:onScreenshot()
    end)
    if not ok then
        logger.warn("Kobold: screenshot failed:", tostring(err))
        local InfoMessage = require("ui/widget/infomessage")
        UIManager:show(InfoMessage:new{ text = "Screenshot failed: " .. tostring(err) })
    end
    UIManager:scheduleIn(2, function() UIManager:setDirty("all", "full") end)
end

-- KOReader's file search (file names, not text inside books), the same
-- dialog as Search in the file browser. Its results open above Kobold.
function KoboldWidgets.showFileSearch()
    local ok, FileManager = pcall(require, "apps/filemanager/filemanager")
    local fm = ok and FileManager and FileManager.instance
    local searcher = fm and fm.filesearcher
    local shown = searcher and searcher.onShowFileSearch
        and pcall(searcher.onShowFileSearch, searcher)
    if not shown then
        local InfoMessage = require("ui/widget/infomessage")
        UIManager:show(InfoMessage:new{ text = require("gettext")("File search is not available.") })
    end
end

-- Adds event handlers every Kobold screen class needs. KOReader broadcasts
-- these events to every open widget.
--   NetworkConnected / NetworkDisconnected: redraw the status bar Wi-Fi icon.
--   Charging / NotCharging / KoboldSettingsChanged: redraw the battery.
--   ShowingReader: a book is opening (from search results, the book menu,
--     ...), so close this screen instead of leaving it under the reader.
-- True for a swipe starting in the left or right edge strip, the same
-- strips KOReader's edge gestures use (1/8 of the width by default).
local function isEdgeSwipe(ev)
    if ev.ges ~= "swipe" or not ev.pos then return false end
    local edge = 1 / 8
    local ok, d = pcall(function() return G_defaults:readSetting("DSWIPE_ZONE_LEFT_EDGE") end)
    if ok and type(d) == "table" and tonumber(d.w) then edge = tonumber(d.w) end
    local W = Screen:getWidth()
    return ev.pos.x < W * edge or ev.pos.x > W * (1 - edge)
end

-- The file browser's Gestures plugin, or nil.
local function gesturesPlugin()
    local FileManager = package.loaded["apps/filemanager/filemanager"]
    local fm = FileManager and FileManager.instance
    return fm, fm and fm.gestures
end

-- Runs fm:onGesture(ev) with KOReader's events sent to every window. The
-- action a KOReader gesture runs (brightness, warmth, refresh, ...) is
-- sent as an event to the top window only, which is Kobold; the file
-- browser that handles it would never see it. SimpleUI does the same.
local function runOnFileBrowser(fm, ev)
    local orig = UIManager.sendEvent
    UIManager.sendEvent = function(_um, e) return UIManager:broadcastEvent(e) end
    local ok, handled = pcall(fm.onGesture, fm, ev)
    UIManager.sendEvent = orig
    return ok and handled and true or false
end

-- Runs a gesture through the file browser's gesture zones. KOReader keeps
-- one set of gestures for the file browser and one for the reader; the
-- file browser's set is tried first, then the reader's (actions that only
-- make sense in a book simply do nothing here). True when one ran.
local function forwardGesture(ev)
    local fm, g = gesturesPlugin()
    if not fm or not fm.onGesture then return false end
    if runOnFileBrowser(fm, ev) then return true end
    local reader_set = g and g.data and g.data.gesture_reader
    if type(reader_set) ~= "table" or g.gestures == reader_set then return false end
    local own = g.gestures
    g.gestures = reader_set
    local handled = runOnFileBrowser(fm, ev)
    g.gestures = own
    return handled
end

-- Name of the corner gesture for a tap or hold at ev.pos, using KOReader's
-- corner zones, or nil when it is not in a corner.
local CORNERS = {
    { key = "DTAP_ZONE_TOP_LEFT",     tap = "tap_top_left_corner",     hold = "hold_top_left_corner" },
    { key = "DTAP_ZONE_TOP_RIGHT",    tap = "tap_top_right_corner",    hold = "hold_top_right_corner" },
    { key = "DTAP_ZONE_BOTTOM_LEFT",  tap = "tap_left_bottom_corner",  hold = "hold_bottom_left_corner" },
    { key = "DTAP_ZONE_BOTTOM_RIGHT", tap = "tap_right_bottom_corner", hold = "hold_bottom_right_corner" },
}
local function cornerGesture(ev)
    if (ev.ges ~= "tap" and ev.ges ~= "hold") or not ev.pos then return nil end
    local W, H = Screen:getWidth(), Screen:getHeight()
    for _i, c in ipairs(CORNERS) do
        local ok, z = pcall(function() return G_defaults:readSetting(c.key) end)
        if ok and type(z) == "table" then
            local x, y = ev.pos.x / W, ev.pos.y / H
            if x >= z.x and x < z.x + z.w and y >= z.y and y < z.y + z.h then
                return c[ev.ges]
            end
        end
    end
    return nil
end

-- True when the user has an action set for corner gesture `name`, in the
-- file browser or reader gestures. Kobold's own taps keep corners that have
-- nothing set.
local function cornerIsSet(name)
    local _fm, g = gesturesPlugin()
    if not name or not g or not g.data then return false end
    for _i, set in ipairs({ g.data.gesture_fm, g.data.gesture_reader }) do
        if type(set) == "table" and set[name] ~= nil then return true end
    end
    return false
end

function KoboldWidgets.addScreenEvents(ScreenClass)
    -- KOReader's own gestures (the Gestures plugin: edge swipes, diagonal
    -- and two-finger gestures, multiswipes, ...) live on the file browser
    -- below Kobold, and KOReader only gives a touch to the top window, so
    -- Kobold passes them on (see forwardGesture). Swipes that start on the
    -- left or right edge go to KOReader first, so edge gestures such as
    -- brightness and warmth win over My Books paging. Corner taps and holds
    -- go to KOReader first when a corner gesture is set. Everything else
    -- goes to Kobold first.
    function ScreenClass:onGesture(ev)
        local InputContainer = require("ui/widget/container/inputcontainer")
        if isEdgeSwipe(ev) and forwardGesture(ev) then return true end
        if cornerIsSet(cornerGesture(ev)) and forwardGesture(ev) then return true end
        if InputContainer.onGesture(self, ev) then return true end
        return forwardGesture(ev)
    end

    -- KOReader changed a book's metadata (Book information, custom title or
    -- author, ...): forget what Kobold remembered and show the new data.
    function ScreenClass:onBookMetadataChanged()
        require("kobold.data.library").forgetDocInfo()
        require("kobold.data.mybooks").forget()
        require("kobold.data.bookinfo").forget()
        if self.scheduleReload then
            self:scheduleReload()
        elseif self.kobold_tab == "home" and self.refreshCovers then
            UIManager:nextTick(function()
                self.data = require("kobold.data.home").getHomeData()
                self:refreshCovers()
            end)
        end
    end

    -- KoboldCoversUpdated: background cover extraction finished; screens
    -- with covers define refreshCovers to redraw with them.
    function ScreenClass:onKoboldCoversUpdated()
        if self.refreshCovers then self:refreshCovers() end
    end
    function ScreenClass:onNetworkConnected() KoboldWidgets.refreshStatusBar(self) end
    function ScreenClass:onNetworkDisconnected() KoboldWidgets.refreshStatusBar(self) end
    -- The device can still report "not charging" when the event arrives,
    -- so the battery is drawn again a moment later.
    function ScreenClass:onCharging()
        KoboldWidgets.refreshStatusBar(self)
        UIManager:scheduleIn(2, function() KoboldWidgets.refreshStatusBar(self) end)
    end
    function ScreenClass:onKoboldSettingsChanged() KoboldWidgets.refreshStatusBar(self) end
    function ScreenClass:onNotCharging()
        KoboldWidgets.refreshStatusBar(self)
        UIManager:scheduleIn(2, function() KoboldWidgets.refreshStatusBar(self) end)
    end
    function ScreenClass:onShowingReader()
        require("kobold.ui.session").rememberScreen(self)
        UIManager:close(self)
    end
end

return KoboldWidgets
