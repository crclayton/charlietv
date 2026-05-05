local fifo = "/tmp/charlietv3-cmd"

local function send(cmd)
    local f = io.open(fifo, "w")
    if f then f:write(cmd .. "\n"); f:close() end
end

-- Named bindings called from input3.conf via script-binding charlietv3_keys/<name>
mp.add_key_binding(nil, "tv-prev",   function() send("prev") end)
mp.add_key_binding(nil, "tv-next",   function() send("next") end)
mp.add_key_binding(nil, "tv-quit",   function() send("quit") end)
mp.add_key_binding(nil, "tv-delete", function() send("delete") end)
mp.add_key_binding(nil, "tv-save",   function() send("save") end)

-- Seek to offset and restore brightness in file-loaded.
-- brightness is set to -100 before loadfile to hide the position-0 frame.
mp.register_event("file-loaded", function()
    local fh = io.open("/tmp/charlietv3-seek", "r")
    if fh then
        local pos = tonumber(fh:read("*a"))
        fh:close()
        os.remove("/tmp/charlietv3-seek")
        if pos and pos > 0 then
            mp.commandv("seek", pos, "absolute", "exact")
        end
    end
    mp.add_timeout(0.20, function()
        mp.set_property_number("brightness", 0)
    end)
end)

