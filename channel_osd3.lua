local channel = ""
local channel_ov = nil
local channel_timer = nil

local function clear_channel_osd()
    if channel_timer then channel_timer:stop(); channel_timer = nil end
    if channel_ov then channel_ov:remove(); channel_ov = nil end
end

mp.register_script_message("charlietv-channel", function(ch)
    channel = ch
end)

mp.register_event("file-loaded", function()
    if channel == "" then return end
    clear_channel_osd()
    channel_ov = mp.create_osd_overlay("ass-events")
    channel_ov.data = "{\\an9\\fs24\\fnNimbus Sans\\c&H0596EB&\\bord1\\shad3\\3c&H000000&\\4c&H000000&}Channel " .. channel
    channel_ov:update()
    channel_timer = mp.add_timeout(5, function()
        channel_ov:remove(); channel_ov = nil; channel_timer = nil
    end)
end)

local info_ov = nil
mp.register_script_message("toggle-info", function()
    if info_ov then
        info_ov:remove()
        info_ov = nil
    else
        local filename = mp.get_property("filename") or "unknown"
        info_ov = mp.create_osd_overlay("ass-events")
        local pre = "{\\an7\\fs20\\fnUbuntu Mono\\bord1\\shad2\\3c&H000000&\\4c&H000000&}"
        info_ov.data = pre
            .. "\\N\\N\\N\\N\\N{\\c&H0596EB&}Playing: " .. filename .. "{\\c&HFFFFFF&}\\N\\N"
            .. "{\\c&H0596EB&}\\N\\N"
            .. " (← and →) change channels\\N"
            .. " (INSERT) jump to beginning\\N(ENTER)  next channel\\N(q)      quit\\N\\N\\N"
            .. " (f) toggle fullscreen\\N"
            .. " (k) keep new movie, (del) remove file\\N\\N"
            .. " (7) and (9) jump chapters\\N(4) and (6) jump episodes\\N(1) and (3) jump time\\N"
            .. " (5) cycle filters\\N"
            .. " (0) restart episode\\N\\N\\N"
            .. "  +-----------+\\N"
            .. "  |           |\\N"
            .. "  |     ^     |\\N"
            .. "  |   <   >   |\\N"
            .. "  |     v     |\\N"
            .. "  |           |\\N"
            .. "  | [pause]   |\\N"
            .. "  | [resize]  |\\N"
            .. "  |           |\\N"
            .. "  | (restart) |\\N"
            .. "  | (next)    |\\N"
            .. "  |           |\\N"
            .. "  +-----------+\\N"
            .. " {\\c&HFFFFFF&}"
        info_ov:update()
    end
end)
