#!/usr/bin/env bash
# Prints the platform key used to separate native toolchains:
#   .rocks/<key>/  (busted, luacheck and their C modules)
#   .tools/<key>/  (StyLua)
# so that a macOS host and a Linux container can share one checkout
# without overwriting each other's binaries.
#
# Usage: tools/platform.sh [OS ARCH]
#   With no arguments it uses `uname -s` and `uname -m`. The arguments
#   exist so the normalization can be tested.
#
# Keys: <os>-<arch>, os in {linux, darwin, ...} (lowercase uname -s),
# arch normalized to x86_64 or arm64 (aarch64 and arm64 are the same CPU
# architecture but uname reports them differently on Linux and macOS).
set -euo pipefail

os="${1:-$(uname -s)}"
arch="${2:-$(uname -m)}"

os="$(printf '%s' "$os" | tr '[:upper:]' '[:lower:]')"
case "$arch" in
  x86_64 | amd64) arch="x86_64" ;;
  aarch64 | arm64) arch="arm64" ;;
  *) arch="$(printf '%s' "$arch" | tr '[:upper:]' '[:lower:]')" ;;
esac

if [[ -z "$os" || -z "$arch" || "$os$arch" == *[!a-z0-9_]* ]]; then
  echo "platform: cannot derive a platform key from '$os' '$arch'" >&2
  exit 1
fi
printf '%s-%s\n' "$os" "$arch"
