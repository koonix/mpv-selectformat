-- author: Ehsan Ghorbannezhad <ehsan@disroot.org>
-- select the video's youtube-dl format via a menu.

-- TODO: fold audio-only formats too
-- TODO: fix all the (width or "sth").. stuff
-- TODO: make cursor pos be bound to a format_id, not menu position
-- TODO: if fold contains only one format, do not unfold
--       (why do this tho? it creates an special case and is confusing and inconsistend)
-- TODO: refactor everything

-- ===============
-- = Global Vars
-- ===============

local msg     = require "mp.msg"
local utils   = require "mp.utils"
local options = require "mp.options"
local assdraw = require "mp.assdraw"

local opts = {
    prefix_cursor    = "● ",
    prefix_norm_sel  = "○ ",
    prefix_norm      = ". ",
    prefix_header    = "- ",
    prefix_indent    = "> ",
    menu_padding_x   = 5,
    menu_padding_y   = 5,
    ass_style = "{\\fnmonospace\\fs8}",
}
options.read_options(opts)

local keys = {
    { { "UP",    "k" },      "up",     function() menu_cursor_move(-1) end, { repeatable=true } },
    { { "DOWN",  "j" },      "down",   function() menu_cursor_move( 1) end, { repeatable=true } },
    { { "PGUP",  "ctrl+u" }, "pgup",   function() menu_cursor_move(-5) end, { repeatable=true } },
    { { "PGDWN", "ctrl+d" }, "pgdwn",  function() menu_cursor_move( 5) end, { repeatable=true } },
    { { "HOME",  "g" },      "top",    function() menu_cursor_move("top")    end },
    { { "END",   "G" },      "bottom", function() menu_cursor_move("bottom") end },
    { { "RIGHT", "l" },      "unfold", function() menu_unfold() end },
    { { "LEFT",  "h" },      "fold",   function() menu_fold()   end },
    { { "ESC",   "q" },      "quit",   function() menu_hide()   end },
    { { "ENTER" },           "select", function() menu_select() end },
}

local data = {}
local url = ""
local ytdl_path = ""
local is_menu_shown = false

-- ===============
-- = Declarations
-- ===============

local main
local formats_fetch
local formats_save
local formats_fold
local menu_toggle
local menu_show
local menu_init_vars
local menu_init_cursor_pos
local menu_hide
local menu_draw
local menu_get_prefix
local menu_get_indent_marker
local menu_keys_bind
local menu_keys_unbind
local menu_cursor_move
local menu_unfold
local menu_fold
local get_unfolded_pos
local menu_select
local is_fetch_in_progress
local no_formats_available
local build_ytdl_format_str
local build_format_label
local get_menu_header
local strfmt_label
local format_sort_fn
local get_param_precedence
local is_format_useful
local sanitize_format
local get_ytdl_cmdline
local get_ytdl_format_args
local is_format_audioonly
local is_loaded_file_audioonly
local is_param_valid
local is_param_empty
local update_url
local numshorten
local sigcmp
local is_network_stream
local reload_resume
local update_ytdl_path
local find_executable_path
local get_ytdl_hook_opt_paths
local execasync
local exec
local is_os_windows
local isempty
local isnum
local isstr
local istable

-- ===============
-- = Functions
-- ===============

function main()
    mp.register_event("start-file", formats_fetch)
    mp.register_event("end-file", menu_hide)
    mp.add_key_binding(nil, "menu", menu_toggle)
end

-- fetch the formats using youtube-dl asyncronously and hand them to formats_save()
function formats_fetch()
    if not update_url() then return end
    if data[url] then return end
    if not update_ytdl_path() then return end
    data[url] = "fetching"
    execasync(function(a, b, c) formats_save(url, a, b, c) end, get_ytdl_cmdline())
end

-- process the formats fetched by formats_fetch()
function formats_save(url, success, result, error)
    data[url] = nil
    if (not success) or result.status ~= 0 then return end
    local json = utils.parse_json(result.stdout)
    if (not istable(json)) or (not istable(json.formats)) then return end
    data[url] = { formats = {} }
    data[url].initial_format_id = json.format_id
    for _, fmt in ipairs(json.formats) do
        if is_format_useful(fmt) then
            fmt = sanitize_format(fmt)
            fmt.label = build_format_label(fmt)
            fmt.ytdl_format = build_ytdl_format_str(fmt)
            table.insert(data[url].formats, fmt)
        end
    end
    if no_formats_available() then return end
    table.sort(data[url].formats, format_sort_fn)
    data[url].formats_unfolded = data[url].formats
    formats_fold()
