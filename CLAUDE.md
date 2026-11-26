@AGENTS.md

# Claude-specific notes

## Model policy for subagents (owner preference)
- **Default:** Opus for architecture, gameplay simulation, reviews and anything touching invariants.
- **Fable 5.2:** shader work (GLSL post-processing, lighting, bloom, CRT) and shader debugging.
- **Sonnet:** acceptable for bounded, low-risk work such as research summaries, mechanical refactors, doc formatting, level-data validation scripts and test-fixture boilerplate.
- When delegating, give the subagent the relevant doc sections and module boundaries, and verify its output yourself before reporting.

## Environment
- In the sandbox, LÖVE runs headless with `xvfb-run -a love . --smoke=N` and `SDL_AUDIODRIVER=dummy`. This is software GL (llvmpipe) and counts only as sandbox evidence, not native evidence.
- Communicate with the owner in Polish. Repo docs, code and commits are in English.
