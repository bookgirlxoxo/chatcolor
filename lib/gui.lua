local CC = rawget(_G, "chatcolor")
if type(CC) ~= "table" then
    return
end
if CC._gui_loaded then
    return
end
CC._gui_loaded = true

local core = CC._core
if type(core) ~= "table" then
    return
end

local GUI_FORMNAME = "chatcolor:gui"
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

core.GUI_FORMNAME = GUI_FORMNAME
core.GUI_ERROR_TTL_SEC = GUI_ERROR_TTL_SEC
core.LEGACY_GUI_CODES = LEGACY_GUI_CODES

local trim = core.trim
local normalize_hex = core.normalize_hex
local pretty_color_name = core.pretty_color_name
local formspec_escape = core.formspec_escape
local hypertext_escape = core.hypertext_escape
local get_selected_style = core.get_selected_style
local style_summary = core.style_summary
local apply_style_for_player = core.apply_style_for_player
local preview_text_for_style = core.preview_text_for_style
local COLOR_BY_CODE = core.COLOR_BY_CODE
local gui_inputs = core.gui_inputs

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
    local preview_line = "Preview: None"
    if type(preview_text_for_style) == "function" then
        preview_line = preview_text_for_style(state.preview_style or current)
    end

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

local open_gui
open_gui = function(player_name, status)
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

CC.open_gui = open_gui

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
    core.clear_player_state(name)
end)
