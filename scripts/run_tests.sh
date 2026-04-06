#!/usr/bin/env bash
set -euo pipefail

for file in tests/*_spec.lua; do
	nvim --headless -u NONE -c "luafile ${file}" -c "qa"
done
