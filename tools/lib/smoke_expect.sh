# shellcheck shell=bash
# Expected outcome of the scripted 120-tick smoke run in the G1 arena
# (src/app/args.lua smoke_frame): player positions in simulation units and
# the sim state hash. Sourced by tools/smoke.sh and tools/hidpi_sim.sh;
# tests/app/arena_spec.lua checks that the pure simulation gives exactly
# this, so the real app must agree. A tuning or arena change updates it
# together with the golden replays.
# shellcheck disable=SC2034 # used by the sourcing scripts
SMOKE_EXPECT_120="p1=1408,2688 p2=1664,2652 hash=581f15d4"
