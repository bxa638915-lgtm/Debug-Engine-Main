# Psych Engine Lua Support for DBE Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Demonstrate behavior-level Lua compatibility for Psych Engine 0.6.3 and 1.0.4 in DBE, using pinned source references, versioned contracts, and fixtures that exercise the actual Lua bridge.

**Architecture:** Keep `LuaScript` as DBE's LuaJIT adapter and keep HScript Improved as CNE's default HScript runtime. Store per-version contract catalogs and source locks under `docs/compatibility/contracts/`; use a small per-mod profile resolver only for incompatible semantics; exercise bindings through deterministic Lua fixtures and gameplay smoke runs.

**Tech Stack:** Haxe, LuaJIT/Lua 5.1 on supported C++ targets, HScript Improved, PowerShell, Python standard library, JSON Schema, existing DBE compatibility and gameplay-smoke infrastructure.

**Spec:** [2026-10-10-psych-lua-dbe-design.md](../specs/2026-10-10-psych-lua-dbe-design.md)

## Global Constraints

The following exclusions are copied from the approved spec and remain out of scope for every task in this plan:

- Substituir LuaJIT, o ScriptAdapterManager ou o runtime HScript padrão da CNE.
- Portar a engine Psych inteira, sua interface, assets, menus ou gameplay que não sejam necessários para contratos Lua.
- Compilar Haxe completo em runtime. runHaxeCode será tratado como o interpretador HScript usado pelo Psych e terá suas diferenças registradas.
- Declarar suporte Web ou mobile sem runtime Lua disponível e validado para esses alvos.
- Isolar scripts em sandbox ou impor quotas de CPU e memória. Scripts continuam executando no processo do jogo.

The approved spec also records: “O checkout tem mudanças locais extensas: 856 remoções rastreadas e 8 arquivos Haxe modificados na verificação de 10 de outubro de 2026. Essas mudanças devem ser preservadas.” The existing `building/compat-test.ps1` refers to test files deleted from this working tree; do not restore or overwrite those files. Add a dedicated Psych Lua runner for the new tests and fixtures.

## Review Focus

1. **Missing, malformed, and unsupported profile config:** prove common APIs remain available, profile-specific ambiguous APIs fail closed, and diagnostics name the mod and API. Test in Task 3 with `tests/psych_contracts/haxe/PsychLuaProfileTest.hx` and both profile-selection Lua fixtures.
2. **Omitted, nil, and coerced arguments:** check defaults and Lua/Haxe conversions for optional arguments and false/zero/empty-string values. Cover each contract entry with a fixture ID and test through the actual bridge in Task 4.
3. **Cross-language cancellation and callback errors:** verify `Function_Stop`, `Function_StopLua`, `Function_StopHScript`, `Function_StopAll`, `ignoreStops`, `excludeValues`, and a throwing Lua callback preserve the source behavior. Test in Task 5.
4. **Notes changed around spawn dispatch:** exercise multiple strumlines, equal note lanes, insertion/removal/reordering, and one-time `onSpawnNote` delivery at the documented scheduler boundary. Test in Task 5.
5. **HScript interpreter boundary:** verify injected variables, callable functions, return conversion, state persistence, import behavior, and interpreter errors for `runHaxeCode`/`runHaxeFunction`; record unsupported Haxe-compiler-only syntax as an incompatibility. Test in Task 6.

## File Map

