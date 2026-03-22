local CC = rawget(_G, "chatcolor")
if type(CC) ~= "table" then
    CC = {}
    rawset(_G, "chatcolor", CC)
end
if CC._module_loaded then
    return
end
CC._module_loaded = true

local modpath = minetest.get_modpath(minetest.get_current_modname())

dofile(modpath .. "/lib/core.lua")
dofile(modpath .. "/lib/renderer.lua")
dofile(modpath .. "/lib/gui.lua")
dofile(modpath .. "/lib/commands.lua")
