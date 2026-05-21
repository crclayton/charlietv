local fifo = "/tmp/charlietv3-cmd"
local function send(cmd)
    local f = io.open(fifo, "w")
    if f then f:write(cmd .. "\n"); f:close() end
end

mp.add_key_binding(nil, "tv-prev",   function() send("prev") end)
mp.add_key_binding(nil, "tv-next",   function() send("next") end)
mp.add_key_binding(nil, "tv-quit",   function() send("quit") end)
mp.add_key_binding(nil, "tv-delete", function() send("delete") end)
mp.add_key_binding(nil, "tv-save",   function() send("save") end)

mp.register_event("file-loaded", function()
    local fh = io.open("/tmp/charlietv3-seek", "r")
    if fh then
        local pos = tonumber(fh:read("*a"))
        fh:close()
        os.remove("/tmp/charlietv3-seek")
        if pos and pos > 0 then
            mp.commandv("seek", pos, "absolute", "exact")
        end
        local mf = io.open("/tmp/charlietv3-channel-loaded", "w")
        if mf then mf:write("1"); mf:close() end
    end
end)

-- Restore brightness when seek completes; brightness is set to -100 before loadfile
-- to suppress frame flash. playback-restart fires once the correct frame is ready.
mp.register_event("playback-restart", function()
    mp.set_property_number("brightness", 0)
end)
