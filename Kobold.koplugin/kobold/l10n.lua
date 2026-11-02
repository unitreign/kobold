-- kobold/l10n.lua — Kobold
-- Translations for Kobold's own text. Use it in place of KOReader's gettext:
--
--   local _ = require("kobold.l10n")
--   _("Remove from Home")                     plain text
--   _.T(_("Page %1 of %2"), page, pages)      text with values (%1, %2, ...)
--   _.N("%1 book", "%1 books", n)             a count, in the language's
--                                             plural form; %1 is the count
--
-- Translations live in the plugin's l10n folder, one standard gettext file
-- per language: l10n/<lang>/kobold.po (for example l10n/de/kobold.po or
-- l10n/pt_BR/kobold.po), made from the template l10n/kobold.pot. The
-- language is KOReader's own (its Language setting). Text without a Kobold
-- translation goes to KOReader's translations, so common words such as
-- "Cancel" are translated either way; failing both, the English is shown.

local GetText = require("gettext")
local KoboldMeta = require("kobold.meta")

local L10n = {}

-- Plural rules ------------------------------------------------------------

-- Splits a C expression into tokens, or nil when it has anything else.
local function tokens(expr)
    local toks, i = {}, 1
    while i <= #expr do
        local c, two = expr:sub(i, i), expr:sub(i, i + 1)
        if c:match("%s") then
            i = i + 1
        elseif c:match("%d") then
            local num = expr:match("^%d+", i)
            toks[#toks + 1] = num
            i = i + #num
        elseif two == "&&" or two == "||" or two == "==" or two == "!="
            or two == "<=" or two == ">=" then
            toks[#toks + 1] = two
            i = i + 2
        elseif c:match("[n()?:!%%*/+<>-]") then
            toks[#toks + 1] = c
            i = i + 1
        else
            return nil
        end
    end
    return toks
end

-- The C expression from a .po file's Plural-Forms header (such as
-- "n%10==1 && n%100!=11 ? 0 : 1") as a Lua function of n. A small parser
-- for the operators gettext allows: ?: || && == != < > <= >= + - * / % !
-- and parentheses. nil when the expression cannot be read.
local function pluralFunc(expr)
    local toks = tokens(expr)
    if not toks then return nil end
    local pos = 1
    local function peek() return toks[pos] end
    local function take() pos = pos + 1 return toks[pos - 1] end
    local function b(x) return x and 1 or 0 end

    local ternary
    local function primary()
        local t = take()
        if t == "n" then return function(n) return n end end
        if t == "(" then
            local e = ternary()
            if take() ~= ")" then error("missing )") end
            return e
        end
        if t == "!" then
            local e = primary()
            return function(n) return e(n) == 0 and 1 or 0 end
        end
        if t == "-" then
            local e = primary()
            return function(n) return -e(n) end
        end
        local v = tonumber(t)
        if not v then error("bad token") end
        return function() return v end
    end
    -- One level of left-to-right binary operators.
    local function level(next_level, ops)
        return function()
            local left = next_level()
            while ops[peek() or ""] do
                local op = ops[take()]
                local l, r = left, next_level()
                left = function(n) return op(l(n), r(n)) end
            end
            return left
        end
    end
    local mul = level(primary, {
        ["*"] = function(x, y) return x * y end,
        ["/"] = function(x, y) return math.floor(x / y) end,
        ["%"] = function(x, y) return x % y end,
    })
    local add = level(mul, {
        ["+"] = function(x, y) return x + y end,
        ["-"] = function(x, y) return x - y end,
    })
    local cmp = level(add, {
        ["<"] = function(x, y) return b(x < y) end,
        [">"] = function(x, y) return b(x > y) end,
        ["<="] = function(x, y) return b(x <= y) end,
        [">="] = function(x, y) return b(x >= y) end,
    })
    local eq = level(cmp, {
        ["=="] = function(x, y) return b(x == y) end,
        ["!="] = function(x, y) return b(x ~= y) end,
    })
    local land = level(eq, { ["&&"] = function(x, y) return b(x ~= 0 and y ~= 0) end })
    local lor = level(land, { ["||"] = function(x, y) return b(x ~= 0 or y ~= 0) end })
    ternary = function()
        local cond = lor()
        if peek() ~= "?" then return cond end
        take()
        local yes = ternary()
        if take() ~= ":" then error("missing :") end
        local no = ternary()
        return function(n)
            if cond(n) ~= 0 then return yes(n) end
            return no(n)
        end
    end

    local ok, f = pcall(function()
        local e = ternary()
        if pos <= #toks then error("trailing tokens") end
        return e
    end)
    return ok and f or nil
end

-- Reading a .po file -------------------------------------------------------

local ESCAPES = { n = "\n", t = "\t", ['"'] = '"', ["\\"] = "\\" }

local function unescape(s)
    return (s:gsub("\\(.)", ESCAPES))
end

-- { [msgid] = text, or { [0] = form, [1] = form, ... } for counts }, and the
-- plural rule as a function. Fuzzy and empty entries are left out, so their
-- English is shown. nil when the file cannot be opened.
local function readPo(path)
    local f = io.open(path, "r")
    if not f then return nil end
    local msgs, plural = {}, nil
    local entry, field, fuzzy = {}, nil, false

    local function finish()
        local id = entry.msgid
        if id and not fuzzy then
            if id == "" then
                local rule = (entry.msgstr or ""):match("Plural%-Forms:[^\n]*plural=([^;\n]+)")
                if rule then plural = pluralFunc(rule) end
            elseif entry.msgid_plural then
                local forms, any = {}, false
                for k, v in pairs(entry) do
                    local idx = k:match("^msgstr%[(%d+)%]$")
                    if idx and v ~= "" then
                        forms[tonumber(idx)] = v
                        any = true
                    end
                end
                if any then msgs[id] = forms end
            elseif entry.msgstr and entry.msgstr ~= "" then
                msgs[id] = entry.msgstr
            end
        end
        entry, field, fuzzy = {}, nil, false
    end

    for line in f:lines() do
        line = line:gsub("\r$", "")
        if line:match("^%s*$") then
            finish()
        elseif line:match("^#,.*fuzzy") then
            fuzzy = true
        elseif not line:match("^#") then
            local key, str = line:match('^(msg[%w_%[%]]+)%s+"(.*)"%s*$')
            if key then
                if key == "msgid" and entry.msgid then finish() end
                field = key
                entry[key] = unescape(str)
            else
                local more = line:match('^%s*"(.*)"%s*$')
                if more and field then entry[field] = entry[field] .. unescape(more) end
            end
        end
    end
    finish()
    f:close()
    return msgs, plural
end

-- The language and its file ------------------------------------------------

local catalog, plural_rule = {}, nil

-- Reads the translation for KOReader's language: the exact code first
-- (pt_BR), then the language alone (pt). English needs no file.
local function load()
    if not KoboldMeta.DIR then return end
    local lang = G_reader_settings and G_reader_settings:readSetting("language")
        or os.getenv("LANGUAGE") or os.getenv("LANG") or "en"
    lang = lang:match("^[^.:@]+") or "en"  -- "de_DE.UTF-8" -> "de_DE"
    for _i, code in ipairs({ lang, lang:match("^(%a+)_") }) do
        local msgs, rule = readPo(KoboldMeta.DIR .. "/l10n/" .. code .. "/kobold.po")
        if msgs then
            catalog, plural_rule = msgs, rule
            return
        end
    end
end
load()

-- The API -----------------------------------------------------------------

-- `text` with %1, %2, ... replaced by the values given. A translation can
-- put them in any order its language needs.
function L10n.T(text, ...)
    local args = { ... }
    return (text:gsub("%%(%d)", function(i)
        local v = args[tonumber(i)]
        if v == nil then return "%" .. i end
        return tostring(v)
    end))
end

-- A count: `one` or `many` (the English forms, each with %1 for the count)
-- in this language's plural form, with %1 replaced by n.
function L10n.N(one, many, n)
    local forms = catalog[one]
    local text
    if type(forms) == "table" then
        local idx = plural_rule and plural_rule(n) or (n == 1 and 0 or 1)
        text = forms[idx] or forms[0]
    end
    if not text and GetText.ngettext then
        local ok, t = pcall(GetText.ngettext, one, many, n)
        if ok then text = t end
    end
    text = text or (n == 1 and one or many)
    return L10n.T(text, n)
end

-- Plain text in this language.
local function translate(_self, text)
    local t = catalog[text]
    if type(t) == "string" then return t end
    return GetText(text)
end

return setmetatable(L10n, { __call = translate })
