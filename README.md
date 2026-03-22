# chatcolor

Chat color helper for Luanti/Minetest chat with:
- Minecraft/Bukkit legacy codes (`&0`..`&f`, `&r`)
- Default per-player chat color styles
- HEX and gradient defaults
- Permission-based color access

This mod depends on `color_lib`.

## Commands

- `/chatcolor <color|&code|#HEX [#HEX]|off>`
- `/chatcolor gui`

Examples:
- `/chatcolor &f`
- `/chatcolor white`
- `/chatcolor purple` (maps to `&5`)
- `/chatcolor #22EC7A`
- `/chatcolor #22EC7A #0448D1`
- `/chatcolor off`

## Privileges

- `chatcolor.use`
  - Allows users to type legacy Bukkit color tokens directly in chat messages.
- `chatcolor.color.*`
  - Allows all `/chatcolor` colors, HEX, gradients, and `/chatcolor gui`.
- `chatcolor.color.<name>`
  - Allows specific legacy default colors (for example `chatcolor.color.white`, `chatcolor.color.purple`).

Canonical color names:
- `black`, `dark_blue`, `dark_green`, `dark_aqua`, `dark_red`, `dark_purple`, `gold`, `gray`, `dark_gray`, `blue`, `green`, `aqua`, `red`, `light_purple`, `yellow`, `white`, `reset`

## GUI

`/chatcolor gui` opens a helper UI for legacy, HEX, and gradient selection.