end

function formats_fold(width, height)
    data[url].formats = {}
    local enummed_res = {}
    local unfold_res = (width or "null").."x"..(height or "null")
    for _, fmt in ipairs(data[url].formats_unfolded) do
        local res = (fmt.width or "").."x"..(fmt.height or "")
        if res == "x" then res = fmt.format_id end
        fmt.is_unfolded = false
        if not enummed_res[res] or res == unfold_res then
            enummed_res[res] = true
            if res == unfold_res then fmt.is_unfolded = true end
            table.insert(data[url].formats, fmt)
        end
    end
end

-- show/hide the menu
function menu_toggle()
    if not update_url() then
        mp.osd_message("Formats are only fetched for internet videos.")
        return
    elseif not update_ytdl_path() then
        mp.osd_message("Couldn't find a youtube-dl executable.")
        return
    end
    if is_menu_shown then menu_hide() else menu_show() end
end

function menu_show()
    if is_fetch_in_progress() then
        mp.osd_message("Formats are being fetched...")
        return
    elseif no_formats_available() then
        mp.osd_message("No formats available.")
        return
    end
    is_menu_shown = true
    menu_init_vars()
    menu_draw()
    menu_keys_bind()
end

function menu_init_vars()
    if data[url].cursor_pos == nil or data[url].selected_pos == nil then
        data[url].cursor_pos = 1
        data[url].selected_pos = 0
        menu_init_cursor_pos()
    end
end

-- put the cursor on the initially loaded format.
-- see the comments of the get_ytdl_format_args() function for more info.
function menu_init_cursor_pos()
    local id = data[url].initial_format_id
    if isempty(id) or not isstr(id) then return end
    id = id:match("^(.*)%+") or id
    for idx, fmt in ipairs(data[url].formats) do
        if fmt.format_id == id then
            data[url].cursor_pos = idx
            data[url].selected_pos = idx
        end
    end
end

function menu_hide()
    if is_menu_shown then
        is_menu_shown = false
        mp.set_osd_ass(0, 0, "")
        menu_keys_unbind()
    end
end

function menu_draw()
    local ass = assdraw.ass_new()
    ass:pos(opts.menu_padding_x, opts.menu_padding_y)
    ass:append(opts.ass_style)
    ass:append(opts.prefix_header..get_menu_header().."\\N")
    for idx, fmt in ipairs(data[url].formats) do
        ass:append(menu_get_prefix(idx))
        ass:append(menu_get_indent_marker(idx))
        ass:append(fmt.label.."\\N")
    end
    mp.set_osd_ass(0, 0, ass.text)
end

function menu_get_prefix(pos)
    if pos == data[url].cursor_pos then
        return opts.prefix_cursor
    elseif pos == data[url].selected_pos then
        return opts.prefix_norm_sel
    else
        return opts.prefix_norm
    end
end

function menu_get_indent_marker(pos)
    if data[url].formats[pos].is_unfolded then
        return opts.prefix_indent
    else
        return ""
    end
end

-- bind the menu movement/action keys
function menu_keys_bind()
    for _, v in ipairs(keys) do
        for i, key in ipairs(v[1]) do
            mp.add_forced_key_binding(key, v[2]..i, v[3], v[4])
        end
    end
end

-- unbind the menu movement/action keys
function menu_keys_unbind()
    for _, v in ipairs(keys) do
        for i in ipairs(v[1]) do
            mp.remove_key_binding(v[2]..i)
        end
    end
end

function menu_cursor_move(i)
    if i == "top" then
        data[url].cursor_pos = 1
    elseif i == "bottom" then
        data[url].cursor_pos = #data[url].formats
    else
        data[url].cursor_pos = data[url].cursor_pos + i
        if data[url].cursor_pos < 1 then
            data[url].cursor_pos = 1
        elseif data[url].cursor_pos > #data[url].formats then
            data[url].cursor_pos = #data[url].formats
        end
    end
    menu_draw()
end

function menu_unfold()
    local cursor_fmt = data[url].formats[data[url].cursor_pos]
    formats_fold(cursor_fmt.width, cursor_fmt.height)
    menu_draw()
