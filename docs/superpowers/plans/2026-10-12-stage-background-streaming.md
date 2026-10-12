# Stage Background Chunk Streaming Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to implement this plan task-by-task. Keep implementation in the engine and do not edit mod content.

**Goal:** Add an engine-owned, opt-in path that splits large static stage images into tiles, prepares tiles near each camera, draws visible tiles, and bounds resident graphics without changing mod files.

**Architecture:** A Python/Pillow command creates lossless RGBA tile files and a versioned manifest in DBE's application cache, keyed by the source image hash and conversion parameters. Haxe runtime code loads a chunk-aware sprite only when a valid manifest exists, computes visible/prefetch tiles from camera view margins, and owns an LRU of `FlxGraphic` references. Existing sprite loading remains the fallback; animated, shader, and screen-space sprites stay on their current path in the first release.

**Tech Stack:** Haxe, HaxeFlixel, OpenFL, existing Lua sprite bridge and bitmap cache; Python 3 with Pillow for offline conversion; Haxe interpreter tests for pure visibility math and pytest for the converter.

**Spec:** `docs/superpowers/specs/2026-10-12-stage-background-streaming-design.md`

## Global Constraints

- Do not edit scripts, images, events, charts, or any other file under `mods/`.
- Preserve the existing dirty worktree; make only narrow edits to the engine files listed in this plan and do not reset or clean unrelated changes.
- Preserve the existing `FlxSprite` path when no valid chunk manifest exists.
- The first eligible runtime path is single-frame world sprites; animated sprites, shader sprites, and screen-space overlays keep the current path.
- Generated files live under DBE application storage, never beside or inside mod files.
- A matching chunk manifest must prevent the original full bitmap from being passed to `FlxG.bitmap.add()` at runtime.
- Keep visible chunks resident and enforce a strict configurable 128 MiB default chunk-cache ceiling. Trim distant prefetch tiles first; if the visible set alone exceeds the ceiling, fall back to the original sprite path before drawing.
- Use a configurable one-tile prefetch ring by default, loaded from an engine-owned settings file in application storage; load camera-destination chunks before drawing after a teleport, even if this causes a one-frame loading hitch.
- Do not claim a performance improvement without recording the launched executable path/hash and a comparable before/after gameplay measurement.

## Review Focus

- A missing, corrupt, or stale manifest must fall back to the original image without a black sprite; pin this in converter/runtime failure-path tests.
- Camera zoom, viewport size, scroll, and sprite scroll factor must produce the correct visible rectangle; pin this in `StageChunkVisibilityTest`.
- A camera teleport beyond the prefetch ring must synchronously obtain destination tiles or use the full-image fallback before draw; pin this in Task 6's camera-teleport gameplay scenario.
- Transparent tile edges must not create seams or halos; pin this by reconstructing test images and comparing every RGBA pixel.
- LRU eviction must never evict a visible tile and must release each graphic reference once; pin pure accounting in `StageChunkLRUTest` and state teardown in Task 6's repeated song-entry scenario.

---

## File Map

