local CC = rawget(_G, "chatcolor")
if type(CC) ~= "table" then
    return
end
if CC._commands_loaded then
    return
end
CC._commands_loaded = true

local core = CC._core
if type(core) ~= "table" then
    return
end

local trim = core.trim
local parse_chatcolor_param = core.parse_chatcolor_param
local apply_style_for_player = core.apply_style_for_player
local has_wildcard_color_priv = core.has_wildcard_color_priv

minetest.register_chatcommand("chatcolor", {
    params = "<gui|color|&code|#HEX [#HEX]|off>",
    description = "Set your default chat color, or open helper UI with /chatcolor gui.",
    func = function(name, param)
        local raw = trim(param)
        if raw:lower() == "gui" then
            if not has_wildcard_color_priv(name) then
                return false, "You need chatcolor.color.* to use /chatcolor gui."
            end
            if type(CC.open_gui) == "function" then
                CC.open_gui(name, "")
                return true
            end
            return false, "ChatColor GUI unavailable."
        end

        local style, err = parse_chatcolor_param(param)
        if not style then
            return false, err
        end

        return apply_style_for_player(name, style)
    end,
})