end

function menu_fold()
    data[url].cursor_pos = get_unfolded_pos()
    formats_fold()
    menu_draw()
end

function get_unfolded_pos()
    local cursor_res = ""
    local function getres(fmt)
        return (fmt.width or "null").."x"..(fmt.height or "null")
    end
    for i = #data[url].formats, 1, -1 do
        local fmt = data[url].formats[i]
        if i == data[url].cursor_pos then
            cursor_res = getres(fmt)
        end
        if cursor_res ~= "" and getres(fmt) ~= cursor_res then
            return i + 1
        end
    end
    return 1
end

function menu_select()
    menu_hide()
    local sel = data[url].cursor_pos
    data[url].selected_pos = sel
    mp.set_property("ytdl-format", data[url].formats[sel].ytdl_format)
    reload_resume()
end

function is_fetch_in_progress()
    return data[url] == "fetching"
end

function no_formats_available()
    return not istable(data[url])
        or not istable(data[url].formats)
        or #data[url].formats == 0
end

-- build the youtube-dl format option for the given format
function build_ytdl_format_str(fmt)
    if is_format_audioonly(fmt) then
        return string.format("%s/bestaudio", fmt.format_id)
    else
        local audiofmt = "bestaudio"
        maxpx = math.max(tonumber(fmt.width or "1"), tonumber(fmt.height or "1"))
        if maxpx < 1000 then audiofmt = "bestaudio[abr<=70]" end
        return string.format("%s+%s/%s+bestaudio/%s/best",
            fmt.format_id, audiofmt, fmt.format_id, fmt.format_id)
    end
end

-- build the label that represents the format in the UI
function build_format_label(fmt)
    local res, codec, br, formatstr
    if is_format_audioonly(fmt) then
        res = "audio-only"
        codec = fmt.acodec
        br = fmt.abr or fmt.tbr
    else
        res = (fmt.width or "?").."x"..(fmt.height or "?")
        codec = fmt.vcodec
        br = fmt.vbr or fmt.tbr
    end
    if codec then
        codec = codec:gsub("%..*", ""):gsub("av01", "av1")
        codec = codec:gsub("avc1", "h264"):gsub("h265", "hevc")
    end
    return strfmt_label(
        res,
        fmt.fps and numshorten(fmt.fps) or "",
        codec or "",
        br and numshorten(br * 10^3) or "",
        fmt.asr and numshorten(fmt.asr) or "",
        fmt.protocol or ""
    )
end

function get_menu_header()
    return strfmt_label("Resolution", "FPS", "Codec", "BR", "ASR", "Proto")
end

function strfmt_label(...)
    return string.format("%-10s %-3s %-5s %-4s %-4s %s", ...)
end

-- function for sorting the formats table
function format_sort_fn(a, b)
    local params = {
        "fps", "dynamic_range", "vcodec",
        "acodec", "tbr", "vbr", "abr", "asr", "protocol"
    }
    a.res = (a.width or 1) * (a.height or 1)
    b.res = (b.width or 1) * (b.height or 1)
    if     a.res > b.res then return true
    elseif a.res < b.res then return false end
    for _, v in ipairs({1, 2}) do
        for _, p in ipairs(params) do
            local do_sigcmp =
                v == 1 and isnum(a[p]) and isnum(b[p]) and true or false
            local x = isnum(a[p]) and a[p] or get_param_precedence(p, a[p])
            local y = isnum(b[p]) and b[p] or get_param_precedence(p, b[p])
            if do_sigcmp then
                if     sigcmp(x, ">", y) then return true
                elseif sigcmp(x, "<", y) then return false end
            else
                if     x > y then return true
                elseif x < y then return false end
            end
        end
    end
    return a.format_id > b.format_id
end

