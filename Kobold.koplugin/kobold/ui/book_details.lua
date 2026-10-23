-- kobold/ui/book_details.lua — Kobold
-- Kobold's book details page (View Details in the book menu), in the same
-- inset panel style as Settings: the cover, title, series, author and
-- progress, a Read now button and a "..." for KOReader's own book menu, then
-- Synopsis and Details tabs. The data comes from KOReader (its book info,
-- with any corrections made in Book information).

local Blitbuffer      = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device          = require("device")
local Font            = require("ui/font")
local FrameContainer  = require("ui/widget/container/framecontainer")
local Geom            = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan  = require("ui/widget/horizontalspan")
local InputContainer  = require("ui/widget/container/inputcontainer")
local LeftContainer   = require("ui/widget/container/leftcontainer")
local LineWidget      = require("ui/widget/linewidget")
local OverlapGroup    = require("ui/widget/overlapgroup")
local RightContainer  = require("ui/widget/container/rightcontainer")
local ScrollTextWidget = require("ui/widget/scrolltextwidget")
local TextBoxWidget   = require("ui/widget/textboxwidget")
local TextWidget      = require("ui/widget/textwidget")
local UIManager       = require("ui/uimanager")
local VerticalGroup   = require("ui/widget/verticalgroup")
local VerticalSpan    = require("ui/widget/verticalspan")
local lfs             = require("libs/libkoreader-lfs")
local _               = require("gettext")
local KoboldLibrary   = require("kobold.data.library")
local KoboldMyBooksData = require("kobold.data.mybooks")
local KoboldPopup     = require("kobold.ui.popup")
local KoboldTaps      = require("kobold.ui.taps")
local KoboldWidgets   = require("kobold.ui.widgets")

local Screen = Device.screen

local KoboldBookDetails = InputContainer:extend{
    name = "kobold_book_details",
    file = nil,
    screen = nil,    -- the Kobold screen it opened from
    on_change = nil, -- runs after the KOReader menu changed something
    tab = "synopsis",
}

local function italicFace(size)
    local ok, face = pcall(function() return KoboldWidgets.italicFace(size) end)
    if ok and face then return face end
    return KoboldWidgets.face(size)
end

local function nonEmpty(s)
    if type(s) ~= "string" then return nil end
    s = s:match("^%s*(.-)%s*$")
    return s ~= "" and s or nil
end

-- Book facts from KOReader's book info (title, authors, series, language,
-- keywords, description, pages), with corrections from Book information.
-- The book is not opened for this.
local function bookProps(file)
    local props = {}
    local ok_fm, FileManager = pcall(require, "apps/filemanager/filemanager")
    local bookinfo = ok_fm and FileManager and FileManager.instance and FileManager.instance.bookinfo
    if bookinfo and bookinfo.getDocProps then
        local ok, p = pcall(bookinfo.getDocProps, bookinfo, file, nil, true)
        if ok and type(p) == "table" then props = p end
        local ok_x, extended = pcall(function() return bookinfo.extendProps(props, file) end)
        if ok_x and type(extended) == "table" then props = extended end
    end
    -- Fall back to the sidecar for anything missing.
    local info = KoboldLibrary.getDocInfoCached(file) or {}
    props.title = nonEmpty(props.title) or nonEmpty(props.display_title) or info.title
    props.authors = nonEmpty(props.authors) or info.authors
    props.series = nonEmpty(props.series) or info.series
    props.series_index = props.series_index or info.series_index
    props.pages = props.pages or info.pages
    return props, info
end

-- Description without HTML, as KOReader shows it.
local function plainText(s)
    s = nonEmpty(s)
    if not s then return nil end
    local ok, util = pcall(require, "util")
    if ok and util.htmlToPlainTextIfHtml then
        local ok2, out = pcall(util.htmlToPlainTextIfHtml, s)
        if ok2 and out then return nonEmpty(out) end
    end
    return nonEmpty((s:gsub("<[^>]+>", "")))
end

local function statusLine(info)
    if info.status == "complete" then return _("Finished") end
    if info.percent and info.percent > 0 then
        return string.format(_("%d%% read"), math.floor(info.percent * 100 + 0.5))
    end
    return _("Unread")
end