- Create `docs/superpowers/results/2026-10-12-genocide-d3r-stage-baseline.md` to record executable identity, settings, frame-rate observations, process memory samples, diagnostic report path, and the go/no-go decision.
- Create `tools/stage-chunker/stage_chunker.py` and `tools/stage-chunker/requirements.txt` for offline lossless image tiling; the tool reads source assets and writes only to its requested cache directory.
- Create `tests/stage_chunker/test_stage_chunker.py` for chunk pixel and manifest checks.
- Create `source/funkin/backend/assets/StageChunkManifest.hx` to validate manifest version/hash/dimensions and expose tile coordinates and paths.
- Create `source/funkin/backend/assets/StageChunkSettings.hx` to load and clamp `prefetchTiles`, `velocityLeadTiles`, and `maximumResidentBytes` from `%LOCALAPPDATA%/DBE/stage-chunks/settings.json`, with defaults of `1`, `1`, and `134217728` bytes.
- Create `source/funkin/backend/assets/StageChunkCache.hx` to load tile bitmaps, own graphic references, track resident bytes, and evict eligible LRU entries.
- Create `source/funkin/backend/assets/StageChunkLRU.hx` as a pure generic LRU/accounting helper so its pin/eviction rules can be tested without initializing OpenFL.
- Create `source/funkin/backend/assets/StageChunkLRU.hx` as a pure generic LRU/accounting helper so its pin/eviction rules can be tested without initializing OpenFL.
- Create `source/funkin/backend/graphics/StageChunkVisibility.hx` for camera-to-world view and tile selection calculations.
- Create `source/funkin/backend/graphics/StageChunkRenderer.hx` to draw selected tile interiors with the owning sprite's supported transforms.
- Create `source/funkin/backend/graphics/StageChunkedLuaSprite.hx`, a `FlxSprite`-compatible wrapper that retains the Lua object's identity and delegates its draw path to the chunk renderer.
- Modify `source/funkin/backend/scripting/LuaScript.hx:174-187` so `makeLuaSprite` chooses the wrapper only when a valid sidecar exists; leave `makeAnimatedLuaSprite` unchanged in this slice.
- Modify `source/funkin/backend/system/GraphicCacheSprite.hx` to add an idempotent release operation for a warmed graphic, allowing streamed graphics to leave its arrays and decrement the use count once.
- Modify `source/funkin/backend/system/PlayStateDiagnostics.hx` to report resident/prefetch tile counts, bytes, cache hits/misses, evictions, and fallback reasons in the existing manual F8 snapshot.
- Create `tests/stage_chunks/haxe/StageChunkVisibilityTest.hx` and `tests/stage_chunks/haxe/StageChunkLRUTest.hx` for pure camera math and cache bookkeeping.
- The first slice does not change `Stage.hx`, `XMLUtil.hx`, `SongAssetManifest.hx`, or `SongLoader.hx`: the measured `Fire-Restaurant` candidates are created through Lua `makeLuaSprite`, and the current song manifest does not preload those Lua-created images. Add XML stage support only after this slice proves safe and worthwhile; XML assets are currently preloaded as full images by the song manifest/loader and require a separate compatibility pass.

## Tasks

### Task 1: Capture the baseline and apply the go/no-go gate

**Files:**
- Create: `docs/superpowers/results/2026-10-12-genocide-d3r-stage-baseline.md`
- Read only: `source/funkin/backend/system/PlayStateDiagnostics.hx`

**Interfaces:**
- Consumes: the installed Release executable and the `genocide-D3R` chart using `Fire-Restaurant`.
- Produces: a baseline record with exact executable identity, the gameplay passage/settings, FPS observations, process memory samples, F8 diagnostic path, and a decision to proceed or stop.

- [ ] **Step 1: Identify the executable actually launched.** While the game is open, record the `Win32_Process.ExecutablePath` and `CommandLine`, then capture that exact file's version, size, and SHA-256. Record source `HEAD` and `git status --short`; do not infer that the executable came from the current dirty checkout.
- [ ] **Step 2: Record the comparison conditions.** Record resolution, display scaling, FPS cap, VSync, low-memory setting, selected difficulty, and a fixed 60-second gameplay passage after the initial load/countdown. Keep scripts active and leave mods untouched. Use an existing script-disable mechanism for a second pass only if one is available in the same binary; do not edit or convert mod scripts to create an A/B mode.
- [ ] **Step 3: Capture current runtime data.** Enable DBE's configured FPS counter and record its value through the fixed passage; sample the same process's `WorkingSet64` and `PrivateMemorySize64` once per second. Trigger the existing F8 diagnostic once during the passage and record its output path; it already reports cameras, stage objects, sprite dimensions, and theoretical RGBA8 sizes. Use an available CPU/GPU profiler for script versus draw/upload attribution; process memory and RGBA8 estimates alone cannot identify that cause.
- [ ] **Step 4: Write the baseline record.** Separate measured values from prior estimates; include `backmost flames`, `newfireglow`, `youhavebeendestroyed`, table assets, and the `WoWpart.lua` particle path as competing candidates.
- [ ] **Step 5: Apply the gate.** Proceed to chunking only if frame/render or texture-residency data implicates static stage imagery. If script/particle CPU dominates, stop this plan before code changes and diagnose that path instead.

Run for an external process-memory sample after the user has entered the fixed passage:

```powershell
$target = Get-Process | Where-Object { $_.ProcessName -like 'CodenameEngine*' } | Select-Object -First 1
1..60 | ForEach-Object {
    $sample = Get-Process -Id $target.Id
    [pscustomobject]@{
        Timestamp = Get-Date -Format o
        PID = $sample.Id
        WorkingSetBytes = $sample.WorkingSet64
        PrivateBytes = $sample.PrivateMemorySize64
        CPUSeconds = $sample.CPU
    }
    Start-Sleep -Seconds 1
} | Export-Csv -NoTypeInformation -Path "$env:TEMP\dbe-genocide-d3r-memory.csv"
```

Expected result: a 60-row CSV and a baseline report tied to the actual process image. The current inspection found no game process and no song-launch command-line option, so this task cannot be completed until the target song is running.

