local CC = rawget(_G, "chatcolor")
if type(CC) ~= "table" then
    CC = {}
    rawset(_G, "chatcolor", CC)
end
if CC._module_loaded then
    return
end
CC._module_loaded = true

local PRIV_USE = "chatcolor.use"
local PRIV_COLOR_ALL = "chatcolor.color.*"
CC.PRIV_USE = PRIV_USE
CC.PRIV_COLOR_ALL = PRIV_COLOR_ALL

local storage = minetest.get_mod_storage()
local selected_styles = {}
local gui_inputs = {}

local GUI_FORMNAME = "chatcolor:gui"
local PREVIEW_PHRASE = "Hello world! I am John Doe"
local GUI_ERROR_TTL_SEC = 3
local LEGACY_GUI_CODES = {
    "0", "1", "2", "3",
    "4", "5", "6", "7",
    "8", "9", "a", "b",
    "c", "d", "e", "f",
}
local LEGACY_HEX_BY_CODE = {
    ["0"] = "#000000",
    ["1"] = "#0000aa",
    ["2"] = "#00aa00",
    ["3"] = "#00aaaa",
    ["4"] = "#aa0000",
    ["5"] = "#aa00aa",
    ["6"] = "#ffaa00",
    ["7"] = "#aaaaaa",
    ["8"] = "#555555",
    ["9"] = "#5555ff",
    a = "#55ff55",
    b = "#55ffff",
    c = "#ff5555",
    d = "#ff55ff",
    e = "#ffff55",
    f = "#ffffff",
    r = "#ffffff",
}

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

