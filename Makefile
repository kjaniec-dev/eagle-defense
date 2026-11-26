# Eagle Defense — developer and CI entry points.
# `make check` is the gate for every PR.

ROCKS      := $(CURDIR)/.rocks
TOOLS      := $(CURDIR)/.tools
BUSTED     := $(ROCKS)/bin/busted
LUACHECK   := $(ROCKS)/bin/luacheck
STYLUA     := $(TOOLS)/stylua
ACTIONLINT := $(TOOLS)/actionlint
LUAJIT     ?= luajit
LOVE       ?= love
SMOKE_TICKS ?= 120
BUILD      := $(CURDIR)/build

export LUA_PATH  := ./?.lua;./?/init.lua;$(ROCKS)/share/lua/5.1/?.lua;$(ROCKS)/share/lua/5.1/?/init.lua;;
export LUA_CPATH := $(ROCKS)/lib/lua/5.1/?.so;;

LUA_SOURCES := main.lua conf.lua src config tests tools assets/manifest.lua

.PHONY: help bootstrap fmt fmt-check lint test validate smoke love run check evidence clean

help:
	@echo "bootstrap  install pinned toolchain (.rocks/, .tools/)"
	@echo "fmt        format Lua sources with StyLua"
	@echo "fmt-check  verify formatting"
	@echo "lint       luacheck + actionlint"
	@echo "test       busted unit/scenario tests (LuaJIT)"
	@echo "validate   architecture boundaries + asset manifest"
	@echo "smoke      headless LÖVE run (Xvfb) with PNG capture"
	@echo "love       build dist/eagle-defense.love (+ SHA-256)"
	@echo "check      fmt-check lint test validate smoke"
	@echo "evidence   build the review evidence package"

bootstrap:
	./tools/bootstrap.sh

fmt:
	$(STYLUA) $(LUA_SOURCES)

fmt-check:
	$(STYLUA) --check $(LUA_SOURCES)

lint:
	$(LUACHECK) $(LUA_SOURCES)
	$(ACTIONLINT) -shellcheck=
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
	./tools/build_love.sh

run:
	$(LOVE) .

check: fmt-check lint test validate smoke

evidence:
	./tools/evidence.sh

clean:
	rm -rf $(BUILD) dist evidence
