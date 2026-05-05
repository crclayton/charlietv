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

-- Seek to position on file-loaded, before first frame renders
local seek_on_load = nil
mp.register_script_message("charlietv-seek", function(pos)
    seek_on_load = tonumber(pos)
end)
mp.register_event("file-loaded", function()
    if seek_on_load and seek_on_load > 0 then
        mp.commandv("seek", seek_on_load, "absolute", "exact")
        seek_on_load = nil
    end
end)