### Task 2: Build and verify the offline tile converter

**Files:**
- Create: `tools/stage-chunker/stage_chunker.py`
- Create: `tools/stage-chunker/requirements.txt`
- Create: `tests/stage_chunker/test_stage_chunker.py`

**Interfaces:**
- Consumes: `input.png`, a cache output directory, `--tile-size` (default `1024`), and `--gutter` (default `2`).
- Produces: `manifest.json` with format version, SHA-256 of the original source, logical width/height, tile size, gutter, and each tile's interior rectangle and output file name; one lossless RGBA PNG per tile.

- [ ] **Step 1: Add converter tests first.** Cover a non-multiple image size, fully transparent pixels, semi-transparent edges, RGB and palette PNG input, and deterministic cache identity. Reconstruct the source from tile interiors and assert byte-for-byte RGBA equality.
- [ ] **Step 2: Run the converter test command and confirm the new cases fail.**

```powershell
python -m pytest tests/stage_chunker/test_stage_chunker.py -q
```

- [ ] **Step 3: Implement only the converter contract.** Use Pillow to decode to RGBA, crop exact tile interiors, extend each tile by clamped neighbor pixels for the gutter, write each tile to a temporary file, then atomically write the manifest last. Derive the output directory from source SHA-256 plus format version/tile/gutter parameters. Never overwrite or move the input image.
- [ ] **Step 4: Re-run converter tests and build sidecars for only the measured eligible assets.** Start with `youhavebeendestroyed.png`, `ltables.png`, and `rtables.png`; do not generate sidecars for animated `backmost flames.png`/`newfireglow.png` or the screen-space vignette.

Run the converter after installing its isolated tool dependency:

```powershell
python -m pip install -r tools/stage-chunker/requirements.txt
python tools/stage-chunker/stage_chunker.py "<absolute source PNG>" --cache-dir "$env:LOCALAPPDATA\DBE\stage-chunks" --tile-size 1024 --gutter 2
```

Expected result: exact RGBA reconstruction from tile interiors, a valid versioned manifest, and no source-file or `mods/` changes.

### Task 3: Implement camera bounds and the bounded tile cache

**Files:**
- Create: `source/funkin/backend/assets/StageChunkManifest.hx`
- Create: `source/funkin/backend/assets/StageChunkCache.hx`
- Create: `source/funkin/backend/graphics/StageChunkVisibility.hx`
- Modify: `source/funkin/backend/system/GraphicCacheSprite.hx`
- Create: `tests/stage_chunks/haxe/StageChunkVisibilityTest.hx`
- Create: `source/funkin/backend/assets/StageChunkSettings.hx`
- Create: `source/funkin/backend/assets/StageChunkLRU.hx`
- Create: `tests/stage_chunks/haxe/StageChunkLRUTest.hx`

**Interfaces:**
- Consumes: source asset key, validated manifest, `FlxCamera`, sprite `scrollFactor`, configured prefetch ring, and maximum resident byte count.
- Produces: visible tile IDs, prefetch tile IDs, acquired `FlxGraphic` handles, and cache counters. Define `StageChunkTransform` with `x`, `y`, `scaleX`, `scaleY`, `offsetX`, `offsetY`, `originX`, `originY`, `scrollFactorX`, and `scrollFactorY`; define `StageChunkVisibilityResult` with `visible:Array<Int>` and `prefetch:Array<Int>`. `StageChunkVisibility.selectTiles(width:Int, height:Int, tileSize:Int, transform:StageChunkTransform, cameraScrollX:Float, cameraScrollY:Float, viewMarginX:Float, viewMarginY:Float, viewWidth:Float, viewHeight:Float, prefetchTiles:Int, velocityLeadX:Float, velocityLeadY:Float):StageChunkVisibilityResult` stays pure; the renderer adapts `FlxCamera` and `FlxSprite` fields into these values.

- [ ] **Step 1: Write Haxe tests for visible-rectangle math.** Verify camera zoom through `viewMarginX/Y` and `viewWidth/Height`, normal `scrollFactor=(1,1)`, parallax factors `(0.5,0.5)`, screen-fixed factor `(0,0)`, negative sprite origins, and cameras with different viewport sizes.
- [ ] **Step 2: Run the pure helper test and confirm it fails.**

```powershell
haxe -cp source -cp tests/stage_chunks/haxe -main StageChunkVisibilityTest --interp
```

