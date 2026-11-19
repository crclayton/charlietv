local channel = ""
local channel_ov = nil
local channel_timer = nil
local info_ov = nil

local function clear_channel_osd()
    if channel_timer then channel_timer:stop(); channel_timer = nil end
    if channel_ov then channel_ov:remove(); channel_ov = nil end
end

local function fmt_dur(secs)
    if not secs or secs < 0 then return "?" end
    secs = math.floor(secs)
    local h = math.floor(secs / 3600)
    local m = math.floor((secs % 3600) / 60)
    if h > 0 then return h .. "h" .. m .. "min" else return m .. "min" end
end

local function clock_str()
    local t = os.date("*t")
    local h = t.hour % 12
    if h == 0 then h = 12 end
    local ampm = t.hour < 12 and "AM" or "PM"
    if t.min == 0 then
        return h .. ampm
    else
        return string.format("%d:%02d%s", h, t.min, ampm)
    end
end

-- OSD always shows the qwerty key labels, even under --dvorak, since
-- that's the layout printed on the keycaps.
local fullscreen_key = "f"

local function show_info()
    if info_ov then info_ov:remove() end
    info_ov = mp.create_osd_overlay("ass-events")
    local filename = mp.get_property("filename") or "unknown"
    local dur_secs  = mp.get_property_number("duration")
    local pos_secs  = mp.get_property_number("time-pos")
    local elapsed   = fmt_dur(pos_secs)
    local total     = fmt_dur(dur_secs)
    local remaining = fmt_dur(dur_secs and pos_secs and (dur_secs - pos_secs) or nil)
    local clock     = clock_str()
    local pre = "{\\an7\\fs24\\fnUbuntu Mono\\bord1\\shad2\\3c&H000000&\\4c&H000000&}"
    info_ov.data = pre
        .. "\\N\\N\\N\\N\\N\\N"
        .. "{\\c&8888878&}" .. clock    .. "\\N"
        .. "{\\c&FFFFFFF&}\\N\\N" .. filename .. "\\N\\N"
        .. "{\\c&H0596EB&}" .. elapsed .. " elapsed / " .. remaining .. " remaining / " .. total .. " total" .. "\\N\\N\\N"
        .. "\\N\\N"
        .. "{\\c&888888&}PC controls:                                                                          Remote controls:\\N"
        .. "{\\c&H0596EB&}\\N\\N"
        .. "(← and →) change channels                                                            +----------------+\\N"
        .. " (SPACE)    pause                                                                      |                |\\N"
        .. "\\h                                                                                     |     +vol       |\\N"
        .. " (" .. fullscreen_key .. ")        toggle fullscreen                                                          |       ^        |\\N"
        .. "(q)        start from beginning                                                       | -ch <   > +ch  |\\N"
        .. "(qq)       quit                                                                       |       v        |\\N"
        .. "\\h                                                                                     |     -vol       |\\N"
        .. "(HOME)     keep new movie                                                             |                |\\N"
        .. "(DEL)      delete file                                                                |    [pause]     |\\N"
        .. "\\h                                                                                     | [restart/quit] |\\N"
        .. "(7) and (9) seek chapters                                                             |                |\\N"
        .. "(4) and (6) seek files                                                                | -file   +file  |\\N"
        .. "(1) and (3) seek time                                                                 | -time   +time  |\\N"
        .. "\\h                                                                                     |                |\\N"
        .. "(8) random episode                                                             |                |\\N"
        .. "(5) cycle filters                                                                     |                |\\N"
        .. "(0) start from beginning                                                              +----------------+\\N"
        .. "{\\c&HFFFFFF&}"
    info_ov:update()
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

-- Fires after seek completes (including while paused) — refresh info if it's visible
mp.register_event("playback-restart", function()
    if info_ov then show_info() end
end)

-- Info screen and pause filter follow the pause state, however pause was
-- toggled (keys, remote, mouse/GUI, IPC). Paused: CRT filter + info screen.
-- Playing: no info, and whatever filter was on before pausing (e.g. a KP5 pick).
local PAUSE_SHADERS = "NoChroma.hook:crt-lottes.glsl"
local saved_shaders = nil
-- Darken the paused picture so the yellow info text stands out. Uses gamma,
-- not brightness, since charlietv3_keys.lua resets brightness on every seek.
local PAUSE_GAMMA = -5

mp.observe_property("pause", "bool", function(_, paused)
    if paused then
        if saved_shaders == nil then
            saved_shaders = mp.get_property_native("glsl-shaders") or {}
        end
        mp.set_property("glsl-shaders", PAUSE_SHADERS)
        mp.set_property_number("gamma", PAUSE_GAMMA)
        show_info()
    else
        if saved_shaders ~= nil then
            mp.set_property_native("glsl-shaders", saved_shaders)
            saved_shaders = nil
            mp.set_property_number("gamma", 0)
        end
        if info_ov then
            info_ov:remove()
            info_ov = nil
        end
    end
end)
