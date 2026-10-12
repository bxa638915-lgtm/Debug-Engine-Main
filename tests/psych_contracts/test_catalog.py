import importlib.util
import json
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
VERIFY_PATH = ROOT / "tools" / "psych-compat" / "verify_contracts.py"


def load_verifier():
    spec = importlib.util.spec_from_file_location("verify_contracts", VERIFY_PATH)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def load_extractor():
    path = ROOT / "tools" / "psych-compat" / "extract_catalog.py"
    spec = importlib.util.spec_from_file_location("extract_catalog", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class CatalogValidationTests(unittest.TestCase):
    def setUp(self):
        self.verifier = load_verifier()

    def valid_function(self):
        return {
            "name": "makeLuaSprite",
            "kind": "function",
            "status": "not-verified",
            "signature": {"parameters": [], "variadic": False},
            "defaults": {},
            "return": {"type": "unknown", "conversion": "unknown"},
            "effects": [],
            "preconditions": [],
            "platform": {"targets": ["unknown"], "buildRequirements": []},
            "errors": {"behavior": "unknown"},
            "dbeBinding": {"status": "unclassified", "name": None},
            "fixtureId": None,
            "source": {"path": "source/psych.lua", "line": 1},
            "evidence": {"kind": "source", "note": "Source location extracted; behavior not yet reviewed."},
        }

    def test_missing_source_lock_is_rejected(self):
        with tempfile.TemporaryDirectory() as temp:
            self.assertFalse(self.verifier.validate_source_locks(Path(temp)))

    def test_lock_tag_and_commit_must_match_pinned_values(self):
        bad = {
            "sources": [{"profile": "0.6.3", "repository": "https://github.com/ShadowMario/FNF-PsychEngine.git", "tag": "0.6.2", "commit": "0" * 40, "snapshotSha256": "0" * 64}]
        }
        errors = self.verifier.validate_lock_data(bad)
        self.assertTrue(any("tag" in error or "commit" in error for error in errors))

    def test_invalid_contract_state_is_rejected(self):
        entry = self.valid_function()
        entry["status"] = "probably-compatible"
        self.assertTrue(self.verifier.validate_entry(entry, "function"))

    def test_missing_required_function_fields_are_rejected(self):
        required = ("signature", "defaults", "return", "effects", "errors", "platform", "evidence")
        for field in required:
            with self.subTest(field=field):
                entry = self.valid_function()
                del entry[field]
                self.assertTrue(self.verifier.validate_entry(entry, "function"))

    def test_duplicate_api_names_are_rejected(self):
        entry = self.valid_function()
        errors = self.verifier.validate_catalog_data({"functions": [entry, dict(entry)], "callbacks": []})
        self.assertTrue(any("duplicate" in error.lower() for error in errors))

    def test_catalog_entry_without_source_location_is_rejected(self):
        entry = self.valid_function()
        del entry["source"]
        self.assertTrue(self.verifier.validate_entry(entry, "function"))

    def test_callback_contract_requires_callback_fields_and_location(self):
        entry = {"name": "onCreate", "kind": "callback", "status": "not-verified", "source": {"path": "source/psych.lua", "line": 1}}
        self.assertTrue(self.verifier.validate_entry(entry, "callback"))

    def test_dbe_only_entry_requires_classification_and_binding_location(self):
        catalog = {
            "functions": [],
            "callbacks": [],
            "dbeOnly": [{"name": "getModSetting", "explanation": "DBE-only."}],
        }
        errors = self.verifier.validate_catalog_data(catalog)
        self.assertTrue(any("DBE-only" in error and "classification" in error for error in errors))

    def test_dbe_only_reconciliation_rejects_unlisted_registered_binding(self):
        catalogs = {
            "0.6.3": {"functions": [{"name": "makeLuaSprite"}], "dbeOnly": []},
            "1.0.4": {"functions": [{"name": "makeLuaSprite"}], "dbeOnly": []},
        }
        bindings = {"makeLuaSprite": 10, "getModSetting": 21}
        reconcile = getattr(self.verifier, "validate_dbe_only_reconciliation", lambda *_: [])
        errors = reconcile(catalogs, bindings)
        self.assertTrue(any("getModSetting" in error and "not listed" in error for error in errors))

    def test_profile_gated_binding_classification_is_valid(self):
        catalog = {
            "functions": [],
            "callbacks": [],
            "dbeOnly": [{
                "name": "getHits",
                "classification": "profile-gated-off",
                "explanation": "DBE declares the callback but gates registration to another profile.",
                "bindingSource": {"path": "source/funkin/backend/scripting/LuaScript.hx", "line": 10},
            }],
        }
        self.assertEqual([], self.verifier.validate_catalog_data(catalog))

    def test_callback_without_explicit_alias_is_classified_as_dynamic_fallback(self):
        extractor = load_extractor()
        entry = extractor._entry("onCustomEvent", "callback", "source/PlayState.hx", 42, set())
        self.assertEqual(entry["dbeBinding"]["status"], "dynamic")
        self.assertEqual(entry["dbeBinding"]["name"], "onCustomEvent")
        self.assertIn("passes", entry["dbeBinding"]["explanation"])

    def test_final_gate_rejects_not_verified_contracts(self):
        catalog = {
            "profile": "0.6.3",
            "functions": [self.valid_function()],
            "callbacks": [],
        }
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            manifest = root / "tests" / "fixtures" / "psych-lua" / "fixture-manifest.json"
            manifest.parent.mkdir(parents=True)
            manifest.write_text(json.dumps({"schemaVersion": 1, "fixtures": []}), encoding="utf-8")
            validate = getattr(self.verifier, "validate_final_evidence", lambda *_: [])
            errors = validate(root, {"0.6.3": catalog}, [])
        self.assertTrue(any("not-verified" in error and "makeLuaSprite" in error for error in errors))

    def test_final_gate_rejects_adapted_status_with_placeholder_contract_fields(self):
        entry = self.valid_function()
        entry.update({"status": "adapted", "fixtureId": "psych-0.6.3-lifecycle"})
        complete = getattr(self.verifier, "_contract_semantics_are_complete", lambda *_: True)
        self.assertFalse(complete(entry, "function"))

    def test_final_gate_requires_a_passing_fixture_result_for_adapted_contracts(self):
        entry = self.valid_function()
        entry.update({
            "status": "adapted",
            "fixtureId": "psych-0.6.3-lifecycle",
            "dbeBinding": {"status": "matched", "name": "makeLuaSprite"},
        })
        fixture_id = entry["fixtureId"]
        catalog = {"profile": "0.6.3", "functions": [entry], "callbacks": []}
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            script = root / "tests" / "fixtures" / "psych-lua" / "0.6.3" / "lifecycle.lua"
            script.parent.mkdir(parents=True)
            script.write_text("makeLuaSprite('fixture', 1, 1)\n", encoding="utf-8")
            manifest = root / "tests" / "fixtures" / "psych-lua" / "fixture-manifest.json"
            manifest.write_text(json.dumps({"schemaVersion": 1, "fixtures": [{
                "id": fixture_id,
                "profile": "0.6.3",
                "scriptPath": "tests/fixtures/psych-lua/0.6.3/lifecycle.lua",
                "physicalStatus": "present",
                "expectedMarkers": [f"DBE_PSYCH_FIXTURE_PASS:{fixture_id}"],
                "covers": {"apis": ["makeLuaSprite"], "callbacks": []},
            }]}), encoding="utf-8")
            runs = [{"builds": [{"target": "windows-x64", "luaEnabled": True, "status": "passed"}], "fixtureRuns": []}]
            validate = getattr(self.verifier, "validate_final_evidence", lambda *_: [])
            errors = validate(root, {"0.6.3": catalog}, runs)
        self.assertTrue(any("passing fixture result" in error and "makeLuaSprite" in error for error in errors))

    def test_final_gate_rejects_unclassified_source_api_mapping(self):
        entry = self.valid_function()
        entry["dbeBinding"] = {"status": "unclassified", "name": None}
        catalog = {"profile": "0.6.3", "functions": [entry], "callbacks": []}
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            manifest = root / "tests" / "fixtures" / "psych-lua" / "fixture-manifest.json"
            manifest.parent.mkdir(parents=True)
            manifest.write_text(json.dumps({"schemaVersion": 1, "fixtures": []}), encoding="utf-8")
            validate = getattr(self.verifier, "validate_final_evidence", lambda *_: [])
            errors = validate(root, {"0.6.3": catalog}, [])
        self.assertTrue(any("unclassified DBE mapping" in error and "makeLuaSprite" in error for error in errors))

    def test_profile_platform_claim_is_unvalidated_without_build_and_fixture_results(self):
        entry = self.valid_function()
        entry.update({"status": "incompatible", "evidence": {"kind": "fixture", "note": "Missing in DBE."}})
        catalog = {"profile": "0.6.3", "functions": [entry], "callbacks": []}
        claim = getattr(self.verifier, "profile_platform_claim", lambda *_: {"status": "supported"})(catalog, "windows-x64", [])
        self.assertEqual("unvalidated", claim["status"])

    def test_hscript_only_build_does_not_count_as_lua_enabled_platform_evidence(self):
        entry = self.valid_function()
        catalog = {"profile": "0.6.3", "functions": [entry], "callbacks": []}
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            build_log = root / "export" / "compat-tests" / "hscript-only-build.log"
            build_log.parent.mkdir(parents=True)
            build_log.write_text("Link: CodenameEngine-HScriptOnly.exe\n", encoding="utf-8")
            evidence = [{"builds": [{
                "target": "windows-x64",
                "luaEnabled": False,
                "status": "passed",
                "log": "export/compat-tests/hscript-only-build.log",
            }], "fixtureRuns": []}]
            claim = self.verifier.profile_platform_claim(catalog, "windows-x64", evidence, root)
        self.assertEqual("unvalidated", claim["status"])

    def test_profile_platform_claim_needs_every_contract_and_result_to_pass(self):
        entry = self.valid_function()
        entry.update({
            "status": "adapted",
            "fixtureId": "psych-0.6.3-lifecycle",
            "dbeBinding": {"status": "matched", "name": "makeLuaSprite"},
        })
        fixture_id = entry["fixtureId"]
        catalog = {"profile": "0.6.3", "functions": [entry], "callbacks": []}
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            script = root / "tests" / "fixtures" / "psych-lua" / "0.6.3" / "lifecycle.lua"
            script.parent.mkdir(parents=True)
            script.write_text("makeLuaSprite('fixture', 1, 1)\n", encoding="utf-8")
            manifest = root / "tests" / "fixtures" / "psych-lua" / "fixture-manifest.json"
            manifest.parent.mkdir(parents=True, exist_ok=True)
            manifest.write_text(json.dumps({"schemaVersion": 1, "fixtures": [{
                "id": fixture_id,
                "profile": "0.6.3",
                "scriptPath": "tests/fixtures/psych-lua/0.6.3/lifecycle.lua",
                "physicalStatus": "present",
                "expectedMarkers": [f"DBE_PSYCH_FIXTURE_PASS:{fixture_id}"],
                "expectedCallbackOrder": [],
                "covers": {"apis": ["makeLuaSprite"], "callbacks": []},
            }]}), encoding="utf-8")
            log = root / "export" / "compat-tests" / "fixture.log"
            log.parent.mkdir(parents=True)
            log.write_text(f"DBE_PSYCH_PROFILE:0.6.3\nDBE_PSYCH_FIXTURE_PASS:{fixture_id}\n", encoding="utf-8")
            build_log = root / "export" / "compat-tests" / "build.log"
            build_log.write_text("Link: ApplicationMain.exe\n", encoding="utf-8")
            runs = [{
                "builds": [{"target": "windows-x64", "luaEnabled": True, "status": "passed", "log": "export/compat-tests/build.log"}],
                "fixtureRuns": [{"profile": "0.6.3", "platform": "windows-x64", "fixtureIds": [fixture_id], "status": "passed", "stdoutLog": "export/compat-tests/fixture.log"}],
            }]
            claim = self.verifier.profile_platform_claim(catalog, "windows-x64", runs, root)
            self.assertEqual("supported", claim["status"])
            entry["status"] = "not-verified"
            claim = self.verifier.profile_platform_claim(catalog, "windows-x64", runs, root)
            self.assertEqual("blocked", claim["status"])
            entry["status"] = "incompatible"
            claim = self.verifier.profile_platform_claim(catalog, "windows-x64", runs, root)
            self.assertEqual("partial", claim["status"])

    def test_source_scanner_includes_lua_registrations_from_secondary_modules(self):
        extractor = load_extractor()
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            source = root / "psychlua" / "ReflectionFunctions.hx"
            source.parent.mkdir(parents=True)
            source.write_text(
                'Lua_helper.add_callback(lua, "getPropertyFromGroup", function() {});\n',
                encoding="utf-8",
            )
            inventory = extractor.scan_tree(root)
        names = {entry["name"] for entry in inventory["functions"]}
        self.assertIn("getPropertyFromGroup", names)


if __name__ == "__main__":
    unittest.main()