- [ ] **Step 3: Implement manifest validation and tile selection.** Reject unsupported format versions, source-hash mismatches, missing files, invalid dimensions, and out-of-range rectangles. Keep `StageChunkVisibility` free of Flixel types: pass camera `scroll`, `viewMargin`, and `viewWidth/viewHeight` as numbers. For each axis, set visible origin to `camera.scroll * sprite.scrollFactor + camera.viewMargin`, then expand the resulting rectangle by the configured tile ring and a clamped lead based on camera movement.
- [ ] **Step 4: Implement the state-scoped LRU.** Load a tile only when it is in visible/prefetch demand, account RGBA bytes, pin visible entries, evict least-recently-used entries outside the visible set, and trim the farthest prefetch tiles until the cache fits. If visible tiles alone exceed the cap, mark the sprite ineligible so it uses the original path. Protect entries from duplicate loads while one load is pending. Read/clamp the settings file once, create it with defaults if absent, and ignore invalid JSON/values in favor of defaults.
- [ ] **Step 5: Add idempotent GPU-cache release.** `GraphicCacheSprite.releaseGraphic(graphic)` removes one owned reference from both arrays and decrements its use count once. Track the graphic's prior `destroyOnNoUse` state and restore it only after this cache releases its last reference. Use this only for chunk graphics; leave existing song-wide pinning behavior unchanged.
- [ ] **Step 6: Re-run the pure Haxe tests.**

```powershell
haxe -cp source -cp tests/stage_chunks/haxe -main StageChunkVisibilityTest --interp
haxe -cp source -cp tests/stage_chunks/haxe -main StageChunkLRUTest --interp
```

Expected result: camera/zoom/parallax cases select the expected tile set; repeated acquire/release, LRU eviction, and protected visible tiles obey the byte budget. The Windows gameplay check later confirms actual `FlxGraphic` references return to baseline at state teardown.

### Task 4: Preserve Lua sprite behavior while drawing chunked static images

**Files:**
- Create: `source/funkin/backend/graphics/StageChunkRenderer.hx`
- Create: `source/funkin/backend/graphics/StageChunkedLuaSprite.hx`
- Modify: `source/funkin/backend/scripting/LuaScript.hx:174-187`
- Modify: `source/funkin/backend/system/PlayStateDiagnostics.hx`
- Create: `tests/stage_chunks/haxe/StageChunkSpriteContractTest.hx`

**Interfaces:**
- Consumes: original Lua `makeLuaSprite` arguments, source asset key, valid sidecar, current sprite transform, cache, and camera.
- Produces: the same registered Lua object identity/API, with tile-backed drawing when the asset is eligible; the unchanged normal `FlxSprite` path for all other cases.

Implement `StageChunkedLuaSprite.tryCreate(x:Float, y:Float, image:String):Null<StageChunkedLuaSprite>`; it returns `null` for a missing/invalid sidecar or unsupported asset. `LuaScript.makeLuaSprite` keeps its existing constructor/load path on `null` and registers the returned subtype unchanged otherwise.

- [ ] **Step 1: Add sprite-contract cases before integration.** Pin that missing/corrupt sidecars choose a normal `FlxSprite`, valid static sidecars choose a `FlxSprite` subtype, the registry returns the same instance, and alpha/position/scale/scroll factor/order pass through unchanged.
- [ ] **Step 2: Run the contract test and confirm it fails before implementation.**

```powershell
haxe -cp source -cp tests/stage_chunks/haxe -main StageChunkSpriteContractTest --interp
```

- [ ] **Step 3: Implement a chunk renderer for the supported contract.** Draw only each tile's interior rectangle, place it at its source-space offset, and apply the owner's position, logical width/height, scale, origin, offset, hitbox, alpha, tint, blend, antialiasing, and camera list. Honor draw order by keeping one logical sprite in the same Lua registry and PlayState member list.
- [ ] **Step 4: Integrate only `makeLuaSprite`.** If and only if a sidecar validates, create `StageChunkedLuaSprite`; otherwise execute the exact current `new FlxSprite(x, y)` plus `loadGraphic(Paths.image(image))` path. Do not change `makeAnimatedLuaSprite`.
- [ ] **Step 5: Add a safe fallback before draw.** If the logical object is asked to load another graphic, gains animation frames, nonzero rotation, or a shader, synchronously load the original bitmap, release its chunks, and use the existing `FlxSprite` draw path that frame. Keep this fallback visible in F8 diagnostics.
- [ ] **Step 6: Extend the manual F8 snapshot.** Report manifest eligibility/failure, visible/prefetched/resident tile counts, resident bytes, hits, misses, evictions, fallback reason, and tile load time without adding per-frame strings or unbounded allocations.
- [ ] **Step 7: Re-run the contract test and build the Windows target.**