local function preview_text_for_style(style)
    local function gradient_preview(from_hex, to_hex)
        local from = normalize_hex(from_hex) or "#ffffff"
        local to = normalize_hex(to_hex) or "#ffffff"
        local phrase = PREVIEW_PHRASE

        local r1 = tonumber(from:sub(2, 3), 16) or 255
        local g1 = tonumber(from:sub(4, 5), 16) or 255
        local b1 = tonumber(from:sub(6, 7), 16) or 255
        local r2 = tonumber(to:sub(2, 3), 16) or 255
        local g2 = tonumber(to:sub(4, 5), 16) or 255
        local b2 = tonumber(to:sub(6, 7), 16) or 255

        local chars = {}
        for ch in phrase:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
            chars[#chars + 1] = ch
        end
        if #chars == 0 then
            chars[1] = phrase
        end

        local out = {}
        local span = math.max(1, #chars - 1)
        for i, ch in ipairs(chars) do
            local t = (i - 1) / span
            local r = math.floor(r1 + ((r2 - r1) * t) + 0.5)
            local g = math.floor(g1 + ((g2 - g1) * t) + 0.5)
            local b = math.floor(b1 + ((b2 - b1) * t) + 0.5)
            local hex = string.format("#%02x%02x%02x", r, g, b)
            out[#out + 1] = minetest.get_color_escape_sequence(hex)
            out[#out + 1] = ch
        end
        out[#out + 1] = minetest.get_color_escape_sequence("#ffffff")
        return table.concat(out)
    end

    if type(style) ~= "table" then
        return "Preview: None"
    end

    if style.kind == "legacy" then
        local C = get_color_lib()
        if C and type(C.render_bukkit_text) == "function" then
            local rendered = C.render_bukkit_text((style.code or "&f") .. PREVIEW_PHRASE, {
                trim = false,
                allow_newlines = false,
                append_white = true,
            })
            if rendered then
                return "Preview: " .. rendered
            end
        end
        return "Preview: " .. tostring(style.code or "")
    end

    if style.kind == "hex" then
        return "Preview: " .. minetest.get_color_escape_sequence(style.color or "#ffffff")
            .. PREVIEW_PHRASE
            .. minetest.get_color_escape_sequence("#ffffff")
    end

    if style.kind == "gradient" then
        return "Preview: " .. gradient_preview(style.from, style.to)
    end

    return "Preview: None"
end

local function sync_gui_inputs_from_style(player_name)
    local state = gui_inputs[player_name]
    if type(state) ~= "table" then
        state = {}
        gui_inputs[player_name] = state
    end

    local style = get_selected_style(player_name)
    if style and style.kind == "hex" then
        state.hex_single = style.color or ""
        state.hex_from = ""
        state.hex_to = ""
    elseif style and style.kind == "gradient" then
        state.hex_single = ""
        state.hex_from = style.from or ""
        state.hex_to = style.to or ""
    else
        state.hex_single = state.hex_single or ""
        state.hex_from = state.hex_from or ""
        state.hex_to = state.hex_to or ""
    end
    if state.preview_style ~= nil and type(state.preview_style) ~= "table" then
        state.preview_style = nil
    end
    return state
end

local function build_gui_formspec(player_name, status)
    local state = sync_gui_inputs_from_style(player_name)
    local current = get_selected_style(player_name)
    local preview_line = preview_text_for_style(state.preview_style or current)

    local fs = {
        "formspec_version[4]",
        "size[12.2,10.4]",
        "label[0.5,0.45;ChatColor GUI]",
        "label[0.5,0.9;Use buttons for legacy colors, or type HEX / gradient.]",
        "button_exit[10.4,0.35;1.4,0.7;cc_close;Close]",
    }

    for idx, code in ipairs(LEGACY_GUI_CODES) do
        local col = (idx - 1) % 4
        local row = math.floor((idx - 1) / 4)
        local x = 0.5 + (col * 2.9)
        local y = 1.35 + (row * 0.78)
        local name = COLOR_BY_CODE[code] or code
        local label = pretty_color_name(name) .. " (&" .. code .. ")"
        local bg = LEGACY_HEX_BY_CODE[code] or "#444444"
        local font_color = (code == "6" or code == "7" or code == "a" or code == "b" or code == "d" or code == "e" or code == "f")
            and "#000000" or "#ffffff"
        fs[#fs + 1] = string.format("style[cc_legacy_%s;bgcolor=%s;font_color=%s]", code, bg, font_color)
        fs[#fs + 1] = string.format("button[%0.2f,%0.2f;2.75,0.65;cc_legacy_%s;%s]", x, y, code, formspec_escape(label))
    end

    fs[#fs + 1] = "box[0.45,4.75;11.3,0.02;#77777788]"
    fs[#fs + 1] = "label[0.6,5.35;Single]"
    fs[#fs + 1] = "field_close_on_enter[cc_hex_single;false]"
    fs[#fs + 1] = "field[0.6,5.60;3.5,0.85;cc_hex_single;;" .. formspec_escape(state.hex_single) .. "]"
    fs[#fs + 1] = "button[4.2,5.75;1.8,0.75;cc_apply_hex;Apply]"

    fs[#fs + 1] = "label[0.5,6.65;Gradient]"
    fs[#fs + 1] = "label[0.6,6.95;From]"
    fs[#fs + 1] = "label[4.2,6.95;To]"
    fs[#fs + 1] = "field_close_on_enter[cc_hex_from;false]"
    fs[#fs + 1] = "field_close_on_enter[cc_hex_to;false]"
    fs[#fs + 1] = "field[0.6,7.25;3.5,0.85;cc_hex_from;;" .. formspec_escape(state.hex_from) .. "]"
    fs[#fs + 1] = "field[4.2,7.25;3.5,0.85;cc_hex_to;;" .. formspec_escape(state.hex_to) .. "]"
    fs[#fs + 1] = "button[7.75,7.35;2.0,0.75;cc_apply_gradient;Apply]"
    fs[#fs + 1] = "button[7.9,8.95;2.0,0.75;cc_preview_fields;Preview]"
    fs[#fs + 1] = "button[10.0,8.95;1.2,0.75;cc_clear;Off]"

    fs[#fs + 1] = "box[0.45,8.72;11.3,0.02;#77777788]"
    fs[#fs + 1] = "label[0.5,8.95;Current: " .. formspec_escape(style_summary(current)) .. "]"
    fs[#fs + 1] = "label[0.5,9.35;" .. formspec_escape(preview_line) .. "]"

    local status_text = nil
    local status_is_error = false
    if type(status) == "table" then
        status_text = trim(status.text)
        status_is_error = status.is_error == true
    elseif type(status) == "string" then
        status_text = trim(status)
    end

    if status_text and status_text ~= "" then
        if status_is_error then
            local markup = "<global color=#ff5555>" .. hypertext_escape(status_text)
            fs[#fs + 1] = "hypertext[0.55,9.81;11.1,0.6;cc_status;" .. formspec_escape(markup) .. "]"
        else
            fs[#fs + 1] = "label[0.55,9.85;" .. formspec_escape(status_text) .. "]"
        end
    end

    return table.concat(fs)
end

local function open_gui(player_name, status)
    local player = minetest.get_player_by_name(player_name)
    if not player then
        return
    end

    local state = sync_gui_inputs_from_style(player_name)
    state.gui_open = true

    if status ~= nil then
        local status_text = ""
        local status_is_error = false
        local status_ttl = 0
        if type(status) == "table" then
            status_text = trim(status.text)
            status_is_error = status.is_error == true
            status_ttl = tonumber(status.ttl or 0) or 0
        else
            status_text = trim(status)
        end

        if status_text == "" then
            state.status = nil
        else
            local token = (tonumber(state.status_token) or 0) + 1
            state.status_token = token
            state.status = {
                text = status_text,
                is_error = status_is_error,
                token = token,
            }

            if status_ttl > 0 then
                minetest.after(status_ttl, function()
                    local player_state = gui_inputs[player_name]
                    if type(player_state) ~= "table" then
                        return
                    end
                    local active = player_state.status
                    if type(active) ~= "table" then
                        return
                    end
                    if active.token ~= token then
                        return
                    end
                    player_state.status = nil
                    if player_state.gui_open then
                        open_gui(player_name)
                    end
                end)
            end
        end
    end

    minetest.show_formspec(player_name, GUI_FORMNAME, build_gui_formspec(player_name, state.status))
end

local function preview_style_from_inputs(state)
    local single_hex = normalize_hex(state.hex_single)
    local from_hex = normalize_hex(state.hex_from)
    local to_hex = normalize_hex(state.hex_to)

    if from_hex and to_hex then
        return {
            kind = "gradient",
            from = from_hex,
            to = to_hex,
        }, nil
    end

    if single_hex then
        return {
            kind = "hex",
            color = single_hex,
        }, nil
    end

    local has_any = trim(state.hex_single or "") ~= ""
        or trim(state.hex_from or "") ~= ""
        or trim(state.hex_to or "") ~= ""
    if has_any then
        return nil, "Preview input invalid. Use #RRGGBB or both gradient colors."
    end
    return nil, "Enter HEX or gradient values first."
end

local function color_name_for_code(code)
    local ch = tostring(code or ""):lower():gsub("^&", "")
    return COLOR_BY_CODE[ch]
end

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

local function strip_player_color_tokens(C, text)
    local out = tostring(text or "")
    if C and type(C.strip_minecraft_legacy_tokens) == "function" then
        out = C.strip_minecraft_legacy_tokens(out, {
            code_char = "&",
            allow_section = true,
        })
    end
    if C and type(C.strip_minecraft_hex_tokens) == "function" then
        out = C.strip_minecraft_hex_tokens(out)
    end
    return out
end

local function split_utf8_chars(text)
    local chars = {}
    local s = tostring(text or "")
    for ch in s:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
        chars[#chars + 1] = ch
    end
    if #chars == 0 and s ~= "" then
        for i = 1, #s do
            chars[#chars + 1] = s:sub(i, i)
        end
    end
    return chars
end

local function hex_to_rgb(hex)
    local h = normalize_hex(hex)
    if not h then
        return nil, nil, nil
    end
    return tonumber(h:sub(2, 3), 16), tonumber(h:sub(4, 5), 16), tonumber(h:sub(6, 7), 16)
end

local function rgb_to_hex(r, g, b)
    local rr = math.max(0, math.min(255, math.floor((tonumber(r) or 0) + 0.5)))
    local gg = math.max(0, math.min(255, math.floor((tonumber(g) or 0) + 0.5)))
    local bb = math.max(0, math.min(255, math.floor((tonumber(b) or 0) + 0.5)))
    return string.format("#%02x%02x%02x", rr, gg, bb)
end

local function apply_gradient(text, from_hex, to_hex)
    local chars = split_utf8_chars(text)
    if #chars == 0 then
        return ""
    end

    local r1, g1, b1 = hex_to_rgb(from_hex)
    local r2, g2, b2 = hex_to_rgb(to_hex)
    if not r1 or not r2 then
        return text
    end

    local out = {}
    local span = math.max(1, #chars - 1)
    for i, ch in ipairs(chars) do
        local t = (i - 1) / span
        local r = r1 + ((r2 - r1) * t)
        local g = g1 + ((g2 - g1) * t)
        local b = b1 + ((b2 - b1) * t)
        out[#out + 1] = minetest.get_color_escape_sequence(rgb_to_hex(r, g, b))
        out[#out + 1] = ch
    end
    out[#out + 1] = minetest.get_color_escape_sequence("#ffffff")
    return table.concat(out)
end

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

function CC.render_for_player(player_name, raw_message, opts)
    local input = tostring(raw_message or "")
    if input == "" then
        return input, false, nil, input
    end

    local has_use = has_use_priv(player_name)
    local style = get_selected_style(player_name)

    if style then
        if style.kind == "legacy" and not has_color_priv_for_code(player_name, style.code) then
            style = nil
            set_selected_style(player_name, nil)
        elseif (style.kind == "hex" or style.kind == "gradient") and not has_wildcard_color_priv(player_name) then
            style = nil
            set_selected_style(player_name, nil)
        end
    end

    if not has_use and not style then
        return input, false, nil, input
    end

    local C = get_color_lib()
    local needs_legacy_renderer = has_use or (style and style.kind == "legacy")
    if needs_legacy_renderer and (type(C) ~= "table" or type(C.render_bukkit_text) ~= "function") then
        return input, false, "color_lib renderer unavailable", input
    end

    local render_opts = {}
    if type(opts) == "table" then
        for key, value in pairs(opts) do
            render_opts[key] = value
        end
    end
    if render_opts.code_char == nil then
        render_opts.code_char = "&"
    end
    if render_opts.allow_section == nil then
        render_opts.allow_section = true
    end
    if render_opts.trim == nil then
        render_opts.trim = false
    end
    if render_opts.append_white == nil then
        render_opts.append_white = true
    end

    if style then
        local clean = strip_player_color_tokens(C, input)

        if style.kind == "legacy" then
            local rendered, _, err, visible = C.render_bukkit_text(style.code .. clean, render_opts)
            if err or not rendered then
                return input, false, err, visible or input
            end
            return rendered, (rendered ~= input), nil, visible
        end

        if style.kind == "hex" then
            local rendered = minetest.get_color_escape_sequence(style.color)
                .. clean
                .. minetest.get_color_escape_sequence("#ffffff")
            return rendered, (rendered ~= input), nil, clean
        end

        if style.kind == "gradient" then
            local rendered = apply_gradient(clean, style.from, style.to)
            return rendered, (rendered ~= input), nil, clean
        end
    end

    local rendered, _, err, visible = C.render_bukkit_text(input, render_opts)
    if err or not rendered then
        return input, false, err, visible or input
    end
    return rendered, (rendered ~= input), nil, visible
end

minetest.register_chatcommand("chatcolor", {
    params = "<gui|color|&code|#HEX [#HEX]|off>",
    description = "Set your default chat color, or open helper UI with /chatcolor gui.",
    func = function(name, param)
        local raw = trim(param)
        if raw:lower() == "gui" then
            if not has_wildcard_color_priv(name) then
                return false, "You need chatcolor.color.* to use /chatcolor gui."
            end
            open_gui(name, "")
            return true
        end

        local style, err = parse_chatcolor_param(param)
        if not style then
            return false, err
        end

        return apply_style_for_player(name, style)
    end,
})

minetest.register_on_player_receive_fields(function(player, formname, fields)
    if formname ~= GUI_FORMNAME then
        return false
    end
    if not player or not player:is_player() then
        return true
    end

    local name = player:get_player_name()
    local state = gui_inputs[name]
    if type(state) ~= "table" then
        state = sync_gui_inputs_from_style(name)
    end

    if type(fields.cc_hex_single) == "string" then
        state.hex_single = trim(fields.cc_hex_single)
    end
    if type(fields.cc_hex_from) == "string" then
        state.hex_from = trim(fields.cc_hex_from)
    end
    if type(fields.cc_hex_to) == "string" then
        state.hex_to = trim(fields.cc_hex_to)
    end

    if fields.quit or fields.cc_close then
        state.gui_open = false
        state.status = nil
        return true
    end

    for _, code in ipairs(LEGACY_GUI_CODES) do
        if fields["cc_legacy_" .. code] then
            local style = {
                kind = "legacy",
                code = "&" .. code,
                color_name = COLOR_BY_CODE[code],
            }
            local ok, msg = apply_style_for_player(name, style)
            state.preview_style = nil
            if ok then
                open_gui(name, msg)
            else
                open_gui(name, {
                    text = msg,
                    is_error = true,
                    ttl = GUI_ERROR_TTL_SEC,
                })
            end
            return true
        end
    end

    if fields.cc_preview_fields then
        local preview_style, err = preview_style_from_inputs(state)
        if not preview_style then
            open_gui(name, {
                text = err,
                is_error = true,
                ttl = GUI_ERROR_TTL_SEC,
            })
            return true
        end
        state.preview_style = preview_style
        open_gui(name, "Preview updated.")
        return true
    end

    if fields.cc_apply_hex then
        local hex = normalize_hex(state.hex_single)
        if not hex then
            open_gui(name, {
                text = "Invalid HEX. Use format #22EC7A.",
                is_error = true,
                ttl = GUI_ERROR_TTL_SEC,
            })
            return true
        end
        local ok, msg = apply_style_for_player(name, {kind = "hex", color = hex})
        state.preview_style = nil
        if ok then
            open_gui(name, msg)
        else
            open_gui(name, {
                text = msg,
                is_error = true,
                ttl = GUI_ERROR_TTL_SEC,
            })
        end
        return true
    end

    if fields.cc_apply_gradient then
        local from_hex = normalize_hex(state.hex_from)
        local to_hex = normalize_hex(state.hex_to)
        if not from_hex or not to_hex then
            open_gui(name, {
                text = "Invalid gradient. Use both: #22EC7A #0448D1",
                is_error = true,
                ttl = GUI_ERROR_TTL_SEC,
            })
            return true
        end
        local ok, msg = apply_style_for_player(name, {
            kind = "gradient",
            from = from_hex,
            to = to_hex,
        })
        state.preview_style = nil
        if ok then
            open_gui(name, msg)
        else
            open_gui(name, {
                text = msg,
                is_error = true,
                ttl = GUI_ERROR_TTL_SEC,
            })
        end
        return true
    end

    if fields.cc_clear then
        local ok, msg = apply_style_for_player(name, {kind = "none"})
        state.preview_style = nil
        if ok then
            open_gui(name, msg)
        else
            open_gui(name, {
                text = msg,
                is_error = true,
                ttl = GUI_ERROR_TTL_SEC,
            })
        end
        return true
    end

    return true
end)

minetest.register_on_leaveplayer(function(player)
    local name = player and player:get_player_name() or ""
    if name ~= "" then
        selected_styles[name] = nil
        gui_inputs[name] = nil
    end
end)