-- rate the given parameter value based on it's precedence
function get_param_precedence(param, value)
    local order = {
        dynamic_range = {
            "sdr", "^$", "hlg", "h?d?r?10$", "h?d?r?10%+", "h?d?r?12", "dv"
        },
        vcodec = {
            "theora", { "mp4v", "h263" }, "vp0?8", { "[hx]264", "avc" },
            { "[hx]265", "he?vc" }, "vp0?9$", "vp0?9%.2", "av0?1",
        },
        acodec = {
            "dts", "^ac%-?3", "e%-?a?c%-?3", "mp3", "mp?4a?", "avc",
            { "vorbis", "ogg" }, "opus"
        },
        protocol = {
            "f4", { "ws", "websocket$" }, { "mms", "rtsp" }, "^$", "rtmpe?",
            "websocket_frag", ".*dash", "m3u8.*", { "http$", "ftp$" },
            { "https", "ftps" },
        },
    }
    if isempty(order[param]) then
        return tonumber(value) or 0
    elseif isempty(value) then
        value = ""
    end
    local n = 1
    for _, patternlist in ipairs(order[param]) do
        patternlist = type(patternlist) == "table" and patternlist or { patternlist }
        for _, pattern in ipairs(patternlist) do
            if value:lower():find(pattern) then
                return n
            end
        end
        n = n + 1
    end
    return 0
end

-- test wether the given format contains the bare minimum of information
function is_format_useful(fmt)
    if (not istable(fmt)) or fmt.ext == "mhtml" or fmt.protocol == "mhtml" then
        return false
    end
    local params = {
        "format_id", "vcodec", "acodec", "width", "height", "vbr", "abr", "tbr"
    }
    for _, p in ipairs(params) do
        if is_param_valid(fmt[p]) then
            return true
        end
    end
    return false
end

-- convert the parameters of the given format to their own appropriate type
function sanitize_format(fmt)
    local numeric_params = {
        "width", "height", "fps", "tbr", "vbr", "abr", "asr"
    }
    local string_params = {
        "format_id", "dynamic_range", "vcodec", "acodec", "protocol"
    }
    for _, p in ipairs(numeric_params) do
        if is_param_empty(fmt[p]) then
            fmt[p] = nil
        elseif isstr(fmt[p]) then
            fmt[p] = tonumber(fmt[p])
        elseif not isnum(fmt[p]) then
            fmt[p] = nil
        end
    end
    for _, p in ipairs(string_params) do
        if is_param_empty(fmt[p]) then
            fmt[p] = nil
        elseif isnum(fmt[p]) then
            fmt[p] = tostring(fmt[p])
        elseif not isstr(fmt[p]) then
            fmt[p] = nil
        end
    end
    return fmt
end

-- build and return the command that needs to run in order to fetch the formats
function get_ytdl_cmdline()
    local args = { ytdl_path, "--no-playlist", "-j" }
    for _, format_arg in ipairs(get_ytdl_format_args()) do
        table.insert(args, format_arg)
    end
    table.insert(args, "--")
    table.insert(args, (url:gsub("^ytdl://", "")))
    return args
end

-- get youtube-dl's format related options that are specified in mpv's
-- command line options or config file. if we call the youtube-dl command
-- with these options included, the initially loaded format will be apparent
-- in the "format_id" parameter of the infojson.
function get_ytdl_format_args()
    local args = {}
    local fmtopt = mp.get_property("ytdl-format")
    local rawopts = mp.get_property_native("ytdl-raw-options")
    if isempty(fmtopt) then
        fmtopt = is_loaded_file_audioonly()
            and "bestaudio/best"
            or  "bestvideo+bestaudio/best"
    end
    if fmtopt ~= "ytdl" then
        table.insert(args, "--format")
        table.insert(args, fmtopt)
    end
    if istable(rawopts) and isstr(rawopts["format-sort"]) then
        table.insert(args, "--format-sort")
        table.insert(args, rawopts["format-sort"])
    end
    return args
end

-- test wether the given format only contains an audio stream
function is_format_audioonly(fmt)
    return is_param_valid(fmt.acodec) and (not is_param_valid(fmt.vcodec))
end

function is_loaded_file_audioonly()
    return mp.get_property("video") == "no"
end

function is_param_valid(p)
    return isnum(p) or (isstr(p) and (not is_param_empty(p)))
end

-- test wether the given format parameter is empty
function is_param_empty(p)
    return isempty(p) or p == "none" or p == "null"
end

-- update the global url variable with the URL of the currently playing video
function update_url()
    local path = mp.get_property("path")
    if isstr(path) and is_network_stream(path) then
        url = path
        return true
    else
        return false
    end
end

-- shorten and format the given number (eg. 4560 -> 4K)
function numshorten(n)
    n = math.floor(n + 0.5) -- round the number
    if     n >= 10^9 then return string.format("%dG", n / 10^9)
    elseif n >= 10^6 then return string.format("%dM", n / 10^6)
    elseif n >= 10^3 then return string.format("%dK", n / 10^3)
    else                  return string.format("%d" , n) end