```powershell
haxe -cp source -cp tests/stage_chunks/haxe -main StageChunkSpriteContractTest --interp
lime test windows -release
```

Expected result: existing Lua script references still point to one sprite object; unsupported assets and scripts render through the old full-image path; eligible static sprites do not load the source PNG as a runtime `FlxGraphic`.

### Task 5: Integrate ordinary XML stage sprites only if needed after the Lua slice

**Files:**
- Modify: `source/funkin/backend/utils/XMLUtil.hx:313-318`
- Modify: `source/funkin/backend/assets/SongAssetManifest.hx:65-76`
- Create: `source/funkin/backend/graphics/StageChunkedFunkinSprite.hx`
- Create: `tests/stage_chunks/haxe/StageChunkXMLContractTest.hx`

**Interfaces:**
- Consumes: a static, single-frame XML stage sprite node and a valid sidecar manifest.
- Produces: a `FunkinSprite` subtype for eligible nodes, while animated/atlas nodes and invalid sidecars retain current construction and full-image preloading.

- [ ] **Step 1: Add XML contract cases.** Verify that a static eligible node selects a `FunkinSprite` subtype, an animated/atlas node remains a normal `FunkinSprite`, and a stale manifest keeps the original source image in the song manifest.
- [ ] **Step 2: Implement the subtype using the same renderer/cache, without adding chunks to the song-wide pinned `GraphicCacheSprite` list.**
- [ ] **Step 3: Change `SongAssetManifest` to omit the original full-image entry only when the XML node is single-frame and its sidecar validates.** The stage sprite loads its visible+prefetch tiles during stage construction, before the countdown. Any validation/load failure restores the original image path and reports the fallback.
- [ ] **Step 4: Run the XML contract test and Windows build.**

```powershell
haxe -cp source -cp tests/stage_chunks/haxe -main StageChunkXMLContractTest --interp
lime test windows -release
```

Expected result: XML static stage art can use tiles without full-source preloading, while spritesheets, animated nodes, and unsupported nodes keep their current timing and behavior. Do not start this task unless the Lua slice passes its visual/performance gate or the user needs XML-only assets covered.

### Task 6: Validate visual continuity, resource lifetime, and performance

**Files:**
- Update: `docs/superpowers/results/2026-10-12-genocide-d3r-stage-baseline.md`
- Read: F8 report, process samples, generated manifest, and final `git status --short`.

**Interfaces:**
- Consumes: baseline from Task 1 and a Release build with chunk streaming.
- Produces: paired before/after data and an explicit pass/fail decision for visual behavior, cache bounds, load time, frame time, and memory.

- [ ] **Step 1: Run the same build conditions and the same gameplay passage with active scripts.** Record the new executable path/version/hash and confirm it is the build just tested.
- [ ] **Step 2: Exercise camera motion.** Test continuous pan across tile boundaries, maximum zoom-in/out, a fast camera move, and a camera teleport farther than the prefetch ring. Confirm no blank gap; record any synchronous fallback hitch.
- [ ] **Step 3: Exercise sprite compatibility.** Confirm target static sprites keep logical width/height, hitbox, alpha, position, scale, scroll factor, object order, and correct transparency; confirm animated flames, shader overlay, and screen-space vignette remain on the old path.
- [ ] **Step 4: Exercise cache lifetime.** Repeatedly enter/exit the song and pan enough to evict tiles; confirm F8 resident bytes remain bounded, visible tiles are not evicted, and reference counts return to baseline after state teardown.
- [ ] **Step 5: Compare paired metrics.** Report FPS samples/median and low-percentile FPS, process working/private bytes, song-entry time, tile decode/upload counts, resident-byte peak, and fallback events. Keep RGBA8 estimates labeled as estimates and use the benchmark to decide whether to retain or revert the feature.
- [ ] **Step 6: Verify scope.** Confirm no files under `mods/` changed and list only intended engine/tool/test/docs files in the final diff.

## Stop Conditions

- If Task 1 identifies script/particle CPU as the dominant cost, stop before converter/runtime changes; this tool is not a targeted fix for that bottleneck.
- If a `FlxSprite`-compatible wrapper cannot preserve Lua-visible properties and object identity, stop automatic selection and keep the existing full-image path.
- If a teleport or cache miss can show an uncovered frame and synchronous fallback cannot cover it, do not ship streaming for that camera path.
- If measured memory/load/FPS does not improve enough to justify complexity, keep the diagnostic and benchmark results but do not enable chunk streaming by default.
