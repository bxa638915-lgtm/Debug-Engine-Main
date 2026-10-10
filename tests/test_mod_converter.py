import json
import sys
import stat
import tempfile
import unittest
import zipfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))

from dbe_mod_converter import ConversionError, convert_mod


class ModConverterTest(unittest.TestCase):
    def setUp(self):
        self.temp_dir = tempfile.TemporaryDirectory()
        self.root = Path(self.temp_dir.name)

    def tearDown(self):
        self.temp_dir.cleanup()

    def test_normalizes_wrapped_psych_package_and_reports_preserved_scripts(self):
        source = self.root / "download"
        package = source / "Cool Mod"
        (package / "assets" / "data" / "cool-song").mkdir(parents=True)
        (package / "assets" / "images").mkdir(parents=True)
        (package / "scripts").mkdir()
        (package / "pack.json").write_text(
            json.dumps({"name": "Cool Mod", "dependencies": ["shared-assets"]}),
            encoding="utf-8",
        )
        (package / "assets" / "data" / "cool-song" / "chart.json").write_text("{}", encoding="utf-8")
        (package / "assets" / "images" / "background.png").write_bytes(b"png")
        (package / "scripts" / "modchart.lua").write_text("function onCreate() end", encoding="utf-8")
        output = self.root / "converted"

        report = convert_mod(source, output, source_format="psych")

        self.assertTrue((output / "data" / "cool-song" / "chart.json").is_file())
        self.assertTrue((output / "images" / "background.png").is_file())
        self.assertTrue((output / "scripts" / "modchart.lua").is_file())
        self.assertFalse((output / "assets").exists())
        self.assertTrue((package / "assets" / "data" / "cool-song" / "chart.json").is_file())
        self.assertEqual(report["sourceFormat"], "psych")
        self.assertIn("shared-assets", report["dependencies"])
        self.assertTrue(any(item["source"].endswith("modchart.lua") for item in report["converted"]))
        self.assertTrue(any("modchart.lua" in warning for warning in report["warnings"]))
        self.assertTrue(any(item["source"].endswith("chart.json") for item in report["converted"]))
        saved_report = json.loads((output / "_dbe_conversion_report.json").read_text(encoding="utf-8"))
        self.assertEqual(saved_report["sourceFormat"], "psych")

    def test_zip_package_normalizes_single_wrapper_directory(self):
        archive = self.root / "mod.zip"
        with zipfile.ZipFile(archive, "w") as package:
            package.writestr("MyMod/data/song/chart.json", "{}")
            package.writestr("MyMod/images/bg.png", b"png")
            package.writestr("MyMod/pack.json", '{"name":"MyMod"}')
        output = self.root / "from-zip"

        report = convert_mod(archive, output, source_format="psych")

        self.assertTrue((output / "data" / "song" / "chart.json").is_file())
        self.assertTrue((output / "images" / "bg.png").is_file())
        self.assertEqual(report["fileCount"], 3)

    def test_rejects_zip_path_traversal_before_creating_output(self):
        archive = self.root / "unsafe.zip"
        with zipfile.ZipFile(archive, "w") as package:
            package.writestr("../outside.txt", "bad")
            package.writestr("mod/data/chart.json", "{}")
        output = self.root / "unsafe-output"

        with self.assertRaises(ConversionError):
            convert_mod(archive, output, source_format="psych")

        self.assertFalse(output.exists())
        self.assertFalse((self.root / "outside.txt").exists())

    def test_rejects_windows_reserved_names_and_zip_symlinks(self):
        reserved_archive = self.root / "reserved.zip"
        with zipfile.ZipFile(reserved_archive, "w") as package:
            package.writestr("MyMod/data/CON.txt", "reserved")
        symlink_archive = self.root / "symlink.zip"
        link = zipfile.ZipInfo("MyMod/data/link")
        link.create_system = 3
        link.external_attr = (stat.S_IFLNK | 0o777) << 16
        with zipfile.ZipFile(symlink_archive, "w") as package:
            package.writestr(link, "../../outside")

        with self.subTest("reserved Windows filename"):
            with self.assertRaises(ConversionError):
                convert_mod(reserved_archive, self.root / "reserved-output", source_format="cne")
        with self.subTest("symbolic link"):
            with self.assertRaises(ConversionError):
                convert_mod(symlink_archive, self.root / "symlink-output", source_format="cne")

        self.assertFalse((self.root / "reserved-output").exists())
        self.assertFalse((self.root / "symlink-output").exists())

    def test_rejects_case_collisions_before_creating_output(self):
        source = self.root / "source.zip"
        with zipfile.ZipFile(source, "w") as package:
            package.writestr("MyMod/images/BG.png", b"one")
            package.writestr("MyMod/images/bg.png", b"two")
        output = self.root / "collision-output"

        with self.assertRaises(ConversionError):
            convert_mod(source, output, source_format="cne")

        self.assertFalse(output.exists())

    def test_rejects_ambiguous_source_format_without_modifying_source(self):
        source = self.root / "ambiguous"
        (source / "data").mkdir(parents=True)
        original = source / "data" / "chart.json"
        original.write_text("{}", encoding="utf-8")

        with self.assertRaises(ConversionError):
            convert_mod(source, self.root / "out", source_format="auto")

        self.assertEqual(original.read_text(encoding="utf-8"), "{}")

    def test_auto_detects_vslice_from_polymod_api_metadata(self):
        source = self.root / "vslice"
        package = source / "Sample Mod"
        (package / "data").mkdir(parents=True)
        (package / "_polymod_meta.json").write_text(
            '{"api_version":"0.8.0","title":"Sample Mod"}', encoding="utf-8"
        )
        (package / "data" / "song.json").write_text("{}", encoding="utf-8")

        report = convert_mod(source, self.root / "vslice-output", source_format="auto")

        self.assertEqual(report["sourceFormat"], "vslice")

    def test_preserves_files_outside_the_detected_package_root(self):
        source = self.root / "release"
        package = source / "MyMod"
        (package / "data").mkdir(parents=True)
        (package / "pack.json").write_text('{"name":"MyMod"}', encoding="utf-8")
        (package / "data" / "chart.json").write_text("{}", encoding="utf-8")
        (source / "_polymod_meta.json").write_text('{"dependencies":["external-only"]}', encoding="utf-8")
        readme = source / "README.txt"
        readme.write_text("Package notes", encoding="utf-8")
        output = self.root / "preserved-output"

        report = convert_mod(source, output, source_format="auto")

        self.assertEqual((output / "_dbe_preserved" / "README.txt").read_text(encoding="utf-8"), "Package notes")
        self.assertTrue(any(item["source"] == "README.txt" for item in report["retained"]))
        self.assertEqual(report["dependencies"], [])

    def test_refuses_to_replace_a_source_conversion_report(self):
        source = self.root / "source-with-report"
        (source / "data").mkdir(parents=True)
        (source / "data" / "chart.json").write_text("{}", encoding="utf-8")
        report_path = source / "_dbe_conversion_report.json"
        report_path.write_text("keep this source file", encoding="utf-8")
        output = self.root / "report-collision"

        with self.assertRaises(ConversionError):
            convert_mod(source, output, source_format="cne")

        self.assertEqual(report_path.read_text(encoding="utf-8"), "keep this source file")

    def test_refuses_to_overwrite_existing_output_or_write_inside_source(self):
        source = self.root / "source"
        (source / "data").mkdir(parents=True)
        (source / "data" / "chart.json").write_text("{}", encoding="utf-8")
        existing = self.root / "existing"
        existing.mkdir()

        with self.assertRaises(ConversionError):
            convert_mod(source, existing, source_format="cne")
        with self.assertRaises(ConversionError):
            convert_mod(source, source / "converted", source_format="cne")


if __name__ == "__main__":
    unittest.main()
