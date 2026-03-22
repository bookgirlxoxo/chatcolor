local CC = rawget(_G, "chatcolor")
if type(CC) ~= "table" then
    return
end
if CC._renderer_loaded then
    return
end
CC._renderer_loaded = true

local core = CC._core
if type(core) ~= "table" then
    return
end

local normalize_hex = core.normalize_hex
local get_color_lib = core.get_color_lib
local has_use_priv = core.has_use_priv
local has_wildcard_color_priv = core.has_wildcard_color_priv
local has_color_priv_for_code = core.has_color_priv_for_code
local get_selected_style = core.get_selected_style
local set_selected_style = core.set_selected_style

local PREVIEW_PHRASE = "Hello world! I am John Doe"
core.PREVIEW_PHRASE = PREVIEW_PHRASE

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

local function preview_text_for_style(style)
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
        return "Preview: " .. apply_gradient(PREVIEW_PHRASE, style.from, style.to)
    end

    return "Preview: None"
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

core.apply_gradient = apply_gradient
core.preview_text_for_style = preview_text_for_style

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
