

-- local mp = require 'mp'
--
-- local msg = require 'mp.msg'
--
-- local function on_end_file(event)
--     msg.info("end-file reason: " .. tostring(event.reason))
--     -- only react when we hit actual EOF
--     if event.reason == "eof" then
--         -- call the same script-binding as your KP6 key
--         mp.commandv("script-binding", "nextfile")
--     end
-- end
--
-- mp.register_event("end-file", on_end_file)
--
--
-- auto-nextfile.lua
local mp = require 'mp'

-- How close to the end (in seconds) before we trigger nextfile
local THRESHOLD = 5

local function on_time_remaining(name, value)
    if value == nil then return end
    if value <= THRESHOLD then
        -- Stop watching, or we’ll spam nextfile
        mp.unobserve_property(on_time_remaining)
        -- Call your existing script-binding
        mp.commandv("script-binding", "nextfile")

        mp.register_event("file-loaded", function()
            mp.commandv("seek", "0", "absolute")

        -- Option 2: Overwrite the actual 'osd-playing-msg' property for this file.
        -- (You can pull in the filename or media title dynamically)
        local filename = mp.get_property("filename")
        mp.set_property("osd-playing-msg", "Fuckin' AUTOMATICALLY playing next episode: " .. filename)

        -- Option 3: Force mpv to display whatever your standard osd-playing-msg is
        mp.commandv("show-text", mp.get_property_osd("osd-playing-msg"))

        end)
    end
end

local function on_file_loaded()
    -- Re-arm the watcher for each new file
    mp.observe_property("time-remaining", "number", on_time_remaining)
end

mp.register_event("file-loaded", on_file_loaded)

