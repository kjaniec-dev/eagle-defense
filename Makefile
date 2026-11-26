# Eagle Defense — developer and CI entry points.
# `make check` is the gate for every PR.

# Native toolchains are kept per platform (tools/platform.sh), so a macOS
# host and a Linux container can share this checkout without overwriting
# each other's binaries: .rocks/<platform>/ and .tools/<platform>/.
PLATFORM   := $(shell $(CURDIR)/tools/platform.sh)
ifeq ($(PLATFORM),)
$(error tools/platform.sh could not determine the platform key)
endif
ROCKS      := $(CURDIR)/.rocks/$(PLATFORM)
TOOLS      := $(CURDIR)/.tools/$(PLATFORM)
BUSTED     := $(ROCKS)/bin/busted
LUACHECK   := $(ROCKS)/bin/luacheck
STYLUA     := $(TOOLS)/stylua
LUAJIT     ?= luajit
LOVE       ?= love
SMOKE_TICKS ?= 120
BUILD      := $(CURDIR)/build

export LUA_PATH  := ./?.lua;./?/init.lua;$(ROCKS)/share/lua/5.1/?.lua;$(ROCKS)/share/lua/5.1/?/init.lua;;
export LUA_CPATH := $(ROCKS)/lib/lua/5.1/?.so;;

LUA_SOURCES := main.lua conf.lua src config tests tools assets/manifest.lua

.PHONY: help bootstrap toolchain require-toolchain fmt fmt-check lint test validate smoke hidpi-sim love \
	love-dev run check evidence evidence-dev mockups busted-version luacheck-version stylua-version clean

help:
	@echo "bootstrap  install pinned toolchain for this platform (.rocks/$(PLATFORM)/, .tools/$(PLATFORM)/)"
	@echo "toolchain  print the resolved platform and toolchain paths"
	@echo "fmt        format Lua sources with StyLua"
	@echo "fmt-check  verify formatting"
	@echo "lint       luacheck + shellcheck"
	@echo "test       busted unit/scenario tests (LuaJIT)"
	@echo "validate   architecture boundaries + asset manifest"
	@echo "smoke      headless LÖVE run (Xvfb) with PNG capture"
	@echo "hidpi-sim  SIMULATED HiDPI regression harness (integer + fit, DPI 1/1.25/1.5/2)"
	@echo "love       build dist/eagle-defense.love from the committed HEAD (+ .sha256, .commit)"
	@echo "love-dev   build dist/eagle-defense.love from the working tree (marked -dirty)"
	@echo "check      fmt-check lint test validate smoke hidpi-sim"
	@echo "evidence   FINAL review evidence package (requires a clean tree; fails closed)"
	@echo "evidence-dev  development snapshot package (dirty tree allowed, marked DEV)"
	@echo "mockups    G1 art-direction concept mockups -> docs/art/mockups (CPU only, deterministic)"

bootstrap:
	./tools/bootstrap.sh

toolchain:
	@echo "platform=$(PLATFORM)"
	@echo "rocks=$(ROCKS)"
	@echo "tools=$(TOOLS)"
	@echo "lua_path=$(LUA_PATH)"
	@echo "lua_cpath=$(LUA_CPATH)"

# Fails with a clear message instead of "No such file" when this platform
# has not been bootstrapped yet (e.g. first run in a new container).
require-toolchain:
	@for t in "$(BUSTED)" "$(LUACHECK)" "$(STYLUA)"; do \
	  if [ ! -x "$$t" ]; then \
	    echo "toolchain for $(PLATFORM) is not installed (missing $$t); run: make bootstrap" >&2; \
	    exit 1; \
	  fi; \
	done

fmt: require-toolchain
	$(STYLUA) $(LUA_SOURCES)

fmt-check: require-toolchain
	$(STYLUA) --check $(LUA_SOURCES)

lint: require-toolchain
	$(LUACHECK) $(LUA_SOURCES)
	@if command -v shellcheck >/dev/null 2>&1; then shellcheck tools/*.sh tools/lib/*.sh && echo "shellcheck: OK"; \
	else echo "shellcheck: not installed (skipped)"; fi

test: require-toolchain
	$(BUSTED) --lua=$(LUAJIT) --output=utfTerminal

validate:
	$(LUAJIT) tools/check_boundaries.lua
	$(LUAJIT) tools/check_assets.lua
	$(LUAJIT) tools/check_dpi.lua

smoke:
	./tools/smoke.sh $(SMOKE_TICKS) $(BUILD)/smoke.png

hidpi-sim:
	./tools/hidpi_sim.sh $(BUILD)/hidpi-sim

love:
	./tools/build_love.sh --commit

love-dev:
	./tools/build_love.sh --worktree

run:
	$(LOVE) .

check: fmt-check lint test validate smoke hidpi-sim

evidence:
	./tools/evidence.sh

evidence-dev:
	./tools/evidence.sh --dev

# G1 visual direction spike: concept art only (never shipped). Headless,
# CPU-only LÖVE run; output PNGs are byte-deterministic.
mockups:
	@mkdir -p docs/art/mockups
	$(LOVE) tools/mockup docs/art/mockups

busted-version: require-toolchain
	@$(BUSTED) --lua=$(LUAJIT) --version

luacheck-version: require-toolchain
	@$(LUACHECK) --version

stylua-version: require-toolchain
	@$(STYLUA) --version

clean:
	rm -rf $(BUILD) dist evidence
