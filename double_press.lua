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

-- Each entry: key, single/double action.
-- Action: { cmd = {...}, text = "optional OSD message" }
local bindings = {
    { key = next_prev_key,
      double = { cmd = {"script-binding", "nextfile"},          },
      single = { cmd = {"script-binding", "previousfile"},      } },
    { key = restart_key,
      double = { cmd = {"seek", "+5", "relative-percent"},      text = "Skipping ahead a lil" },
      single = { cmd = {"seek", "-5", "relative-percent"},      text = "Jumping back a lil" } },
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