end

-- compare the given numbers, but only succeed if the larger
-- number is significantly (15%) larger than the smaller one.
function sigcmp(a, operator, b)
    local fraction = 0.15
    if operator == ">" and a > b + (a * fraction) then
        return true
    elseif operator == "<" and a + (b * fraction) < b then
        return true
    else
        return false
    end
end

-- test wether the given path or URL is a network stream.
-- works by checking the given URL's protocol.
function is_network_stream(path)
    local proto = path:match("^(%a+)://")
    if not proto then return false end
    for _, p in ipairs{
        "http", "https", "ytdl", "rtmp", "rtmps", "rtmpe", "rtmpt", "rtmpts",
        "rtmpte", "rtsp", "rtsps", "mms", "mmst", "mmsh", "mmshttp", "rtp",
        "srt", "srtp", "gopher", "gophers", "data", "ftp", "ftps", "sftp" }
    do
        if proto == p then return true end
    end
    return false
end

-- this function is a modified version of mpv-reload's reload_resume()
-- https://github.com/4e6/mpv-reload, commit c1219b6
function reload_resume()
    local pos = mp.get_property("time-pos")
    local duration = mp.get_property_native("duration")
    local plcount = mp.get_property_number("playlist-count")
    local plpos = mp.get_property_number("playlist-pos")
    local playlist = {}
    for i = 0, plcount - 1 do
        playlist[i] = mp.get_property("playlist/"..i.."/filename")
    end
    if pos and isnum(duration) and duration >= 0 then
        mp.commandv("loadfile", url, "replace", "start=+"..pos)
    else
        mp.commandv("loadfile", url, "replace")
    end
    for i = 0, plpos - 1 do
        mp.commandv("loadfile", playlist[i], "append")
    end
    mp.commandv("playlist-move", 0, plpos + 1)
    for i = plpos + 1, plcount - 1 do
        mp.commandv("loadfile", playlist[i], "append")
    end
end

-- search for yt-dlp or youtube-dl executable's path and update the ytdl-path variable
function update_ytdl_path()
    if ytdl_path == nil then
        return false
    elseif not isempty(ytdl_path) then
        return true
    end
    local paths = {}
    paths = get_ytdl_hook_opt_paths() or { "yt-dlp", "yt-dlp_x86", "youtube-dl" }
    for _, p in pairs(paths) do
        p = find_executable_path(p)
        if p then
            ytdl_path = p
            return true
        end
    end
    msg.warn("couldn't find a youtube-dl executable")
    ytdl_path = nil
    return false
end

-- search in config dirs and system's path for the given youtube-dl executable name
function find_executable_path(name)
    local suffix = is_os_windows() and ".exe" or ""
    local cname = mp.find_config_file(name..suffix)
    if cname then
        return cname
    elseif exec({name, "--version"}).error_string ~= "init" then
        return name
    end
    return nil
end

-- get the paths specified in ytdl_hook's ytdl_path script-opt
-- if there aren't any paths specified there, return false
function get_ytdl_hook_opt_paths()
    local paths = {}
    local sep = is_os_windows() and ";" or ":"
    local hook_opts = { ytdl_path = "" }
    options.read_options(hook_opts, "ytdl_hook")
    for p in hook_opts.ytdl_path:gmatch("[^"..sep.."]+") do
        table.insert(paths, p)
    end
    return #paths > 0 and paths or false
end

-- asynchronously execute shell commands using mpv's subprocess command
function execasync(fn, args)
    mp.command_native_async({ name = "subprocess", args = args,
        capture_stdout = true, capture_stderr = true }, fn)
end

-- execute shell commands using mpv's subprocess command
function exec(args)
    return mp.command_native{ name = "subprocess", args = args,
        capture_stdout = true, capture_stderr = true }
end

function is_os_windows()
    return package.config:sub(1,1) == "\\"
end

function isempty(var)
    return var == nil or var == ""
end

function isnum(var)
    return type(var) == "number"
end

function isstr(var)
    return type(var) == "string"
end

function istable(var)
    return type(var) == "table"
end

-- if table.unpack() isn't available, use unpack() instead
if not table.unpack then
    table.unpack = unpack
end

main()

-- vim:expandtab
