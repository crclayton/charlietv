-- Detects double-press of configured keys and maps them to alternate actions.
-- Single-press fires after TIMEOUT if no second press is detected.

local mp = require 'mp'

local TIMEOUT = 0.3       -- seconds to wait for a second press
local POST_DOUBLE_GRACE = TIMEOUT * 2  -- suppress single if it fires within this long after a double

-- Keys below are given as the physical positions used by charlietv3.sh's
-- default (QWERTY) input3.conf. Under --dvorak, the same physical keys type
-- different characters, so the layout picked in charlietv3.sh (passed via
-- the CHARLIETV_LAYOUT env var) selects the matching characters here.
local LAYOUT = os.getenv("CHARLIETV_LAYOUT") or "qwerty"
local next_prev_key, restart_key
if LAYOUT == "dvorak" then
    next_prev_key, restart_key = "s", "-"
else
    next_prev_key, restart_key = ";", "'"
end

-- Escalating skip: each skip within SKIP_RESET seconds of the last one (same
-- direction) jumps further, stepping through SKIP_STEPS. Waiting resets it.
local SKIP_RESET = 1
local SKIP_STEPS = { 1, 5, 10, 20, 40, 80 }  -- percent of the file
local BAR_SECS = 2  -- how long the progress bar stays up

-- Progress bar across the full screen width, e.g. ├█████──────────┤
-- (box-drawing chars join into one solid line in a monospace font)
local bar = mp.create_osd_overlay("ass-events")
local bar_timer = nil
local function show_bar(pct)
    local dims = mp.get_property_native("osd-dimensions") or {}
    local w, h = dims.w or 0, dims.h or 0
    if w <= 0 or h <= 0 then w, h = 1280, 720 end
    local fs = math.floor(h / 24)
    local n = math.max(10, math.floor(w * 0.95 / (fs * 0.51)) - 2)  -- mono char ~0.51em wide
    local k = math.min(n - 1, math.floor(pct / 100 * n))
    local line = "├" .. string.rep("█", k + 1) .. string.rep("─", n - k - 1) .. "┤"
    bar.res_x, bar.res_y = w, h
    bar.data = string.format("{\\an2\\pos(%d,%d)\\fnmonospace\\fs%d\\1c&H0596EB&\\3c&H000000&\\bord1\\shad2}%s",
        math.floor(w / 2), h - fs, fs, line)
    bar:update()
    if bar_timer then bar_timer:kill() end
    bar_timer = mp.add_timeout(BAR_SECS, function() bar:remove(); bar_timer = nil end)
end
local skip = { dir = 0, level = 0, last = -math.huge }

local function do_skip(dir)
    local now = mp.get_time()
    if dir == skip.dir and now - skip.last < SKIP_RESET then
        skip.level = math.min(skip.level + 1, #SKIP_STEPS)
    else
        skip.level = 1
    end
    skip.dir, skip.last = dir, now

    local step = SKIP_STEPS[skip.level]
    local pos = mp.get_property_number("percent-pos", 0)
    local target = math.min(math.max(pos + dir * step, 0), 99.5)
    mp.commandv("seek", target, "absolute-percent")

    mp.commandv("show-text", string.format("%s %d%%",
        dir > 0 and "Skipping ahead" or "Jumping back", step))
    show_bar(target)
end

-- Each entry: key, single/double action.
-- Action: { cmd = {...}, text = "optional OSD message" } or { fn = function }
local bindings = {
    { key = next_prev_key,
      double = { cmd = {"script-binding", "nextfile"},          },
      single = { cmd = {"script-binding", "previousfile"},      } },
    { key = restart_key,
      double = { fn = function() do_skip(1) end },
      single = { fn = function() do_skip(-1) end } },
}

local state = {}

for i, b in ipairs(bindings) do
    local key    = b.key
    local single = b.single
    local double = b.double
    state[key] = { timer = nil, count = 0, last_double = -math.huge }

    -- Binding name must not embed the raw key character: mpv treats ";"
    -- (and possibly other punctuation) as a command separator when it
    -- appears inside the generated "script-binding <name>" command string,
    -- silently truncating the binding name and breaking the key entirely.
    mp.add_forced_key_binding(key, "dp" .. i, function()
        local s = state[key]
        s.count = s.count + 1
        if s.timer then s.timer:kill(); s.timer = nil end
        s.timer = mp.add_timeout(TIMEOUT, function()
            local n = s.count
            s.count = 0
            s.timer = nil
            local function act(a)
                if a.fn then a.fn(); return end
                mp.commandv(table.unpack(a.cmd))
                if a.text then mp.commandv("show-text", a.text) end
            end
            if n >= 2 then
                act(double)
                s.last_double = mp.get_time()
            elseif mp.get_time() - s.last_double >= POST_DOUBLE_GRACE then
                act(single)
            end
        end)
    end)
end
