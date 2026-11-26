-- Boot state: one-time initialisation, then hands over to the next state.
-- In G0 the next state is the debug sandbox.

local M = {}

function M.new(ctx)
  local state = {}

  function state:enter()
    ctx.machine:request("sandbox")
  end

  return state
end

return M
