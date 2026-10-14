-- kobold/data/perf.lua — Kobold
-- Timing lines in KOReader's log ("[kobold perf] ..."), to see where loading
-- time goes on a real device. Builds no widgets.

local logger          = require("logger")

local KoboldPerf = {}

local ok_time, time = pcall(require, "ui/time")
if not (ok_time and time and time.now and time.since and time.to_ms) then time = nil end

-- A start mark for KoboldPerf.log.
function KoboldPerf.start()
    if time then return time.now() end
    return os.clock()
end

-- Logs `label` with the milliseconds since `mark`, plus an optional
-- string.format detail, e.g. KoboldPerf.log("scan", t, "books=%d", n).
function KoboldPerf.log(label, mark, fmt, ...)
    local ms
    if time then
        ms = time.to_ms(time.since(mark))
    else
        ms = (os.clock() - mark) * 1000
    end
    local detail = fmt and (" " .. string.format(fmt, ...)) or ""
    logger.info(string.format("[kobold perf] %s: %.0fms%s", label, ms, detail))
end

return KoboldPerf
