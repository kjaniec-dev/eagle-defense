local statemachine = require("src.core.statemachine")

local function recorder(log, name)
  return {
    enter = function(_, params)
      log[#log + 1] = name .. ":enter:" .. tostring(params and params.v)
    end,
    exit = function()
      log[#log + 1] = name .. ":exit"
    end,
    tick = function(_, x)
      log[#log + 1] = name .. ":tick:" .. tostring(x)
    end,
  }
end

describe("core.statemachine", function()
  local log, sm
  before_each(function()
    log = {}
    sm = statemachine.new({
      states = { a = recorder(log, "a"), b = recorder(log, "b") },
      transitions = { a = { b = true } },
    })
  end)

  it("enters the initial state on start", function()
    sm:start("a", { v = 1 })
    assert.are.equal("a", sm.current_name)
    assert.are.same({ "a:enter:1" }, log)
  end)

  it("defers transitions until flush and calls exit then enter", function()
    sm:start("a")
    sm:request("b", { v = 2 })
    assert.are.equal("a", sm.current_name)
    assert.is_true(sm:flush())
    assert.are.equal("b", sm.current_name)
    assert.are.same({ "a:enter:nil", "a:exit", "b:enter:2" }, log)
    assert.is_false(sm:flush())
  end)

  it("rejects transitions that are not whitelisted", function()
    sm:start("a")
    sm:request("b")
    sm:flush()
    assert.has_error(function()
      sm:request("a")
    end)
  end)

  it("rejects unknown states", function()
    assert.has_error(function()
      sm:start("nope")
    end)
    sm:start("a")
    assert.has_error(function()
      sm:request("nope")
    end)
  end)

  it("cannot be started twice", function()
    sm:start("a")
    assert.has_error(function()
      sm:start("a")
    end)
  end)

  it("dispatches callbacks to the current state and ignores missing ones", function()
    sm:start("a")
    sm:dispatch("tick", 5)
    sm:dispatch("draw")
    assert.are.same({ "a:enter:nil", "a:tick:5" }, log)
  end)
end)
