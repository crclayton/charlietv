local mp = require 'mp'

local THRESHOLD = 5
local triggered = false

local function on_time_remaining(name, value)
    if triggered then return end
    if value == nil or value <= 0 then return end
    if value <= THRESHOLD then
        triggered = true
        mp.unobserve_property(on_time_remaining)
        mp.commandv("script-binding", "nextfile")

        local handler
        handler = function()
            mp.unregister_event(handler)
            mp.commandv("seek", "0", "absolute")
            local filename = mp.get_property("filename")
            mp.set_property("osd-playing-msg", "Fuckin' AUTOMATICALLY playing next episode: " .. filename)
            mp.commandv("show-text", mp.get_property_osd("osd-playing-msg"))
        end
        mp.register_event("file-loaded", handler)
    end
end

local function on_file_loaded()
    triggered = false
    mp.unobserve_property(on_time_remaining)
    mp.observe_property("time-remaining", "number", on_time_remaining)
end

mp.register_event("file-loaded", on_file_loaded)
