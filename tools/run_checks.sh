#!/usr/bin/env bash
# Full offline check: Luau compile, headless world/traffic/integration tests, geometric
# bounds verification, then build + validate the .rbxlx.
#   LUAU_BIN=/path/to/luau-dir tools/run_checks.sh
# (luau / luau-compile from https://github.com/luau-lang/luau/releases)
set -euo pipefail
cd "$(dirname "$0")/.."
BIN="${LUAU_BIN:-.}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "== compile"
find src -name '*.lua' | sort | while read -r f; do "$BIN/luau-compile" --text "$f" > /dev/null && echo "ok  $f"; done

echo "== world geometry (bounds, bypass, reachability)"
python3 tools/make_harness.py tools/tests/world_dump.lua "$TMP/world.lua"
"$BIN/luau" "$TMP/world.lua" > "$TMP/world.txt"
python3 tools/verify_world.py "$TMP/world.txt" | grep -v '^OK' || true

echo "== traffic simulation"
python3 tools/make_harness.py tools/tests/traffic_sim.lua "$TMP/traffic.lua"
"$BIN/luau" "$TMP/traffic.lua" | tee "$TMP/traffic.txt" | grep -v '^OK'
grep -q "ALL TRAFFIC CHECKS PASSED" "$TMP/traffic.txt"

echo "== server + client integration"
python3 tools/make_harness.py tools/tests/integration.lua "$TMP/int.lua"
"$BIN/luau" "$TMP/int.lua" | tee "$TMP/int.txt" | grep -v '^OK'
grep -q "ALL INTEGRATION CHECKS PASSED" "$TMP/int.txt"

python3 tools/verify_world.py "$TMP/world.txt" > /dev/null

echo "== crossing playability probe (informational)"
python3 tools/make_harness.py tools/tests/crossing_agent.lua "$TMP/cross.lua"
"$BIN/luau" "$TMP/cross.lua"

echo "== build + validate rbxlx"
python3 tools/build_rbxlx.py builds/Survive_India_Tycoon_V26_1_RAGS_MUSIC.rbxlx
echo "ALL CHECKS PASSED"
