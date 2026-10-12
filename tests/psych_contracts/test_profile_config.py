import json
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
FIXTURE_ROOT = ROOT / "tests" / "fixtures" / "psych-lua"
MANIFEST = FIXTURE_ROOT / "fixture-manifest.json"


class PsychProfileFixtureConfigTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.fixtures = json.loads(MANIFEST.read_text(encoding="utf-8"))["fixtures"]
        cls.by_id = {fixture["id"]: fixture for fixture in cls.fixtures}

    def test_selected_profile_fixtures_declare_both_supported_versions(self):
        for profile in ("0.6.3", "1.0.4"):
            fixture_id = f"psych-{profile}-profile-selection"
            fixture = self.by_id[fixture_id]
            self.assertEqual(profile, fixture["profile"])
            self.assertEqual(profile, fixture["expectedProfile"])
            self.assertEqual("selected", fixture["configScenario"])

    def test_unspecified_profile_fixtures_cover_missing_malformed_and_unsupported_config(self):
        cases = {
            "missing": "psych-profile-unspecified-no-config",
            "malformed": "psych-profile-unspecified-malformed",
            "unsupported": "psych-profile-unspecified-unsupported",
        }
        for scenario, fixture_id in cases.items():
            fixture = self.by_id[fixture_id]
            self.assertEqual("unspecified", fixture["profile"])
            self.assertEqual("unspecified", fixture["expectedProfile"])
            self.assertEqual(scenario, fixture["configScenario"])

    def test_profile_config_inputs_and_lua_markers_match_each_scenario(self):
        scenarios = [
            self.by_id["psych-0.6.3-profile-selection"],
            self.by_id["psych-1.0.4-profile-selection"],
            self.by_id["psych-profile-unspecified-no-config"],
            self.by_id["psych-profile-unspecified-malformed"],
            self.by_id["psych-profile-unspecified-unsupported"],
        ]
        for fixture in scenarios:
            with self.subTest(fixture=fixture["id"]):
                scenario = fixture["configScenario"]
                config_text = fixture.get("configText")
                if scenario == "selected":
                    self.assertIsNone(config_text)
                elif scenario == "missing":
                    self.assertIsNone(config_text)
                elif scenario == "malformed":
                    with self.assertRaises(json.JSONDecodeError):
                        json.loads(config_text)
                elif scenario == "unsupported":
                    self.assertNotIn(json.loads(config_text)["psychLuaProfile"], ("0.6.3", "1.0.4"))
                else:
                    self.fail(f"unexpected config scenario: {scenario}")

                script_path = ROOT / fixture["scriptPath"]
                self.assertTrue(script_path.is_file(), f"fixture script is missing: {script_path}")
                script = script_path.read_text(encoding="utf-8")
                self.assertIn("engine.compatibility.psychLuaProfile", script)
                for marker in fixture["expectedMarkers"]:
                    script_marker = "DBE_PSYCH_PROFILE:" if marker.startswith("DBE_PSYCH_PROFILE:") else marker
                    self.assertIn(script_marker, script)


if __name__ == "__main__":
    unittest.main()
