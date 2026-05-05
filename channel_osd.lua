local opts = require 'mp.options'
local o = { channel = "", duration = 5 }
opts.read_options(o, "channel_osd")

if o.channel ~= "" then
    mp.register_event("file-loaded", function()
        local ov = mp.create_osd_overlay("ass-events")
        -- \an9 = top-right; colors/font match master.sh OSD style (#eb9605 → BGR &H0596EB&)
        ov.data = "{\\an9\\fs24\\fnNimbus Sans\\c&H0596EB&\\bord1\\shad3\\3c&H000000&\\4c&H000000&}" .. o.channel
        ov:update()
        mp.add_timeout(o.duration, function() ov:remove() end)
    end)
end

-- Info overlay toggle (bound to 'i' and 'c' in input.conf)
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
            .. "\\N\\N\\N\\N\\N\\N\\N{\\c&H0596EB&}Playing: " .. filename .. "{\\c&HFFFFFF&}\\N\\N"
            .. "{\\c&H0596EB&}\\N\\N"
            .. " (← and →) change channels\\N"
            .. " (INSERT) jump to beginning\\N(ENTER)  skip to next episode\\N(ESC)    close\\N\\N"

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