function KoboldBookDetails:build()
    local R = KoboldPopup.panelRect()
    local border  = Screen:scaleBySize(2)
    local pad     = Screen:scaleBySize(20)
    local inner_w = R.w - 2 * (border + pad)
    local inner_h = R.h - 2 * (border + pad)
    local x0, y0  = R.x + border + pad, R.y + border + pad
    local top_h   = Screen:scaleBySize(40)
    local gap     = Screen:scaleBySize(16)
    local close_sz = Screen:scaleBySize(26)
    self.panel_rect = R

    local file = self.file
    local props, info = bookProps(file)
    local title = props.title or (file:match("([^/]+)$") or file)

    -- Header: cover on the left, text and buttons on the right.
    local cover_w = math.floor(inner_w * 0.34)
    local cover_h = math.floor(cover_w * 1.5)
    local text_w  = inner_w - cover_w - gap
    local text = VerticalGroup:new{
        align = "left",
        TextBoxWidget:new{ text = title, face = KoboldWidgets.face(22), width = text_w },
    }
    if props.series then
        local series = props.series:upper()
        if props.series_index then
            local n = tonumber(props.series_index)
            if n and n == math.floor(n) then n = math.floor(n) end
            series = series .. " - " .. tostring(n or props.series_index)
        end
        text[#text + 1] = VerticalSpan:new{ width = Screen:scaleBySize(4) }
        text[#text + 1] = TextWidget:new{ text = series, face = KoboldWidgets.face(13), max_width = text_w }
    end
    if props.authors then
        text[#text + 1] = VerticalSpan:new{ width = Screen:scaleBySize(6) }
        text[#text + 1] = TextWidget:new{
            text = (props.authors:gsub("\n", ", ")), face = KoboldWidgets.face(16), max_width = text_w,
        }
    end
    text[#text + 1] = VerticalSpan:new{ width = Screen:scaleBySize(6) }
    text[#text + 1] = TextWidget:new{
        text = statusLine(info), face = KoboldWidgets.face(14), fgcolor = KoboldWidgets.subtitleColor(),
    }

    -- Buttons: a grey "Read now" and a round grey "...".
    local button_h = Screen:scaleBySize(48)
    local read_w = math.min(Screen:scaleBySize(160), text_w - button_h - gap)
    local grey = Blitbuffer.COLOR_LIGHT_GRAY
    local read_button = FrameContainer:new{
        bordersize = 0, padding = 0, background = grey,
        CenterContainer:new{
            dimen = Geom:new{ w = read_w, h = button_h },
            TextWidget:new{ text = _("Read now"), face = italicFace(18) },
        },
    }
    local dots_button = FrameContainer:new{
        bordersize = 0, padding = 0, background = grey, radius = math.floor(button_h / 2),
        CenterContainer:new{
            dimen = Geom:new{ w = button_h, h = button_h },
            TextWidget:new{ text = "…", face = KoboldWidgets.face(18), bold = true },
        },
    }
    local text_h = text:getSize().h
    local buttons_y = y0 + top_h + text_h + gap
    self.read_rect = Geom:new{ x = x0 + cover_w + gap, y = buttons_y, w = read_w, h = button_h }
    self.dots_rect = Geom:new{ x = x0 + cover_w + gap + read_w + gap, y = buttons_y, w = button_h, h = button_h }
    local right = VerticalGroup:new{
        align = "left",
        text,
        VerticalSpan:new{ width = gap },
        HorizontalGroup:new{ read_button, HorizontalSpan:new{ width = gap }, dots_button },
    }
    local header_h = math.max(cover_h, right:getSize().h)

    -- Tabs: Synopsis and Details, the chosen one bold and underlined.
    local tabs_h = Screen:scaleBySize(44)
    local tab_gap = Screen:scaleBySize(28)
    local bar_h = Screen:scaleBySize(3)
    local tabs_y = y0 + top_h + header_h + gap
    local tabs = HorizontalGroup:new{}
    self.tab_rects = {}
    local tx = x0
    for i, t in ipairs({ { id = "synopsis", text = _("Synopsis") }, { id = "details", text = _("Details") } }) do
        local selected = t.id == self.tab
        local label = TextWidget:new{ text = t.text, face = KoboldWidgets.face(17), bold = selected }
        local w = label:getSize().w
        if i > 1 then tabs[#tabs + 1] = HorizontalSpan:new{ width = tab_gap } end
        tabs[#tabs + 1] = VerticalGroup:new{
            align = "left",
            CenterContainer:new{ dimen = Geom:new{ w = w, h = tabs_h - bar_h }, label },
            LineWidget:new{
                dimen = Geom:new{ w = w, h = bar_h },
                background = selected and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_WHITE,
            },
        }
        self.tab_rects[t.id] = Geom:new{ x = tx - tab_gap / 2, y = tabs_y, w = w + tab_gap, h = tabs_h }
        tx = tx + w + tab_gap
    end

    -- Tab content fills the rest of the panel; long text scrolls.
    local body_h = math.max(Screen:scaleBySize(60), inner_h - top_h - header_h - gap - tabs_h - gap)
    local body_text
    if self.tab == "synopsis" then
        body_text = plainText(props.description) or _("No synopsis.")
    else
        local lines = {}
        local function add(label, value) if value then lines[#lines + 1] = label .. " " .. tostring(value) end end
        add(_("Language:"), nonEmpty(props.language))
        add(_("Keywords:"), nonEmpty(props.keywords) and props.keywords:gsub("\n", ", "))
        add(_("Pages:"), props.pages)
        add(_("File name:"), file:match("([^/]+)$"))
        add(_("Path:"), file:match("^(.*)/[^/]+$"))
        add(_("File size:"), KoboldMyBooksData.formatSize(lfs.attributes(file, "size")))
        add(_("File format:"), (file:match("%.([^%./]+)$") or ""):upper())
        body_text = table.concat(lines, "\n")
    end
    local body = ScrollTextWidget:new{
        text = body_text, face = KoboldWidgets.face(15),
        width = inner_w, height = body_h, dialog = self,
    }

    self.close_rect = Geom:new{ x = x0 + inner_w - close_sz - pad, y = R.y, w = close_sz + 2 * pad, h = top_h + pad }
    local panel = FrameContainer:new{
        bordersize = border, padding = pad,
        radius = KoboldPopup.radius(),
        background = Blitbuffer.COLOR_WHITE,
        VerticalGroup:new{
            align = "left",
            OverlapGroup:new{
                dimen = Geom:new{ w = inner_w, h = top_h },
                CenterContainer:new{
                    dimen = Geom:new{ w = inner_w, h = top_h },
                    TextWidget:new{ text = _("Book Details"), face = KoboldWidgets.face(18) },
                },
                RightContainer:new{
                    dimen = Geom:new{ w = inner_w, h = top_h },
                    KoboldWidgets.icon("close", close_sz),
                },
            },
            KoboldWidgets.fixed(inner_w, header_h, HorizontalGroup:new{
                align = "top",
                KoboldWidgets.makeCover(file, cover_w, cover_h),
                HorizontalSpan:new{ width = gap },
                right,
            }),
            VerticalSpan:new{ width = gap },
            tabs,
            LineWidget:new{ dimen = Geom:new{ w = inner_w, h = Screen:scaleBySize(1) }, background = Blitbuffer.COLOR_LIGHT_GRAY },
            VerticalSpan:new{ width = gap - Screen:scaleBySize(1) },
            body,
        },
    }
    return KoboldPopup.place(self.dimen, R.x, R.y, panel)
end

function KoboldBookDetails:init()
    local W, H = Screen:getWidth(), Screen:getHeight()
    self.dimen = Geom:new{ x = 0, y = 0, w = W, h = H }
    if Device:hasKeys() then
        self.key_events = { Close = { { Device.input.group.Back } } }
    end
    self[1] = self:build()
    KoboldTaps.add(self, "KoboldDetailsTap", 0, 0, W, H, function(ges)
        local pos = ges.pos
        if pos:intersectWith(self.close_rect) then
            self:onClose()
        elseif pos:intersectWith(self.read_rect) then
            self:onClose()
            require("kobold.ui.reader").open(self.screen, self.file)
        elseif pos:intersectWith(self.dots_rect) then
            if not KoboldWidgets.showBookMenu(self.file, function()
                if self.on_change then self.on_change() end
                self:refresh()
            end) then
                UIManager:show(require("ui/widget/infomessage"):new{
                    text = _("The KOReader book menu is not available."),
                })
            end
        else
            for id, rect in pairs(self.tab_rects) do
                if pos:intersectWith(rect) and id ~= self.tab then
                    self.tab = id
                    self:refresh()
                    return
                end
            end
        end
    end)
end

function KoboldBookDetails:refresh()
    if self.closed then return end
    self[1] = self:build()
    UIManager:setDirty(self, function() return "ui", self.panel_rect end)
end

function KoboldBookDetails:onClose()
    self.closed = true
    UIManager:close(self, "ui", self.panel_rect)
    return true
end

-- Opens the details page for `file`, over `screen` (the Kobold screen).
function KoboldBookDetails.show(file, screen, on_change)
    local w = KoboldBookDetails:new{ file = file, screen = screen, on_change = on_change }
    UIManager:show(w, "ui", w.panel_rect)
end

return KoboldBookDetails
