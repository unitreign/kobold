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

-- `spec` is a list of items, top to bottom:
--   { section = "HOME" }                                   a gray band
--   { title, desc = optional, value = optional text,
--     action = true for an italic action word, on_tap = fn }  a row
-- Returns the widget (exactly `w` wide) and the tap rectangles
-- { { rect = Geom, on_tap = fn }, ... } in screen coordinates, for a list
-- drawn with its top-left corner at (x, y).
function KoboldSettingsList.build(spec, x, y, w)
    local band_h   = Screen:scaleBySize(30)
    local band_pad = Screen:scaleBySize(10)
    local row_pad  = Screen:scaleBySize(12)
    local gap      = Screen:scaleBySize(16)
    local line_h   = Screen:scaleBySize(1)
    local value_w  = math.floor(w * 0.38)
    local text_w   = w - value_w - gap

    local list = VerticalGroup:new{ align = "left" }
    local hits = {}
    local cy = y
    local function add(widget)
        list[#list + 1] = widget
        cy = cy + widget:getSize().h
    end

    for i, item in ipairs(spec) do
        if item.section then
            if i > 1 then add(VerticalSpan:new{ width = Screen:scaleBySize(10) }) end
            add(FrameContainer:new{
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
            })
        else
            local text = VerticalGroup:new{
                align = "left",
                TextWidget:new{ text = item.title, face = KoboldWidgets.face(17), max_width = text_w },
            }
            if item.desc then
                text[#text + 1] = VerticalSpan:new{ width = Screen:scaleBySize(3) }
                text[#text + 1] = TextBoxWidget:new{
                    text = item.desc,
                    face = KoboldWidgets.face(13),
                    fgcolor = KoboldWidgets.subtitleColor(),
                    width = text_w,
                }
            end
            local value = TextWidget:new{
                text = item.value or "",
                face = item.action and actionFace(16) or KoboldWidgets.face(15),
                max_width = value_w,
            }
            local h = math.max(text:getSize().h, value:getSize().h) + 2 * row_pad
            local top = cy
            add(HorizontalGroup:new{
                LeftContainer:new{ dimen = Geom:new{ w = text_w, h = h }, text },
                HorizontalSpan:new{ width = gap },
                RightContainer:new{ dimen = Geom:new{ w = value_w, h = h }, value },
            })
            local nxt = spec[i + 1]
            if nxt and not nxt.section then
                add(LineWidget:new{
                    dimen = Geom:new{ w = w, h = line_h },
                    background = Blitbuffer.COLOR_LIGHT_GRAY,
                })
            end
            if item.on_tap then
                hits[#hits + 1] = { rect = Geom:new{ x = x, y = top, w = w, h = h }, on_tap = item.on_tap }
            end
        end
    end
    return list, hits
end

-- The on_tap of the row under `pos`, or nil.
function KoboldSettingsList.hit(hits, pos)
    for _i, hit in ipairs(hits or {}) do
        if pos:intersectWith(hit.rect) then return hit.on_tap end
    end
    return nil
end

return KoboldSettingsList
