#!/usr/bin/env bash
# Installs the pinned local toolchain into .rocks/ (busted, luacheck) and
# .tools/ (StyLua). Requires: luarocks, a Lua 5.1/LuaJIT dev setup, curl, unzip.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROCKS="$ROOT/.rocks"
TOOLS="$ROOT/.tools"

BUSTED_VERSION="2.3.0-1"
LUACHECK_VERSION="1.2.0-1"
STYLUA_VERSION="2.6.0"

die() { echo "bootstrap: $*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "missing required tool: $1"; }

need luarocks
need curl
need unzip

LR=(luarocks --lua-version 5.1 --tree "$ROCKS")
if [[ "$(uname -s)" == "Darwin" ]] && command -v brew >/dev/null 2>&1; then
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

# --- StyLua (release binary, SHA-256 pinned) -------------------------------
os="$(uname -s)"; arch="$(uname -m)"
case "$os-$arch" in
  Linux-x86_64)  asset="stylua-linux-x86_64.zip";  sha="a485f72bbfa22e4642e77a84b5edc2611a5cab7477b34e2e709dd8f78e919895" ;;
  Linux-aarch64|Linux-arm64) asset="stylua-linux-aarch64.zip"; sha="8e67539e5fdf7a81cd03cf592b0df18d3bb96ee17a5ea5d9bf67b86387b903b0" ;;
  Darwin-arm64)  asset="stylua-macos-aarch64.zip"; sha="dab9b66d340ca5ffc8225211f1dcf89b84783e09b8cbec8c518497eba81f3c42" ;;
  Darwin-x86_64) asset="stylua-macos-x86_64.zip";  sha="90779aa873837b2dff8eb3361bd27950303914c24265a59cae0a0d0629d71585" ;;
  *) die "unsupported platform for StyLua: $os-$arch" ;;
esac

if [[ -x "$TOOLS/stylua" ]] && "$TOOLS/stylua" --version
"$TOOLS/actionlint" -version | head -1 | grep -q "$STYLUA_VERSION"; then
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

# --- actionlint (workflow static analysis, SHA-256 pinned) -----------------
ACTIONLINT_VERSION="1.7.12"
case "$os-$arch" in
  Linux-x86_64)  al_asset="actionlint_${ACTIONLINT_VERSION}_linux_amd64.tar.gz";  al_sha="8aca8db96f1b94770f1b0d72b6dddcb1ebb8123cb3712530b08cc387b349a3d8" ;;
  Linux-aarch64|Linux-arm64) al_asset="actionlint_${ACTIONLINT_VERSION}_linux_arm64.tar.gz"; al_sha="325e971b6ba9bfa504672e29be93c24981eeb1c07576d730e9f7c8805afff0c6" ;;
  Darwin-arm64)  al_asset="actionlint_${ACTIONLINT_VERSION}_darwin_arm64.tar.gz"; al_sha="aba9ced2dee8d27fecca3dc7feb1a7f9a52caefa1eb46f3271ea66b6e0e6953f" ;;
  Darwin-x86_64) al_asset="actionlint_${ACTIONLINT_VERSION}_darwin_amd64.tar.gz"; al_sha="5b44c3bc2255115c9b69e30efc0fecdf498fdb63c5d58e17084fd5f16324c644" ;;
esac

if [[ -x "$TOOLS/actionlint" ]] && "$TOOLS/actionlint" -version | head -1 | grep -q "$ACTIONLINT_VERSION"; then
  echo "bootstrap: actionlint $ACTIONLINT_VERSION already installed"
else
  tmp2="$(mktemp -d)"
  curl -fsSL -o "$tmp2/$al_asset" \
    "https://github.com/rhysd/actionlint/releases/download/v$ACTIONLINT_VERSION/$al_asset"
  if command -v sha256sum >/dev/null 2>&1; then
    actual="$(sha256sum "$tmp2/$al_asset" | cut -d' ' -f1)"
  else
    actual="$(shasum -a 256 "$tmp2/$al_asset" | cut -d' ' -f1)"
  fi
  [[ "$actual" == "$al_sha" ]] || die "actionlint checksum mismatch: $actual"
  tar -xzf "$tmp2/$al_asset" -C "$TOOLS" actionlint
  rm -rf "$tmp2"
fi

echo "bootstrap: done"
export LUA_PATH="$ROCKS/share/lua/5.1/?.lua;$ROCKS/share/lua/5.1/?/init.lua;;"
export LUA_CPATH="$ROCKS/lib/lua/5.1/?.so;;"
"$ROCKS/bin/busted" --lua=luajit --version
"$ROCKS/bin/luacheck" --version | head -1
"$TOOLS/stylua" --version
"$TOOLS/actionlint" -version | head -1
