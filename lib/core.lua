local CC = rawget(_G, "chatcolor")
if type(CC) ~= "table" then
    CC = {}
    rawset(_G, "chatcolor", CC)
end
if CC._core_loaded then
    return
end
CC._core_loaded = true

local core = CC._core
if type(core) ~= "table" then
    core = {}
    CC._core = core
end

local PRIV_USE = "chatcolor.use"
local PRIV_COLOR_ALL = "chatcolor.color.*"
CC.PRIV_USE = PRIV_USE
CC.PRIV_COLOR_ALL = PRIV_COLOR_ALL
core.PRIV_USE = PRIV_USE
core.PRIV_COLOR_ALL = PRIV_COLOR_ALL

local storage = minetest.get_mod_storage()
local selected_styles = {}
local gui_inputs = {}

core.storage = storage
core.selected_styles = selected_styles
core.gui_inputs = gui_inputs

local COLOR_BY_CODE = {
    ["0"] = "black",
    ["1"] = "dark_blue",
    ["2"] = "dark_green",
    ["3"] = "dark_aqua",
    ["4"] = "dark_red",
    ["5"] = "dark_purple",
    ["6"] = "gold",
    ["7"] = "gray",
    ["8"] = "dark_gray",
    ["9"] = "blue",
    a = "green",
    b = "aqua",
    c = "red",
    d = "light_purple",
    e = "yellow",
    f = "white",
    r = "reset",
}

local CODE_BY_COLOR = {}
for code, color in pairs(COLOR_BY_CODE) do
    CODE_BY_COLOR[color] = code
end
CODE_BY_COLOR.grey = CODE_BY_COLOR.gray
CODE_BY_COLOR.darkgrey = CODE_BY_COLOR.dark_gray
CODE_BY_COLOR.darkgray = CODE_BY_COLOR.dark_gray
CODE_BY_COLOR.purple = "5"
CODE_BY_COLOR.darkpurple = "5"
CODE_BY_COLOR.pink = "d"
CODE_BY_COLOR.magenta = "d"
CODE_BY_COLOR.lightpurple = "d"

