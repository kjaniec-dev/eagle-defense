-- Eagle Defense entry point. All wiring lives in src/app/app.lua.
local App = require("src.app.app")

love.run = App.run
