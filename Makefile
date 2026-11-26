# Eagle Defense — developer and CI entry points.
# `make check` is the gate for every PR.

ROCKS      := $(CURDIR)/.rocks
TOOLS      := $(CURDIR)/.tools
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

.PHONY: help bootstrap fmt fmt-check lint test validate smoke love love-dev run check evidence \
	evidence-dev busted-version clean

help:
	@echo "bootstrap  install pinned toolchain (.rocks/, .tools/)"
	@echo "fmt        format Lua sources with StyLua"
	@echo "fmt-check  verify formatting"
	@echo "lint       luacheck + shellcheck"
	@echo "test       busted unit/scenario tests (LuaJIT)"
	@echo "validate   architecture boundaries + asset manifest"
	@echo "smoke      headless LÖVE run (Xvfb) with PNG capture"
	@echo "love       build dist/eagle-defense.love from the committed HEAD (+ .sha256, .commit)"
	@echo "love-dev   build dist/eagle-defense.love from the working tree (marked -dirty)"
	@echo "check      fmt-check lint test validate smoke"
	@echo "evidence   FINAL review evidence package (requires a clean tree; fails closed)"
	@echo "evidence-dev  development snapshot package (dirty tree allowed, marked DEV)"

bootstrap:
	./tools/bootstrap.sh

fmt:
	$(STYLUA) $(LUA_SOURCES)

fmt-check:
	$(STYLUA) --check $(LUA_SOURCES)

lint:
	$(LUACHECK) $(LUA_SOURCES)
	@if command -v shellcheck >/dev/null 2>&1; then shellcheck tools/*.sh && echo "shellcheck: OK"; \
	else echo "shellcheck: not installed (skipped)"; fi

test:
	$(BUSTED) --lua=$(LUAJIT) --output=utfTerminal

validate:
	$(LUAJIT) tools/check_boundaries.lua
	$(LUAJIT) tools/check_assets.lua

smoke:
	./tools/smoke.sh $(SMOKE_TICKS) $(BUILD)/smoke.png

love:
	./tools/build_love.sh --commit

love-dev:
	./tools/build_love.sh --worktree

run:
	$(LOVE) .

check: fmt-check lint test validate smoke

evidence:
	./tools/evidence.sh

evidence-dev:
	./tools/evidence.sh --dev

busted-version:
	@$(BUSTED) --lua=$(LUAJIT) --version

clean:
	rm -rf $(BUILD) dist evidence
