#!/usr/bin/env bash
# Installs the pinned local toolchain for THIS platform into
#   .rocks/<platform>/  (busted, luacheck and their C modules)
#   .tools/<platform>/  (StyLua)
# where <platform> comes from tools/platform.sh (e.g. darwin-arm64,
# linux-arm64). A macOS host and a Linux container can therefore share one
# checkout without overwriting each other's binaries.
# Requires: luarocks, a Lua 5.1/LuaJIT dev setup, curl, unzip.
#
#   tools/bootstrap.sh                install (idempotent)
#   tools/bootstrap.sh --print-plan   print the resolved platform, paths and
#                                     pinned StyLua asset/checksum; install nothing
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLATFORM="$("$ROOT/tools/platform.sh")"
ROCKS="$ROOT/.rocks/$PLATFORM"
TOOLS="$ROOT/.tools/$PLATFORM"

BUSTED_VERSION="2.3.0-1"
LUACHECK_VERSION="1.2.0-1"
STYLUA_VERSION="2.6.0"

die() { echo "bootstrap: $*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "missing required tool: $1"; }

# --- StyLua release asset for this platform (SHA-256 pinned) ----------------
case "$PLATFORM" in
  linux-x86_64)  asset="stylua-linux-x86_64.zip";  sha="a485f72bbfa22e4642e77a84b5edc2611a5cab7477b34e2e709dd8f78e919895" ;;
  linux-arm64)   asset="stylua-linux-aarch64.zip"; sha="8e67539e5fdf7a81cd03cf592b0df18d3bb96ee17a5ea5d9bf67b86387b903b0" ;;
  darwin-arm64)  asset="stylua-macos-aarch64.zip"; sha="dab9b66d340ca5ffc8225211f1dcf89b84783e09b8cbec8c518497eba81f3c42" ;;
  darwin-x86_64) asset="stylua-macos-x86_64.zip";  sha="90779aa873837b2dff8eb3361bd27950303914c24265a59cae0a0d0629d71585" ;;
  *) die "unsupported platform for StyLua: $PLATFORM" ;;
esac

# --- legacy flat layout (before per-platform directories) ------------------
# It is never used any more. It is NOT deleted automatically: in a shared
# checkout it may belong to another machine.
legacy=()
for p in .rocks/bin .rocks/lib .rocks/share .tools/stylua; do
  [[ -e "$ROOT/$p" ]] && legacy+=("$p")
done
if [[ ${#legacy[@]} -gt 0 ]]; then
  echo "bootstrap: NOTE: legacy unpartitioned toolchain found (no longer used): ${legacy[*]}" >&2
  echo "bootstrap: NOTE: remove it when convenient: (cd \"$ROOT\" && rm -rf ${legacy[*]})" >&2
fi

if [[ "${1:-}" == "--print-plan" ]]; then
  echo "platform=$PLATFORM"
  echo "rocks=$ROCKS"
  echo "tools=$TOOLS"
  echo "busted=$BUSTED_VERSION"
  echo "luacheck=$LUACHECK_VERSION"
  echo "stylua=$STYLUA_VERSION"
  echo "stylua_asset=$asset"
  echo "stylua_sha256=$sha"
  exit 0
fi
[[ $# -eq 0 ]] || die "unknown argument: $1"

echo "bootstrap: platform $PLATFORM -> .rocks/$PLATFORM, .tools/$PLATFORM"

need luarocks
need curl
need unzip

LR=(luarocks --lua-version 5.1 --tree "$ROCKS")
if [[ "$PLATFORM" == darwin-* ]] && command -v brew >/dev/null 2>&1; then
  # Homebrew's luarocks defaults to Lua 5.4; point it at LuaJIT's 5.1 headers.
  LR+=(--lua-dir "$(brew --prefix luajit)")
fi

install_rock() {
  local name="$1" version="$2"
  if [[ -d "$ROCKS/lib/luarocks/rocks-5.1/$name/$version" ]]; then
    echo "bootstrap: $name $version already installed"
  else
    "${LR[@]}" install "$name" "$version"
  fi
}

install_rock busted "$BUSTED_VERSION"
install_rock luacheck "$LUACHECK_VERSION"

# --- StyLua (release binary, SHA-256 pinned above) -------------------------
if [[ -x "$TOOLS/stylua" ]] && "$TOOLS/stylua" --version | grep -q "$STYLUA_VERSION"; then
  echo "bootstrap: stylua $STYLUA_VERSION already installed"
else
  mkdir -p "$TOOLS"
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  curl -fsSL -o "$tmp/$asset" \
    "https://github.com/JohnnyMorganz/StyLua/releases/download/v$STYLUA_VERSION/$asset"
  if command -v sha256sum >/dev/null 2>&1; then
    actual="$(sha256sum "$tmp/$asset" | cut -d' ' -f1)"
  else
    actual="$(shasum -a 256 "$tmp/$asset" | cut -d' ' -f1)"
  fi
  [[ "$actual" == "$sha" ]] || die "StyLua checksum mismatch: $actual"
  unzip -q -o "$tmp/$asset" -d "$TOOLS"
  chmod +x "$TOOLS/stylua"
fi

echo "bootstrap: done"
export LUA_PATH="$ROCKS/share/lua/5.1/?.lua;$ROCKS/share/lua/5.1/?/init.lua;;"
export LUA_CPATH="$ROCKS/lib/lua/5.1/?.so;;"
"$ROCKS/bin/busted" --lua=luajit --version
"$ROCKS/bin/luacheck" --version | head -1
"$TOOLS/stylua" --version