- `docs/compatibility/contracts/source-lock.json` — immutable Psych repository, tag, commit, and source-snapshot checksums.
- `docs/compatibility/contracts/psych-contract.schema.json` — JSON Schema for API and callback contract entries.
- `docs/compatibility/contracts/psych-0.6.3.json` and `psych-1.0.4.json` — exhaustive versioned source inventories reconciled with DBE bindings and fixtures.
- `tests/fixtures/psych-lua/fixture-manifest.json` — stable fixture IDs, profile, script paths, and covered API/callback names; physical Lua fixtures are added in Tasks 3–6.
- `tools/psych-compat/extract_catalog.py` and `verify_contracts.py` — source inventory and catalog/fixture validation tools.
- `tests/psych_contracts/` — Python standard-library checks for source locks, schema, API reconciliation, and fixture coverage.
- `tests/fixtures/psych-lua/{0.6.3,1.0.4}/` — profile metadata and behavior fixtures, grouped by lifecycle, API domain, and callbacks.
- `building/psych-lua-test.ps1` — dedicated contract and gameplay-fixture runner; does not depend on or rewrite deleted tests in `building/compat-test.ps1`.
- `source/cne/compat/PsychLuaProfile.hx` — profile value, config parsing, and ambiguity policy.
- `source/funkin/backend/assets/ModsFolder.hx`, `source/funkin/backend/scripting/Script.hx`, `source/funkin/backend/scripting/LuaScript.hx`, and `source/cne/compat/ScriptCapabilities.hx` — load and expose the selected profile, report it, and dispatch only profile-safe semantics.
- `source/funkin/game/PlayState.hx`, `source/cne/compat/PsychHookMap.hx`, and `source/cne/compat/PsychCallbackResult.hx` — callback timing, arguments, order, and cancellation behavior where fixtures prove a gap.
- Existing focused adapters such as `PsychLuaPropertyPath.hx`, `PsychLuaObjectRegistry.hx`, `PsychLuaCamera.hx`, `PsychDialogueConverter.hx`, `PsychLuaSubState.hx`, and `PsychAchievementStore.hx` — change only when their contract fixtures expose a mismatch.
- `docs/compatibility/COMPATIBILITY-API.md`, `COMPATIBILITY-AUDIT.md`, `COMPATIBILITY-MATRIX.md`, and `COMPATIBILITY-ROADMAP.md` — evidence-based final API and platform claims.

## Task 1: Pin Psych source and build exhaustive contract catalogs

**Files:** `docs/compatibility/contracts/source-lock.json`, `docs/compatibility/contracts/psych-contract.schema.json`, `docs/compatibility/contracts/psych-0.6.3.json`, `docs/compatibility/contracts/psych-1.0.4.json`, `tests/fixtures/psych-lua/fixture-manifest.json`, `tools/psych-compat/extract_catalog.py`, `tools/psych-compat/verify_contracts.py`, `tests/psych_contracts/test_catalog.py`.

