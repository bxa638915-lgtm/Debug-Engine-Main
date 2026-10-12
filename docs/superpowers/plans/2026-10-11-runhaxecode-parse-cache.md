# runHaxeCode Parse Cache Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task, or superpowers:subagent-driven-development if the user selects subagent execution. Track steps with checkbox syntax.

**Goal:** Avoid reparsing identical Lua-to-HScript snippets while preserving one execution and the same interpreter effects on every call.

**Architecture:** Add a bounded, per-HScript-instance cache used only by executeString, the runtime entry point used by Psych runHaxeCode. Cache successful ASTs by exact source text, keep execution in the same interpreter, and expose per-instance hit/miss counters for the F8 diagnostic plan.

**Tech Stack:** Haxe, hscript-improved, existing DBE Lua/HScript bridge.

**Spec:** docs/superpowers/specs/2026-10-11-d3r-script-performance-design.md

## Global Constraints

- Cache is limited to 64 source strings per HScript instance.
- Cache is cleared on reload and destroy.
- Parse errors retain the current file/line error context and never enter the cache.
- No Lua, chart, event, character, shader, or other mod file changes.
- Do not modify makeGraphic or its scale/frame semantics.
- No automated test files are added or run for this task; validation uses the Windows Release build and manual gameplay comparison.
- Do not commit; local DBE development instructions prohibit commits unless explicitly requested.

## Review Focus

- Repeated exact source must hit the cache but still execute effects every call; inspect executeString flow and verify during the D3R Release smoke run.
- Different source strings, including code interpolated with different camera names, must have separate entries; inspect the exact string key and exercise both camera snippets in the smoke run.
- Invalid HScript must remain uncached and continue reporting origin/line; inspect the parse-error branch and confirm no regression in the existing error path.
- More than 64 unique snippets must not grow the cache; inspect FIFO eviction and counter behavior after overflow.
- Reload/destroy must release all cached AST references and reset counters; inspect the lifecycle paths and verify a new PlayState starts with empty counters.

---

### Task 1: Confirm AST reuse is safe in the checked-out interpreter

**Files:**
- Read: source/funkin/backend/scripting/HScript.hx:71-81, 176-181, 184-220, 270-290
- Read: .haxelib/hscript-improved/git/hscript/Interp.hx:623-660, 1131-1193
- Read: .haxelib/hscript-improved/git/hscript/Expr.hx:197-220

**Interfaces:**
- Consumes: current HScript.executeString(source:String):Dynamic and Interp.execute(expr:Expr):Dynamic.
- Produces: a documented go/no-go decision on reusing a successfully parsed Expr across calls to the same Interp.

- [ ] Inspect Expr and Interp.execute for writes to expression nodes or nested arrays during execution. Search assignments to AST fields; distinguish reads and interpreter-state changes from mutations of the Expr tree.
- [ ] Confirm execution state is reset as expected at the start of each Interp.execute call and parser error origin/line are stored on Expr.
- [ ] If execution mutates cached AST nodes in a way that changes later results, stop this plan before Task 2 and report the incompatibility instead of enabling a semantically unsafe cache.

### Task 2: Add the bounded runtime-expression cache

**Files:**
- Modify: source/funkin/backend/scripting/HScript.hx: imports, dynamic execution state, executeString, reload, destroy

**Interfaces:**
- Consumes: executeString(source:String):Dynamic and the AST-reuse decision from Task 1.
- Produces: public read-only Int counters runHaxeCodeCacheHits and runHaxeCodeCacheMisses, plus a maximum of 64 cached valid source strings per HScript instance.

- [ ] Add a StringMap<Expr>, an insertion-order Array<String>, a private inline capacity of 64, and public read-only hit/miss counters. Keep all state on the HScript instance; do not create a static/global cache.
- [ ] Update executeString to preserve null/empty handling. For non-empty input, look up the exact source; on a hit set code and expr to the current source and cached AST, then call interp.execute(expr) as today. On a miss, call loadFromString(source), increment the miss count, and cache only a non-null Expr.
- [ ] When inserting a 65th distinct valid source, remove the oldest key from both the order Array and StringMap before insertion. Do not cache parse failures or cache a null Expr.
- [ ] Clear the map, order Array, and both counters before reload reconstructs the interpreter and when destroy releases it. Leave normal loadFromString behavior for file scripts unchanged.
- [ ] Keep lastExecutionResult assignment and return behavior identical for cache hit and miss paths.

    private static inline var RUN_HAXE_EXPR_CACHE_LIMIT:Int = 64;
    private var runHaxeExprCache:haxe.ds.StringMap<hscript.Expr> = new haxe.ds.StringMap();
    private var runHaxeExprCacheOrder:Array<String> = [];
    public var runHaxeCodeCacheHits(default, null):Int = 0;
    public var runHaxeCodeCacheMisses(default, null):Int = 0;

### Task 3: Compile and compare gameplay behavior

**Files:**
- Build: project Windows Release target.
- Runtime check: mods/d 3 S 0 r mix/data/genocide-d3r/somethincool.lua, without editing it.

**Interfaces:**
- Consumes: the cache counters and executeString behavior from Task 2.
- Produces: a successful Release build and a recorded same-machine D3R comparison after the F8 plan exposes cache counters.

- [ ] Run haxelib run lime build windows -release from Debug Engine-Main and record the exit code and relevant compiler output.
- [ ] Launch the Release build and play the same section of genocide-D3R with the original scripts enabled. Confirm camera follow updates and Lua-to-Haxe effects still execute; record FPS and memory alongside the previous 13–25 FPS observation.
- [ ] After the F8 plan is implemented, capture once during gameplay and confirm repeated snippets increase hits while misses remain bounded by distinct source strings. Do not add temporary logging to the per-frame callback.
- [ ] Report results as observed values; do not claim a fixed FPS target or that the 12,000 × 12,000 graphic was optimized.
