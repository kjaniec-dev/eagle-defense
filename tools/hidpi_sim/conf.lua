-- Uses the app's own conf.lua, so the window setup (including highdpi) is
-- exactly the game's. See tools/hidpi_sim/main.lua.
local app_root = assert(os.getenv("EAGLE_APP_ROOT"), "hidpi_sim: EAGLE_APP_ROOT is not set")
dofile(app_root .. "/conf.lua")