local COLOR_NAMES_BY_CODE = {}
for color_name, code in pairs(CODE_BY_COLOR) do
    if not COLOR_NAMES_BY_CODE[code] then
        COLOR_NAMES_BY_CODE[code] = {}
    end
    COLOR_NAMES_BY_CODE[code][#COLOR_NAMES_BY_CODE[code] + 1] = color_name
end

core.COLOR_BY_CODE = COLOR_BY_CODE
core.CODE_BY_COLOR = CODE_BY_COLOR
core.COLOR_NAMES_BY_CODE = COLOR_NAMES_BY_CODE

local function trim(s)
    return tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function normalize_color_name(input)
    local key = tostring(input or ""):lower()
    key = key:gsub("%s+", "_"):gsub("%-", "_")
    return key
end

local function normalize_hex(input)
    local h = tostring(input or ""):match("^#([%x][%x][%x][%x][%x][%x])$")
    if not h then
        return nil
    end
    return "#" .. h:lower()
end

local function pretty_color_name(input)
    local text = tostring(input or ""):gsub("_", " ")
    return (text:gsub("(%a)([%w']*)", function(a, b)
        return a:upper() .. b:lower()
    end))
end

local function formspec_escape(s)
    return minetest.formspec_escape(tostring(s or ""))
end

local function hypertext_escape(s)
    local value = tostring(s or "")
    if type(minetest.hypertext_escape) == "function" then
        return minetest.hypertext_escape(value)
    end
    value = value:gsub("&", "&amp;")
    value = value:gsub("<", "&lt;")
    value = value:gsub(">", "&gt;")
    value = value:gsub("\"", "&quot;")
    return value
end

core.trim = trim
core.normalize_color_name = normalize_color_name
core.normalize_hex = normalize_hex
core.pretty_color_name = pretty_color_name
core.formspec_escape = formspec_escape
core.hypertext_escape = hypertext_escape

local function key_for_player(player_name)
    return "selected_style:" .. tostring(player_name or "")
end

local function register_privilege_safe(name, def)
    local ok, err = pcall(minetest.register_privilege, name, def)
    if not ok then
        minetest.log("warning", "[chatcolor] Failed to register privilege '" .. tostring(name) .. "': " .. tostring(err))
    end
end

register_privilege_safe(PRIV_USE, {
    description = "Allows using Bukkit-style chat color codes (&0..&f, &r).",
    give_to_singleplayer = false,
})

register_privilege_safe(PRIV_COLOR_ALL, {
    description = "Allows setting any /chatcolor default color, including HEX and gradient.",
    give_to_singleplayer = false,
})

for color_name, _ in pairs(CODE_BY_COLOR) do
    local priv_name = "chatcolor.color." .. color_name
    register_privilege_safe(priv_name, {
        description = "Allows /chatcolor " .. color_name .. ".",
        give_to_singleplayer = false,
    })
end

local function has_use_priv(player_name)
    if type(player_name) ~= "string" or player_name == "" then
        return false
    end
    return minetest.check_player_privs(player_name, {[PRIV_USE] = true})
end

local function has_wildcard_color_priv(player_name)
    if type(player_name) ~= "string" or player_name == "" then
        return false
    end
    return minetest.check_player_privs(player_name, {[PRIV_COLOR_ALL] = true})
end

local function has_color_priv_for_code(player_name, code)
    if has_wildcard_color_priv(player_name) then
        return true
    end
    local key = tostring(code or ""):lower():gsub("^&", "")
    if key == "" then
        return false
    end
    local names = COLOR_NAMES_BY_CODE[key]
    if type(names) ~= "table" then
        return false
    end
    for _, color_name in ipairs(names) do
        if minetest.check_player_privs(player_name, {["chatcolor.color." .. color_name] = true}) then
            return true
        end
    end
    return false
end

local function has_color_priv(player_name, color_name)
    local key = normalize_color_name(color_name)
    return has_color_priv_for_code(player_name, CODE_BY_COLOR[key])
end

local function get_color_lib()
    local C = rawget(_G, "color_lib")
    if type(C) ~= "table" then
        return nil
    end
    return C
end

core.has_use_priv = has_use_priv
core.has_wildcard_color_priv = has_wildcard_color_priv
core.has_color_priv_for_code = has_color_priv_for_code
core.has_color_priv = has_color_priv
core.get_color_lib = get_color_lib

local function encode_style(style)
    if type(style) ~= "table" then
        return ""
    end

    if style.kind == "legacy" then
        local code = tostring(style.code or ""):lower():gsub("^&", "")
        if code:match("^[0-9a-fr]$") then
            return "legacy:&" .. code
        end
        return ""
    end

    if style.kind == "hex" then
        local color = normalize_hex(style.color)
        if color then
            return "hex:" .. color
        end
        return ""
    end

    if style.kind == "gradient" then
        local from = normalize_hex(style.from)
        local to = normalize_hex(style.to)
        if from and to then
            return "gradient:" .. from .. ":" .. to
        end
        return ""
    end

    return ""
end

local function decode_style(raw)
    local stored = trim(raw)
    if stored == "" then
        return nil
    end

    local legacy_code = stored:match("^legacy:(&?[0-9a-fr])$")
    if legacy_code then
        local ch = legacy_code:lower():gsub("^&", "")
        return {
            kind = "legacy",
            code = "&" .. ch,
            color_name = COLOR_BY_CODE[ch],
        }
    end

    local hex_color = stored:match("^hex:(#%x%x%x%x%x%x)$")
    if hex_color then
        return {
            kind = "hex",
            color = hex_color:lower(),
        }
    end

    local g1, g2 = stored:match("^gradient:(#%x%x%x%x%x%x):(#%x%x%x%x%x%x)$")
    if g1 and g2 then
        return {
            kind = "gradient",
            from = g1:lower(),
            to = g2:lower(),
        }
    end

    -- Backward compatibility with old stored format (&f / f / #rrggbb)
    local old_code = stored:lower():match("^&?([0-9a-fr])$")
    if old_code then
        return {
            kind = "legacy",
            code = "&" .. old_code,
            color_name = COLOR_BY_CODE[old_code],
        }
    end

    local old_hex = normalize_hex(stored)
    if old_hex then
        return {
            kind = "hex",
            color = old_hex,
        }
    end

    return nil
end

local function get_selected_style(player_name)
    if type(player_name) ~= "string" or player_name == "" then
        return nil
    end

    local cached = selected_styles[player_name]
    if cached ~= nil then
        if cached == false then
            return nil
        end
        return cached
    end

    local style = decode_style(storage:get_string(key_for_player(player_name)))
    if not style then
        selected_styles[player_name] = false
        return nil
    end

    selected_styles[player_name] = style
    return style
end

local function set_selected_style(player_name, style)
    if type(player_name) ~= "string" or player_name == "" then
        return false
    end

    local encoded = encode_style(style)
    if encoded == "" then
        storage:set_string(key_for_player(player_name), "")
        selected_styles[player_name] = false
        return true
    end

    storage:set_string(key_for_player(player_name), encoded)
    selected_styles[player_name] = decode_style(encoded)
    return true
end

local function clear_player_state(player_name)
    if type(player_name) ~= "string" or player_name == "" then
        return
    end
    selected_styles[player_name] = nil
    gui_inputs[player_name] = nil
end

local function style_summary(style)
    if type(style) ~= "table" then
        return "None"
    end
    if style.kind == "legacy" then
        return pretty_color_name(style.color_name or "color") .. " (" .. tostring(style.code or "") .. ")"
    end
    if style.kind == "hex" then
        return tostring(style.color or "")
    end
    if style.kind == "gradient" then
        return "Gradient selected"
    end
    return "None"
end

core.get_selected_style = get_selected_style
core.set_selected_style = set_selected_style
core.style_summary = style_summary
core.clear_player_state = clear_player_state

local function parse_legacy_color(input)
    local lower = trim(input):lower()

    local code_from_name = CODE_BY_COLOR[normalize_color_name(lower)]
    if code_from_name then
        return {
            kind = "legacy",
            code = "&" .. code_from_name,
            color_name = normalize_color_name(lower),
        }, nil
    end

    local C = get_color_lib()
    if not C or type(C.read_minecraft_legacy_token) ~= "function" then
        return nil, "color_lib parser unavailable"
    end

    local _, step = C.read_minecraft_legacy_token(lower, 1, {
        code_char = "&",
        allow_section = true,
        case = "lower",
    })
    if step == #lower then
        local code = lower:sub(#lower, #lower)
        if COLOR_BY_CODE[code] then
            return {
                kind = "legacy",
                code = "&" .. code,
                color_name = COLOR_BY_CODE[code],
            }, nil
        end
    end

    return nil, "Use a color name, one code like &f, one hex (#22EC7A), gradient (#22EC7A #0448D1), or /chatcolor off."
end

local function parse_chatcolor_param(raw)
    local input = trim(raw)
    if input == "" then
        return nil, "Usage: /chatcolor <color|&code|#HEX [#HEX]|off>"
    end

    local lower = input:lower()
    if lower == "off" or lower == "none" or lower == "clear" then
        return {kind = "none"}, nil
    end

    local args = {}
    for token in input:gmatch("%S+") do
        args[#args + 1] = token
    end

    if #args == 1 then
        local h1 = normalize_hex(args[1])
        if h1 then
            return {
                kind = "hex",
                color = h1,
            }, nil
        end
    elseif #args == 2 then
        local h1 = normalize_hex(args[1])
        local h2 = normalize_hex(args[2])
        if h1 and h2 then
            return {
                kind = "gradient",
                from = h1,
                to = h2,
            }, nil
        end
        if h1 or h2 then
            return nil, "Gradient usage: /chatcolor #22EC7A #0448D1"
        end
    end

    return parse_legacy_color(input)
end

local function apply_style_for_player(player_name, style)
    if type(player_name) ~= "string" or player_name == "" then
        return false, "Player not found."
    end
    if type(style) ~= "table" then
        return false, "Invalid style."
    end

    if style.kind == "none" then
        set_selected_style(player_name, nil)
        return true, "Default chat color cleared."
    end

    if style.kind == "legacy" then
        if not has_color_priv_for_code(player_name, style.code) then
            return false, "You do not have permission for that color."
        end
        set_selected_style(player_name, style)
        return true, "Default chat color set to " .. tostring(style.color_name) .. " (" .. style.code .. ")."
    end

    if style.kind == "hex" or style.kind == "gradient" then
        if not has_wildcard_color_priv(player_name) then
            return false, "You do not have permission for HEX or gradient."
        end
        set_selected_style(player_name, style)
        if style.kind == "hex" then
            return true, "Default chat HEX color set to " .. tostring(style.color) .. "."
        end
        return true, "Default chat gradient set to " .. tostring(style.from) .. " -> " .. tostring(style.to) .. "."
    end

    return false, "Invalid style."
end

core.parse_chatcolor_param = parse_chatcolor_param
core.apply_style_for_player = apply_style_for_player

CC.has_use_priv = has_use_priv
CC.has_color_priv = has_color_priv
CC.get_selected_color = function(player_name)
    local style = get_selected_style(player_name)
    if style and style.kind == "legacy" then
        return style.code
    end
    return nil
end
CC.get_selected_style = get_selected_style
