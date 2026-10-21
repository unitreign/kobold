-- kobold/ui/settings_list.lua — Kobold
-- Builds a settings list in the style of the e-reader's own settings pages:
-- gray section bands with small capitals, then rows with a title, an
-- optional description under it and a value or action word on the right.
-- Used by the Kobold Settings screen and the reading stats popup.

local Blitbuffer      = require("ffi/blitbuffer")
local Device          = require("device")
local Font            = require("ui/font")
local FrameContainer  = require("ui/widget/container/framecontainer")
local Geom            = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan  = require("ui/widget/horizontalspan")
local LeftContainer   = require("ui/widget/container/leftcontainer")
local LineWidget      = require("ui/widget/linewidget")
local RightContainer  = require("ui/widget/container/rightcontainer")
local TextBoxWidget   = require("ui/widget/textboxwidget")
local TextWidget      = require("ui/widget/textwidget")
local VerticalGroup   = require("ui/widget/verticalgroup")
local VerticalSpan    = require("ui/widget/verticalspan")
local KoboldWidgets   = require("kobold.ui.widgets")

local Screen = Device.screen

local KoboldSettingsList = {}

local function bandColor()
    local ok, c = pcall(function() return Blitbuffer.Color8(0xE4) end)
    if ok and c then return c end
    return Blitbuffer.COLOR_LIGHT_GRAY
end

-- Italic face for action words (Start, Edit, Reset), as on the e-reader.
local function actionFace(size)
    local ok, face = pcall(function() return Font:getFace("infont", size) end)
    if ok and face then return face end
    return KoboldWidgets.face(size)
end

-- Compact rows, as on the e-reader's settings pages: one line per setting,
-- its value on the right. A setting's description is not drawn; tapping its
-- name shows it as a tooltip, tapping its value changes it.
--
-- `spec` is a list of items, top to bottom:
--   { section = "HOME" }                                   a gray band
--   { title, desc = optional, value = optional text,
--     action = true for an italic action word, on_tap = fn }  a row
-- Returns the widget (exactly `w` wide), the tap rectangles
-- { { rect = Geom, on_tap = fn }, ... } in screen coordinates for a list
-- drawn with its top-left corner at (x, y), and the index of the first item
-- left out (nil when everything fit).
-- opts.from: first item to show (default 1). opts.max_h: stop before the
-- list grows past this height; a section band is never left last.
function KoboldSettingsList.build(spec, x, y, w, opts)
    opts = opts or {}
    local band_h   = Screen:scaleBySize(26)
    local band_pad = Screen:scaleBySize(10)
    local row_pad  = Screen:scaleBySize(9)
    local gap      = Screen:scaleBySize(16)
    local line_h   = Screen:scaleBySize(1)
    local value_w  = math.floor(w * 0.38)
    local text_w   = w - value_w - gap
    local from     = opts.from or 1

    -- One item as { widgets = {...}, h = total height, row_h, on_tap }.
    local function piece(i)
        local item = spec[i]
        if item.section then
            local widgets = {}
            if i > from then widgets[#widgets + 1] = VerticalSpan:new{ width = Screen:scaleBySize(6) } end
            widgets[#widgets + 1] = FrameContainer:new{
                bordersize = 0, padding = 0,
                background = bandColor(),
                KoboldWidgets.fixed(w, band_h, LeftContainer:new{
                    dimen = Geom:new{ w = w, h = band_h },
                    HorizontalGroup:new{
                        HorizontalSpan:new{ width = band_pad },
                        TextWidget:new{
                            text = item.section:upper(),
                            face = KoboldWidgets.face(12),
                            max_width = w - 2 * band_pad,
                        },
                    },
                }),
            }
            local h = band_h + (i > from and Screen:scaleBySize(6) or 0)
            return { widgets = widgets, h = h, section = true }
        end
        local text = TextWidget:new{ text = item.title, face = KoboldWidgets.face(16), max_width = text_w }
        local value = TextWidget:new{
            text = item.value or "",
            face = item.action and actionFace(16) or KoboldWidgets.face(15),
            max_width = value_w,
        }
        local row_h = math.max(text:getSize().h, value:getSize().h) + 2 * row_pad
        local widgets = { HorizontalGroup:new{
            LeftContainer:new{ dimen = Geom:new{ w = text_w, h = row_h }, text },
            HorizontalSpan:new{ width = gap },
            RightContainer:new{ dimen = Geom:new{ w = value_w, h = row_h }, value },
        } }
        local h = row_h
        local nxt = spec[i + 1]
        if nxt and not nxt.section then
            widgets[#widgets + 1] = LineWidget:new{
                dimen = Geom:new{ w = w, h = line_h },
                background = Blitbuffer.COLOR_LIGHT_GRAY,
            }
            h = h + line_h
        end
        return { widgets = widgets, h = h, row_h = row_h, on_tap = item.on_tap, item = item }
    end

    local list = VerticalGroup:new{ align = "left" }
    local hits = {}
    local cy = y
    local i = from
    local next_index = nil
    while i <= #spec do
        local p = piece(i)
        local need = p.h
        -- A band needs the row after it on the same page.
        if p.section and spec[i + 1] then need = need + piece(i + 1).h end
        if opts.max_h and i > from and (cy - y) + need > opts.max_h then
            next_index = i
            break
        end
        if not p.section then
            local item = p.item
            local tip = item.desc and function() KoboldSettingsList.showTip(item) end
            if tip then
                -- Name: the tooltip. Value side: the setting itself.
                hits[#hits + 1] = { rect = Geom:new{ x = x, y = cy, w = text_w, h = p.row_h }, on_tap = tip }
                if p.on_tap then
                    hits[#hits + 1] = {
                        rect = Geom:new{ x = x + text_w, y = cy, w = w - text_w, h = p.row_h },
                        on_tap = p.on_tap,
                    }
                end
            elseif p.on_tap then
                hits[#hits + 1] = { rect = Geom:new{ x = x, y = cy, w = w, h = p.row_h }, on_tap = p.on_tap }
            end
        end
        for _k, widget in ipairs(p.widgets) do list[#list + 1] = widget end
        cy = cy + p.h
        i = i + 1
    end
    return list, hits, next_index
end

-- Tooltip for a setting: its name and description in a small box.
function KoboldSettingsList.showTip(item)
    local InfoMessage = require("ui/widget/infomessage")
    local UIManager = require("ui/uimanager")
    UIManager:show(InfoMessage:new{
        text = item.title .. "\n\n" .. item.desc,
        show_icon = false,
        width = math.floor(Screen:getWidth() * 0.75),
    })
end

-- The on_tap of the row under `pos`, or nil.
function KoboldSettingsList.hit(hits, pos)
    for _i, hit in ipairs(hits or {}) do
        if pos:intersectWith(hit.rect) then return hit.on_tap end
    end
    return nil
end

return KoboldSettingsList
