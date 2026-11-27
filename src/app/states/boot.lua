-- Boot state: one-time initialisation, then hands over to the next state.
-- In G1 the next state is the combat test arena.

local M = {}

function M.new(ctx)
  local state = {}

  function state:enter()
    ctx.machine:request("arena")
  end

  return state
end

return M
