import importlib.util
import json
import re
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


class FixtureCoverageTests(unittest.TestCase):
    def setUp(self):
        self.verifier = load_verifier()

    def validate(self, entries, fixtures):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            manifest_path = root / "tests" / "fixtures" / "psych-lua" / "fixture-manifest.json"
            manifest_path.parent.mkdir(parents=True)
            manifest_path.write_text(json.dumps({"schemaVersion": 1, "fixtures": fixtures}), encoding="utf-8")
            catalogs = {"0.6.3": {"functions": entries, "callbacks": []}}
            return self.verifier.validate_manifest(root, catalogs)

    @staticmethod
    def function(name="makeLuaSprite", status="not-verified", fixture_id=None):
        return {"name": name, "status": status, "fixtureId": fixture_id}

    @staticmethod
    def fixture(fixture_id="psych-0.6.3-lifecycle", profile="0.6.3", script_path=None, apis=None, callbacks=None):
        return {
            "id": fixture_id,
            "profile": profile,
            "scriptPath": script_path or f"tests/fixtures/psych-lua/{profile}/lifecycle.lua",
            "covers": {"apis": apis or [], "callbacks": callbacks or []},
            "physicalStatus": "pending",
        }

    def test_compatible_function_without_manifest_fixture_is_rejected(self):
        errors = self.validate([self.function(status="compatible")], [])
        self.assertTrue(any("makeLuaSprite" in error and "missing required fixture" in error for error in errors))

    def test_fixture_id_absent_from_manifest_is_rejected(self):
        errors = self.validate([self.function(fixture_id="missing-fixture")], [])
        self.assertTrue(any("unresolved or wrong-profile fixture missing-fixture" in error for error in errors))

    def test_fixture_must_declare_the_api_it_covers(self):
        fixture = self.fixture(apis=[])
        errors = self.validate([self.function(fixture_id=fixture["id"])], [fixture])
        self.assertTrue(any("makeLuaSprite" in error and "does not cover" in error for error in errors))

    def test_fixture_path_profile_mismatch_is_rejected(self):
        fixture = self.fixture(profile="0.6.3", script_path="tests/fixtures/psych-lua/1.0.4/lifecycle.lua")
        errors = self.validate([], [fixture])
        self.assertTrue(any("script path does not match profile" in error for error in errors))

    def test_fixture_requires_expected_markers_and_callback_order(self):
        errors = self.validate([], [self.fixture()])
        self.assertTrue(any("expectedMarkers" in error for error in errors))
        self.assertTrue(any("expectedCallbackOrder" in error for error in errors))

    @staticmethod
    def missing_api_calls(root, fixture):
        script_path = root / fixture["scriptPath"]
        source = re.sub(r"--[^\n]*", "", script_path.read_text(encoding="utf-8"))
        return [
            api
            for api in fixture.get("covers", {}).get("apis", [])
            if not re.search(r"(?<![\w.])" + re.escape(api) + r"\s*\(", source)
        ]

    def test_present_fixture_must_call_every_declared_api(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            script = root / "tests/fixtures/psych-lua/0.6.3/lifecycle.lua"
            script.parent.mkdir(parents=True)
            script.write_text("makeGraphic('fixture', 1, 1)\n", encoding="utf-8")
            fixture = self.fixture(apis=["makeLuaSprite"])
            missing = self.missing_api_calls(root, fixture)
            self.assertEqual(["makeLuaSprite"], missing)

    def test_present_task_four_fixtures_call_every_declared_api(self):
        manifest_path = ROOT / "tests/fixtures/psych-lua/fixture-manifest.json"
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        errors = []
        for fixture in manifest["fixtures"]:
            if fixture.get("ownerTask") != 4 or fixture.get("physicalStatus") != "present":
                continue
            observed = fixture.get("covers", {}).get("observedApis", [])
            call_fixture = {**fixture, "covers": {"apis": observed}}
            missing = self.missing_api_calls(ROOT, call_fixture)
            if missing:
                errors.append(f"{fixture['id']} lists observed APIs without calls: {', '.join(missing)}")
        self.assertEqual([], errors, "\n".join(errors))

    def test_present_task_five_fixtures_call_apis_and_define_callbacks(self):
        manifest_path = ROOT / "tests" / "fixtures" / "psych-lua" / "fixture-manifest.json"
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        errors = []
        for fixture in manifest["fixtures"]:
            if fixture.get("ownerTask") != 5 or fixture.get("physicalStatus") != "present":
                continue
            missing = self.missing_api_calls(ROOT, fixture)
            if missing:
                errors.append(f"{fixture['id']} lists APIs without calls: {', '.join(missing)}")
            script = (ROOT / fixture["scriptPath"]).read_text(encoding="utf-8")
            for callback in fixture.get("covers", {}).get("callbacks", []):
                if not re.search(r"\bfunction\s+" + re.escape(callback) + r"\s*\(", script):
                    errors.append(f"{fixture['id']} lists callback without a function: {callback}")
        self.assertEqual([], errors, "\n".join(errors))


if __name__ == "__main__":
    unittest.main()
