local mp = require 'mp'

function nextfile_and_rewind()
    -- Go to next file
    mp.commandv("script-binding", "nextfile")
    -- Once the new file is loaded, seek to start
    mp.register_event("file-loaded", function()
        mp.commandv("seek", "0", "absolute")
    end)
end

mp.add_key_binding(nil, "nextfile_and_rewind", nextfile_and_rewind)

