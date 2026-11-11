-- kobold/ui/popup_kit.lua — Kobold
-- Building blocks for the status bar popups, in the e-reader's style: rows
-- of text, switch rows (a label with the on/off switch), italic links, and
-- thin lines between sections that run the box's full width. build() stacks
-- them in a box under the status bar item that opened the popup, with the
-- arrow pointing at it, and records where each tappable row is.

local Blitbuffer      = require("ffi/blitbuffer")
local Device          = require("device")
local FrameContainer  = require("ui/widget/container/framecontainer")
local Geom            = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan  = require("ui/widget/horizontalspan")
local LeftContainer   = require("ui/widget/container/leftcontainer")
local LineWidget      = require("ui/widget/linewidget")
local TextWidget      = require("ui/widget/textwidget")
local VerticalGroup   = require("ui/widget/verticalgroup")
local VerticalSpan    = require("ui/widget/verticalspan")
local KoboldPopup     = require("kobold.ui.popup")
local KoboldSwitch    = require("kobold.ui.switch")
local KoboldWidgets   = require("kobold.ui.widgets")

local Screen = Device.screen

local Kit = {}

function Kit.pad() return Screen:scaleBySize(18) end

-- One height for every row with a control (switch, value, link), and the
-- space above and below a line, so the popups are evenly spaced.
local function rowH() return Screen:scaleBySize(44) end
local function lineGap() return Screen:scaleBySize(12) end
local function border() return Screen:scaleBySize(2) end

-- Row kinds, each { kind, ... } (see build):
--   Kit.text(text, size, grey)      plain text
--   Kit.value(label, value, on_tap) a label with its value on the right
--   Kit.switch(label, on, on_tap, tag) a label with the switch on the right
--                                   (`tag`, e.g. "AUTO", just before it)
--   Kit.link(text, on_tap)          an italic link
--   Kit.line()                      a thin line across the whole box
--   Kit.space(h)                    empty space
function Kit.text(text, size, grey) return { kind = "text", text = text, size = size, grey = grey } end
function Kit.value(label, value, on_tap) return { kind = "value", label = label, value = value, on_tap = on_tap } end
function Kit.switch(label, on, on_tap, tag) return { kind = "switch", label = label, on = on, on_tap = on_tap, tag = tag } end
function Kit.link(text, on_tap) return { kind = "link", text = text, on_tap = on_tap } end
function Kit.line() return { kind = "line" } end
function Kit.space(h) return { kind = "space", h = h } end
-- A widget built by the caller, exactly `inner` wide: { widget, hits }
-- where hits are { rect (relative to the widget), on_tap }.
function Kit.custom(widget, hits) return { kind = "custom", widget = widget, hits = hits } end

