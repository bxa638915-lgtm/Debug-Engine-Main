# Psych Lua behavior fixtures

`fixture-manifest.json` is the registry for both Psych profiles. A declaration reserves its ID, profile, script path, covered APIs/callbacks, expected output markers, and callback order. `physicalStatus: "pending"` means the Lua file has not been added or run yet; it is not compatibility evidence.

## Fixture output contract

Each script must use `debugPrint` to emit:

- `DBE_PSYCH_PROFILE:<profile>` after checking `engine.compatibility.psychLuaProfile` reports the selected profile.
- `DBE_PSYCH_FIXTURE_PASS:<fixture-id>` only after all assertions in that fixture pass.
- `DBE_PSYCH_CALLBACK:<fixture-id>:<callback-name>` for callbacks whose order is declared in `expectedCallbackOrder`. The manifest stores callback names in the exact expected sequence; the fixture ID keeps markers distinct when several scripts run together.
- `DBE_PSYCH_LUA_ERROR:<details>` when a fixture catches or reports a Lua-side failure. The gameplay runner treats this marker as a failure, along with engine Lua load/callback error messages.

Keep each fixture deterministic and limited to its declared `covers` list. Callback markers outside `expectedCallbackOrder` are allowed when the fixture does not assert callback ordering.

## Runner

From the engine project root, run `./building/psych-lua-test.ps1 -ValidateOnly` to validate catalogs, manifest declarations, and the Python contract suite. This mode deliberately does not require the physical Lua scripts.

After the owning tasks add and mark scripts `present`, run `./building/psych-lua-test.ps1 -BuildEngine -GameplaySmoke -Profiles 0.6.3,1.0.4`. `-GameplaySmoke` refuses pending or missing scripts, creates a uniquely named temporary mod under the Windows release build's `mods` directory, captures logs under `export/compat-tests/`, and removes only the mod it created. Use `-FixtureIds <id,...>` to narrow a smoke run.

## Evidence status

All currently listed Lua fixtures are present. A passing fixture proves only the assertions and callbacks it executes; `covers.apis` alone records call coverage, not a complete signature/default/error contract. The final build and gameplay runs are recorded in `export/compat-tests/psych-lua-evidence-*.json` and summarized in `docs/compatibility/COMPATIBILITY-EVIDENCE.md`. The two profile catalogs remain the source of truth for whether an individual contract is verified.
