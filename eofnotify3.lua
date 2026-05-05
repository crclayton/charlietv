mp.register_event("end-file", function(e)
    if e.reason == "eof" then
        local f = io.open("/tmp/charlietv3-cmd", "w")
        if f then f:write("next\n"); f:close() end
    end
end)
