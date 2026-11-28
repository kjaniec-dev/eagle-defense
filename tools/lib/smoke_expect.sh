# shellcheck shell=bash
# Expected outcomes of the scripted 120-tick smoke runs (src/app/args.lua
# smoke_frame), one per arena: player positions in simulation units and the
# sim state hash. Sourced by tools/smoke.sh and tools/hidpi_sim.sh;
# tests/app/arena_spec.lua checks that the pure simulation gives exactly
# these, so the real app must agree. A tuning or arena change updates them
# together with the golden replays.
# shellcheck disable=SC2034 # used by the sourcing scripts
# G1 arena (--arena=g1_arena): unchanged since the G1 tuning approval.
SMOKE_EXPECT_120="p1=1408,2688 p2=1664,2652 hash=581f15d4"
# G2 terrain arena (--arena=g2_terrain): P1 slides on ice into the water
# column, P2 shoots its brick wall point-blank. Updated for the owner brick
# tuning (4 x 2, 2026-11-28; was hash=4b7aaef1 at 2 x 1).
SMOKE_EXPECT_G2_120="p1=512,2688 p2=2304,3072 hash=ac2a42a0"
