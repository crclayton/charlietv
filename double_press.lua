-- Detects double-press of configured keys and maps them to alternate actions.
-- Single-press fires after TIMEOUT if no second press is detected.

local mp = require 'mp'

local TIMEOUT = 0.3       -- seconds to wait for a second press
local POST_DOUBLE_GRACE = TIMEOUT * 2  -- suppress single if it fires within this long after a double

-- Each entry: key, single/double action.
-- Action: { cmd = {...}, text = "optional OSD message" }
local bindings = {
    { key = "s",
      double = { cmd = {"script-binding", "nextfile"},          },
      single = { cmd = {"script-binding", "previousfile"},      } },
    { key = "-",
      double = { cmd = {"seek", "+5", "relative-percent"},      text = "Skipping ahead a lil" },
      single = { cmd = {"seek", "0.25", "absolute-percent"},    text = "Let's get restarted in here" } },
}

local state = {}

for _, b in ipairs(bindings) do
    local key    = b.key
    local single = b.single
    local double = b.double
    state[key] = { timer = nil, count = 0, last_double = -math.huge }

    mp.add_forced_key_binding(key, "dp-" .. key, function()
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