local function rowWidget(row, inner, pad)
    local row_h = rowH()
    if row.kind == "text" then
        -- Titles in serif; grey notes in the sans face, smaller.
        local face = row.grey and KoboldWidgets.face(row.size or 14) or KoboldWidgets.serifFace(row.size or 18)
        local t = TextWidget:new{ text = row.text, face = face,
            fgcolor = row.grey and KoboldWidgets.subtitleColor() or nil, max_width = inner }
        local h = t:getSize().h + Screen:scaleBySize(4)
        return LeftContainer:new{ dimen = Geom:new{ w = inner, h = h }, t }, h
    elseif row.kind == "value" or row.kind == "switch" then
        local label = TextWidget:new{ text = row.label, face = KoboldWidgets.serifFace(18), max_width = inner }
        local right = HorizontalGroup:new{ align = "center" }
        if row.kind == "value" then
            right[#right + 1] = TextWidget:new{ text = row.value or "", face = KoboldWidgets.italicFace(17) }
        else
            if row.tag then
                right[#right + 1] = TextWidget:new{ text = row.tag, face = KoboldWidgets.face(13) }
                right[#right + 1] = HorizontalSpan:new{ width = Screen:scaleBySize(12) }
            end
            right[#right + 1] = KoboldSwitch:new{ on = row.on, height = Screen:scaleBySize(26) }
        end
        local gap = math.max(0, inner - label:getSize().w - right:getSize().w)
        return KoboldWidgets.fixed(inner, row_h, HorizontalGroup:new{
            align = "center", label, HorizontalSpan:new{ width = gap }, right,
        }), row_h
    elseif row.kind == "link" then
        return LeftContainer:new{ dimen = Geom:new{ w = inner, h = row_h },
            TextWidget:new{ text = row.text, face = KoboldWidgets.italicFace(17), max_width = inner } }, row_h
    elseif row.kind == "line" then
        -- Runs the full width of the box (out into its padding). Rows with
        -- a control already have room inside them, so next to one the line
        -- keeps only a small gap; next to plain text, the full gap.
        local above = row.after_control and Screen:scaleBySize(2) or lineGap()
        local below = row.before_control and Screen:scaleBySize(2) or lineGap()
        local thick = Screen:scaleBySize(1)
        return HorizontalGroup:new{
            HorizontalSpan:new{ width = -pad },
            VerticalGroup:new{
                VerticalSpan:new{ width = above },
                LineWidget:new{ dimen = Geom:new{ w = inner + 2 * pad, h = thick },
                    background = Blitbuffer.COLOR_DARK_GRAY },
                VerticalSpan:new{ width = below },
            },
        }, above + thick + below
    elseif row.kind == "space" then
        return VerticalSpan:new{ width = row.h }, row.h
    elseif row.kind == "custom" then
        return row.widget, row.widget:getSize().h
    end
end

-- Stacks `rows` in a box `fw` wide under status bar item `anchor_name`.
-- Sets popup.frame_dimen and popup.hits ({ rect, on_tap } in screen
-- coordinates); returns the layer to use as popup[1].
function Kit.build(popup, anchor_name, rows, fw)
    fw = fw or KoboldPopup.width()
    local pad, b = Kit.pad(), border()
    local inner = fw - 2 * (pad + b)
    local fx, fy = KoboldPopup.origin(fw, anchor_name)
    local x0, y0 = fx + b, fy + b + math.floor(pad * 0.8)
    local content = VerticalGroup:new{ align = "left" }
    local hits, y = {}, 0
    local control = { value = true, switch = true, link = true }
    for i, row in ipairs(rows) do
        if row.kind == "line" then
            row.after_control = rows[i - 1] and control[rows[i - 1].kind] or false
            row.before_control = rows[i + 1] and control[rows[i + 1].kind] or false
        end
        local widget, h = rowWidget(row, inner, pad)
        if widget then
            content[#content + 1] = widget
            if row.on_tap then
                -- The row's tap area spans the box's width.
                hits[#hits + 1] = { rect = Geom:new{ x = fx, y = y0 + y, w = fw, h = h }, on_tap = row.on_tap }
            end
            for _j, hit in ipairs(row.hits or {}) do
                hits[#hits + 1] = { rect = Geom:new{ x = x0 + pad + hit.rect.x, y = y0 + y + hit.rect.y,
                    w = hit.rect.w, h = hit.rect.h }, on_tap = hit.on_tap }
            end
            y = y + h
        end
    end
    -- A last row with a control has room inside it already, like the space
    -- above it; plain text at the bottom gets a little padding.
    local last = rows[#rows]
    local bottom = last and control[last.kind] and Screen:scaleBySize(2) or math.floor(pad * 0.4)
    local box = FrameContainer:new{
        bordersize = b, padding = pad, padding_top = math.floor(pad * 0.8), padding_bottom = bottom,
        radius = KoboldPopup.radius(), background = Blitbuffer.COLOR_WHITE,
        content,
    }
    local size = box:getSize()
    popup.frame_dimen = Geom:new{ x = fx, y = fy, w = size.w, h = size.h }
    popup.hits = hits
    return KoboldPopup.place(popup.dimen, fx, fy, box, KoboldPopup.anchor(anchor_name))
end

-- The tap handler: a row's action (given the tap position and the row's
-- rect), or close when outside the box.
function Kit.tap(popup, pos)
    local d = popup.frame_dimen
    if not (pos.x >= d.x and pos.x < d.x + d.w and pos.y >= d.y and pos.y < d.y + d.h) then
        popup:onClose()
        return true
    end
    for _i, hit in ipairs(popup.hits or {}) do
        local r = hit.rect
        if pos.x >= r.x and pos.x < r.x + r.w and pos.y >= r.y and pos.y < r.y + r.h then
            hit.on_tap(pos, r)
            return true
        end
    end
    return true
end

return Kit
