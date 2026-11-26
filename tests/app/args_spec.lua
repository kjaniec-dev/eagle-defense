local args = require("src.app.args")

describe("app.args", function()
  it("parses smoke options", function()
    local o = args.parse({ "--smoke=120", "--smoke-out=/tmp/x.png" })
    assert.are.equal(120, o.smoke)
    assert.are.equal("/tmp/x.png", o.smoke_out)
  end)

  it("parses the window size", function()
    local o = args.parse({ "--window=1366x768" })
    assert.are.equal(1366, o.window_w)
    assert.are.equal(768, o.window_h)
    assert.has_error(function()
      args.parse({ "--window=big" })
    end)
  end)

  it("parses the presentation mode and rejects unknown modes", function()
    assert.are.equal("fit", args.parse({ "--scale-mode=fit" }).scale_mode)
    assert.are.equal("integer", args.parse({ "--scale-mode=integer" }).scale_mode)
    assert.is_nil(args.parse({}).scale_mode)
    assert.has_error(function()
      args.parse({ "--scale-mode=stretch" })
    end)
  end)

  it("defaults to interactive mode", function()
    assert.is_nil(args.parse({}).smoke)
  end)

  it("rejects invalid tick counts", function()
    for _, bad in ipairs({ "--smoke=0", "--smoke=abc", "--smoke=1.5" }) do
      assert.has_error(function()
        args.parse({ bad })
      end)
    end
  end)

  it("produces deterministic scripted smoke input", function()
    assert.are.same(args.smoke_frame(10), args.smoke_frame(10))
    assert.are.same({ "up", "left" }, { args.smoke_frame(1)[1].dir, args.smoke_frame(1)[2].dir })
    assert.are.same({ "right", "up" }, { args.smoke_frame(61)[1].dir, args.smoke_frame(61)[2].dir })
    -- one press per scripted shot, fire held for 3 ticks
    assert.are.same(
      { true, true },
      { args.smoke_frame(1)[1].fire_pressed, args.smoke_frame(3)[1].fire }
    )
    assert.are.same(
      { false, false },
      { args.smoke_frame(2)[1].fire_pressed, args.smoke_frame(4)[1].fire }
    )
  end)
end)
