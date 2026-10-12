# F8 Script and Camera Snapshot Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task, or superpowers:subagent-driven-development if the user selects subagent execution. Track steps with checkbox syntax.

**Goal:** Extend the existing Ctrl+Shift+F8 report with a bounded snapshot of script types/cache counters, camera filters, and backing-graphic sizes.

**Architecture:** Keep PlayStateDiagnostics.capture as the only collection point and add summary sections to its existing report builder. Read current PlayState ScriptPack, FlxG camera manager, FlxCamera.filters, and the graphics of sprites already traversed; do no ongoing timing or per-frame logging.

**Tech Stack:** Haxe, HaxeFlixel, DBE PlayState diagnostics.

**Spec:** docs/superpowers/specs/2026-10-11-d3r-script-performance-design.md

## Global Constraints

- Ctrl+Shift+F8 remains the existing trigger; no new hotkey or automatic capture.
- Report script/cache counts, camera filters, and approximate RGBA8 backing-graphic sizes only when available.
- Graphic byte counts are theoretical CPU bitmap estimates, not process-memory or GPU measurements.
- Handle null ScriptPack, camera list, filter list, graphic, and dimensions without aborting report generation.
- No Lua, chart, event, character, shader, or other mod file changes.
- Do not modify makeGraphic or its scale/frame semantics.
- No automated test files are added or run for this task; validation uses the Windows Release build and one manual F8 capture.
- Do not commit; local DBE development instructions prohibit commits unless explicitly requested.

## Review Focus

- Null or empty FlxG.cameras.list must still produce a report; inspect guards around camera enumeration.
- Null or empty camera.filters and filtersEnabled=false must be reported without calling filter methods; capture with cameras both with and without filters.
- A null/empty ScriptPack and non-HScript Script entries must not break type or cache aggregation; inspect casts and capture during a normal song.
- Missing graphic or unavailable width/height must be marked unknown, not treated as zero-byte proof; inspect dimension guards and capture a sprite without a graphic if present.
- Repeated F8 captures must stay on-demand and avoid frame logging; use the existing hotkey twice and compare that no continuous console output appears.

---

### Task 1: Summarize active gameplay scripts and HScript cache counters

**Files:**
- Modify: source/funkin/backend/system/PlayStateDiagnostics.hx: buildReport loaded-scripts section
- Read: source/funkin/game/PlayState.hx:101-103, 1540-1541
- Read: source/funkin/backend/scripting/ScriptPack.hx:10-18
- Read: source/funkin/backend/scripting/HScript.hx: public cache counters from plan 2026-10-11-runhaxecode-parse-cache.md

**Interfaces:**
- Consumes: PlayState.scripts.scripts and HScript.runHaxeCodeCacheHits/runHaxeCodeCacheMisses.
- Produces: a ScriptPack summary with total/active counts by concrete script type and summed HScript cache hits/misses, followed by the existing per-script paths.

- [ ] Reuse the existing LOADED SCRIPTS section; do not create a second full script listing.
- [ ] Count entries in game.scripts.scripts by Type.getClassName(Type.getClass(script)); count active entries separately. Continue listing each script path and active flag as today.
- [ ] For entries that are HScript, add the public hit/miss properties from the cache plan. Sum them with Int counters; if there is no HScript entry, report zero and an explicit no-HScript note.
- [ ] Guard game.scripts and individual entries before type inspection. Do not traverse character or state script packs in this phase; label the summary as the PlayState ScriptPack.

### Task 2: Report camera filters and backing-graphic dimensions

**Files:**
- Modify: source/funkin/backend/system/PlayStateDiagnostics.hx: camera-manager section, appendCamera, walkObject
- Read: .haxelib/flixel/git/flixel/FlxCamera.hx: filters, filtersEnabled
- Read: .haxelib/flixel/git/flixel/graphics/FlxGraphic.hx: width, height, key

**Interfaces:**
- Consumes: existing camera/render-tree traversal and FlxGraphic width/height fields.
- Produces: camera count plus per-camera filter count/class names; sprite lines include backing dimensions and theoretical RGBA8 bytes when valid.

- [ ] In the camera-manager section, count registered cameras from FlxG.cameras.list. In appendCamera, include filtersEnabled and either <none>, <null>, or a bounded comma-separated list of each filter's concrete class and total count.
- [ ] For each FlxSprite in walkObject, read the graphic key, width, and height with the existing null-safe reflection style. For positive numeric dimensions, compute bytes using Float arithmetic as width × height × 4 and label it estimateRGBA8Bytes. For missing/invalid dimensions, write unknown.
- [ ] Keep existing MAX_OBJECTS behavior and cap printed filter names to a small fixed count (16); include the total count if the list is longer. Do not inspect shader internals or invoke methods on filter objects.
- [ ] Do not claim the graphic estimate identifies allocation origin or actual GPU memory; it is a size estimate for the backing image visible in the current render tree.

### Task 3: Build and capture one in-game report

**Files:**
- Build: project Windows Release target.
- Runtime check: existing Ctrl+Shift+F8 path in source/funkin/game/PlayState.hx:1540-1541.

**Interfaces:**
- Consumes: script/cache summary and camera/graphic fields from Tasks 1 and 2.
- Produces: one F8 report from genocide-D3R that can guide the next measured optimization.

- [ ] Run haxelib run lime build windows -release from Debug Engine-Main and record exit code and compiler output.
- [ ] Launch Release, play genocide-D3R until its Lua scripts are active, press Ctrl+Shift+F8 once, and read the saved report path shown by the game.
- [ ] Confirm the report includes script counts, HScript cache counters, camera/filter data, and the 12,000 × 12,000 backing graphic if that sprite is in the traversed render tree. Confirm null entries do not abort capture and no per-frame log spam appears.
- [ ] Record FPS and memory shown by the same Release run for comparison; state clearly that this snapshot does not profile CPU or GPU time and that the giant graphic remains unchanged.