- [ ] Add failing Python tests for missing source locks, commit/tag mismatch, invalid contract states, missing signature/default/return/effect/error/platform/evidence fields, duplicate API names, and catalog entries without a source location.
- [ ] Run `python -m unittest discover -s tests/psych_contracts -p "test_*.py"` and confirm the new catalog checks fail before the catalog/schema/tool files exist.
- [ ] Pin the official [`0.6.3` tag](https://github.com/ShadowMario/FNF-PsychEngine/tree/eb0ade39e8d1c5437db2166a9ddb6eb3c05956e1) to commit `eb0ade39e8d1c5437db2166a9ddb6eb3c05956e1` and the official [`1.0.4` tag](https://github.com/ShadowMario/FNF-PsychEngine/tree/5c67ced49e5a98535298a6daa3f8f4ec79ac8399) to commit `5c67ced49e5a98535298a6daa3f8f4ec79ac8399`. Fetch each exact commit into a temporary source directory, calculate and record the archive/snapshot SHA-256, and do not use the local `FNF-PsychEngine-0.6.3` folder as contract evidence unless its content matches the pinned commit.
- [ ] Define the contract schema with explicit states `compatible`, `adapted`, `incompatible`, and `not-verified`. Function entries record the ordered parameters, accepted values, defaults, variadic behavior, return/conversion, effects, preconditions, platform/build requirements, error behavior, DBE binding, fixture ID, and source path/line. Callback entries record event source, trigger boundary, order, arguments, return/cancellation, fixture ID, and source path/line.
- [ ] Implement the source scanner to extract callback names and source locations from each pinned Psych tree and extract DBE names from the explicit `LuaScript` callback registrations. Generate reviewable inventories; do not infer full behavior or mark a contract compatible from a name match.
- [ ] Complete both catalogs: every source API and callback is reconciled against DBE, every DBE-only entry is explained, profile differences are classified, and every compatible/adapted entry is assigned a behavior fixture ID. Add those IDs, profile labels, script paths, and covered API/callback names to `fixture-manifest.json`; mark physical fixtures pending until their owning tasks add them. Mark unresolved contracts `not-verified`; they cannot support a parity claim.
- [ ] Run the Python suite and `python tools/psych-compat/verify_contracts.py --fetch-pinned-sources`; require zero unclassified names, valid source hashes, schema-valid catalogs, and fixture references that resolve through the manifest.

## Task 2: Add a dedicated test runner without restoring removed tests

**Files:** `building/psych-lua-test.ps1`, `tests/psych_contracts/test_fixture_coverage.py`, `tests/fixtures/psych-lua/fixture-manifest.json`, `tests/fixtures/psych-lua/README.md`.

- [ ] Add failing tests that reject a compatible catalog entry without a fixture-manifest entry, a fixture ID absent from the manifest, an API assigned to a fixture whose `covers` list omits it, and a fixture declaration whose profile disagrees with its profile-specific path.
- [ ] Run the new Python suite and confirm each invalid fixture/catalog case is rejected.
- [ ] Implement `building/psych-lua-test.ps1` with separate `-ValidateOnly`, `-BuildEngine`, and `-GameplaySmoke` switches. `-ValidateOnly` runs Python catalog/manifest checks without requiring physical Lua fixtures that later tasks have not added yet; `-GameplaySmoke` requires every requested fixture file to exist and an existing or explicitly requested Windows release build. Never call the currently broken `building/compat-test.ps1` as a prerequisite.
- [ ] Make the runner create only a uniquely named temporary mod under the resolved Windows release `mods` directory, refuse to overwrite an existing directory, launch only the engine executable it started, and remove only that verified temporary mod in `finally`.
- [ ] Add runner checks for every expected marker, callback order, profile report, and Lua error marker. Preserve logs under `export/compat-tests/` for diagnosis.
- [ ] Run `python -m unittest discover -s tests/psych_contracts -p "test_*.py"` and `./building/psych-lua-test.ps1 -ValidateOnly`; confirm the dedicated runner works while the deleted legacy tests remain deleted and reports gameplay fixtures as pending until their owning tasks add them.

## Task 3: Resolve and expose an explicit per-mod Psych Lua profile

**Files:** `source/cne/compat/PsychLuaProfile.hx`, `source/funkin/backend/assets/ModsFolder.hx`, `source/funkin/backend/scripting/Script.hx`, `source/funkin/backend/scripting/LuaScript.hx`, `source/cne/compat/ScriptCapabilities.hx`, `tests/psych_contracts/haxe/PsychLuaProfileTest.hx`, `tests/fixtures/psych-lua/{0.6.3,1.0.4}/profile-selection.lua`, `tests/psych_contracts/test_profile_config.py`.

- [ ] Add failing resolver tests for absent config, each supported profile, malformed JSON, unsupported version, empty version, and two mods loaded successively without state leakage.
- [ ] Run `haxe -cp source -cp tests/psych_contracts/haxe -main PsychLuaProfileTest --interp` and confirm the new profile cases fail before implementation.
- [ ] Add an optional `data/config/dbe-compat.json` mod file with the single documented field `psychLuaProfile` (`"0.6.3"` or `"1.0.4"`). Read it through the active mod asset path so directory, ZIP, and converted mods use the same rule; preserve unknown mod metadata and leave the Psych source schema unchanged.
- [ ] Represent no selection explicitly as `unspecified`. Shared contracts run normally. For a version-incompatible API called with `unspecified`, fail closed using that API's documented neutral return, log one diagnostic per mod/API naming both candidate profiles and the required config, and never guess from Lua text or folder layout.
- [ ] Reset the cached profile when `ModsFolder` changes, and expose the selected/unspecified profile in `engine.compatibility` and the DBE conversion/compatibility report without changing source format detection.
- [ ] Add fixtures for both selected versions, no config, malformed JSON, and unsupported values; run the Haxe profile test, Python profile/config tests, and `./building/psych-lua-test.ps1 -ValidateOnly`.

## Task 4: Close lifecycle, property, groups, objects, and rendering contracts

**Files:** `source/funkin/backend/scripting/LuaScript.hx`, `source/cne/compat/PsychLuaPropertyPath.hx`, `source/cne/compat/PsychLuaObjectRegistry.hx`, `source/cne/compat/PsychLuaCamera.hx`, `source/funkin/game/PlayState.hx`, `tests/fixtures/psych-lua/{0.6.3,1.0.4}/lifecycle.lua`, `properties-groups.lua`, `objects-rendering.lua`.

- [ ] Add the two-version Lua fixtures first. Each fixture calls every compatible/adapted catalog entry in these domains and asserts the documented return and observable value/effect, including omitted arguments, explicit `nil`, `false`, `0`, empty strings, missing tags, invalid group indices, indexed property paths, and duplicate object tags.
- [ ] Run `./building/psych-lua-test.ps1 -BuildEngine -GameplaySmoke -Profiles 0.6.3,1.0.4` and capture the failing markers before adapter changes.
- [ ] Compare fixture output with both source contracts. Patch only demonstrated mismatches in init/load/reload/close cleanup, property and class access, group access, object registry, sprites/animations, text, camera routing, and graphics sizing; retain existing CNE behavior outside Lua calls.
- [ ] Verify every binding in these categories maps to at least one fixture assertion and every unsupported or ambiguous behavior is explicitly marked in both catalogs.
- [ ] Rerun those fixtures for both profiles and require no Lua load/API errors, leaked tagged objects, or changed behavior in the existing HScript smoke markers.

## Task 5: Match gameplay callbacks, dispatch, notes, input, and scheduler timing

**Files:** `source/funkin/backend/scripting/LuaScript.hx`, `source/cne/compat/PsychHookMap.hx`, `source/cne/compat/PsychCallbackResult.hx`, `source/funkin/game/PlayState.hx`, `tests/psych_contracts/haxe/PsychHookMapContractTest.hx`, `tests/psych_contracts/haxe/PsychCallbackDispatchTest.hx`, `tests/fixtures/psych-lua/{0.6.3,1.0.4}/callbacks.lua`, `notes-scheduler.lua`, `input-cancellation.lua`.

- [ ] Add failing tests for callback argument order/conversions, callback call order, all stop constants, `ignoreStops`, `excludeValues`, exceptions, event early-trigger timing, input cancellation on one lane, note index changes, multiple strumlines, note removal/reordering, and exactly-once spawn delivery.
- [ ] Run `haxe -cp source -cp tests/psych_contracts/haxe -main PsychHookMapContractTest --interp`, `haxe -cp source -cp tests/psych_contracts/haxe -main PsychCallbackDispatchTest --interp`, and the two-version gameplay fixtures; record their pre-fix failures.
- [ ] Implement only divergences the pinned contracts and fixtures establish in hook mapping, scheduler boundary, note aggregate order/indexing, Lua/HScript dispatch, and cancellation propagation. Preserve event ordering from the approved contract; do not approximate an unverified Psych scheduler boundary as parity.
- [ ] Confirm callback fixtures observe event time, argument count/value, script order, cancellation result, and side effect in the game log for both profiles.
- [ ] Rerun both Haxe tests and the gameplay fixtures; require no duplicate/missed `onSpawnNote`, no blocked unrelated input lane, and no HScript callback skipped by a Lua result that should not stop it.

## Task 6: Close timers, tweens, audio, shaders, persistence, dialogue, achievements, and HScript interop

**Files:** `source/funkin/backend/scripting/LuaScript.hx`, `source/cne/compat/PsychDialogueConverter.hx`, `source/cne/compat/PsychLuaSubState.hx`, `source/cne/compat/PsychAchievementStore.hx`, `source/funkin/backend/scripting/HScript.hx`, `tests/fixtures/psych-lua/{0.6.3,1.0.4}/timers-tweens-audio.lua`, `saves-settings-achievements.lua`, `dialogue-substates.lua`, `hscript-interop.lua`.

- [ ] Add two-version fixtures that assert timer/tween completion and cancellation, sound lifecycle, shader set/get conversions, save persistence across state switches, configured mod settings, achievement data and unlock presentation, dialogue JSON/portrait resolution, custom substate callbacks, and HScript injected variables/call/return/state/error behavior.
- [ ] Run the fixtures and capture failing markers for both profiles before changing adapters.
- [ ] Compare each result with the source contracts. Implement missing persistent settings and achievement visual behavior only to the documented Psych contract; if a behavior depends on Psych-only assets/UI that DBE cannot provide, mark it incompatible with an observable diagnostic instead of reporting success.
- [ ] Compare `runHaxeCode`, `runHaxeFunction`, and `addHaxeLibrary` against Psych's HScript Iris source. Keep HScript Improved as the target interpreter, document syntax/API differences per contract, and reject or report unsupported operations without claiming Haxe compilation.
- [ ] Rerun all four fixture groups on both profiles and confirm cleanup after reload/state switch, persisted values after reopening, and explicit expected results for every incompatibility.

## Task 7: Close catalog coverage and publish evidence-based compatibility claims

**Files:** `tools/psych-compat/verify_contracts.py`, `tests/psych_contracts/test_catalog.py`, `tests/psych_contracts/test_fixture_coverage.py`, `docs/compatibility/COMPATIBILITY-API.md`, `docs/compatibility/COMPATIBILITY-AUDIT.md`, `docs/compatibility/COMPATIBILITY-MATRIX.md`, `docs/compatibility/COMPATIBILITY-ROADMAP.md`, `docs/compatibility/examples/psych-basic.lua`.

- [ ] Add failing final-gate checks that reject any `not-verified` catalog entry, any compatible/adapted entry without an on-disk fixture and passing fixture result, any source API name without a classified DBE mapping, and any platform/profile claim without a recorded run result.
- [ ] Run `python -m unittest discover -s tests/psych_contracts -p "test_*.py"` and confirm the gate rejects intentionally incomplete catalog copies used by the tests.
- [ ] Implement the evidence report generation: include pinned source commit/checksum, profile selection, function/callback counts by status, fixture IDs and results, DBE binding target, and per-platform build/smoke result. Keep incompatible behaviors visible and do not convert `not-verified` to compatible from name matching.
- [ ] Update API docs, audit, matrix, roadmap, and example to agree with the catalog. Correct the stale statement that this checkout has no Git, and replace prior unsupported “all names are compatible” language with status/evidence summaries.
- [ ] Run the final Python gate and `./building/psych-lua-test.ps1 -ValidateOnly`; require both catalogs to validate, all fixture references to resolve, and no unverified contracts before any full-profile claim.

## Task 8: Validate supported desktop targets and finalize the matrix

**Files:** `building/psych-lua-test.ps1`, `docs/compatibility/COMPATIBILITY-MATRIX.md`, `docs/compatibility/COMPATIBILITY-AUDIT.md`.

- [ ] On Windows, run `haxelib run lime build windows -release` and `./building/psych-lua-test.ps1 -GameplaySmoke -Profiles 0.6.3,1.0.4`; capture the exact source locks, logs, fixture results, and build result.
- [ ] On Linux and macOS, run the same Lua-enabled desktop build and gameplay smoke only when the target toolchain and LuaJIT dependency are available. Record unavailable toolchains as unvalidated; do not infer a pass from Windows.
- [ ] Re-run the HScript-only build/configuration without `LUA_ALLOWED` to verify builds that omit Lua still compile and do not advertise `.lua` support.
- [ ] Update the compatibility matrix so each Psych profile and desktop platform is marked supported only when its catalog has no `not-verified` entries, all declared compatible/adapted fixture checks pass, and that target's build and smoke both pass. Keep Web/mobile unsupported unless a separate validated runtime exists.
- [ ] Review the final diff against the approved spec and preserve every pre-existing user change and deletion; do not commit unless explicitly asked.
