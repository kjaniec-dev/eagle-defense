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

  it("parses --arena and refuses unknown arenas", function()
    assert.are.equal("g1_arena", args.parse({ "--arena=g1_arena" }).arena)
    assert.are.equal("g2_terrain", args.parse({ "--arena=g2_terrain" }).arena)
    assert.is_nil(args.parse({}).arena)
    assert.are.equal("g2_terrain", args.DEFAULT_ARENA)
    assert.has_error(function()
      args.parse({ "--arena=campaign_01" })
    end)
  end)

  it("has one smoke script per arena and requires the arena", function()
    assert.has_error(function()
      args.smoke_frame(1)
    end)
    -- terrain arena: P1 up 30 ticks, released, right 30 ticks, released;
    -- P2 never moves and presses fire every 20 ticks from tick 1
    local f = args.smoke_frame(1, "g2_terrain")
    assert.are.same({ "up", nil, true }, { f[1].dir, f[2].dir, f[2].fire_pressed })
    assert.is_nil(args.smoke_frame(31, "g2_terrain")[1].dir)
    assert.are.equal("right", args.smoke_frame(61, "g2_terrain")[1].dir)
    assert.is_nil(args.smoke_frame(91, "g2_terrain")[1].dir)
    assert.is_true(args.smoke_frame(101, "g2_terrain")[2].fire_pressed)
    assert.is_false(args.smoke_frame(102, "g2_terrain")[2].fire_pressed)
  end)

  it("produces deterministic scripted smoke input", function()
    assert.are.same(args.smoke_frame(10, "g1_arena"), args.smoke_frame(10, "g1_arena"))
    assert.are.same(
      { "up", "left" },
      { args.smoke_frame(1, "g1_arena")[1].dir, args.smoke_frame(1, "g1_arena")[2].dir }
    )
    assert.are.same(
      { "right", "up" },
      { args.smoke_frame(61, "g1_arena")[1].dir, args.smoke_frame(61, "g1_arena")[2].dir }
    )
    -- one press per scripted shot, fire held for 3 ticks
    assert.are.same(
      { true, true },
      { args.smoke_frame(1, "g1_arena")[1].fire_pressed, args.smoke_frame(3, "g1_arena")[1].fire }
    )
    assert.are.same(
      { false, false },
      { args.smoke_frame(2, "g1_arena")[1].fire_pressed, args.smoke_frame(4, "g1_arena")[1].fire }
    )
  end)
end)
