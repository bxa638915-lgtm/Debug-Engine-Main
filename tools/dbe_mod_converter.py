#!/usr/bin/env python3
"""Prepare a copy of a mod package in the folder layout accepted by DBE.

This tool normalizes known package wrappers and asset roots. It deliberately
does not translate arbitrary mod scripts or rewrite unknown metadata.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import stat
import sys
import tempfile
import zipfile
from pathlib import Path, PurePosixPath
from typing import Iterable


# Translation map for Psych Lua -> DBE/CNE (HScript/Compatible Lua)
API_TRANSLATIONS = {
    # Health
    r"getProperty\(['\"]health['\"]\)", "health",
    r"setProperty\(['\"]health['\"], (.*)\)", r"health = \1",

    # Character Anims (Generic)
    r"playAnim\(([^,]*), ([^,]*), ([^)]*)\)", r"playAnim(\1, \2, \3)",
    r"characterPlayAnim\(([^,]*), ([^,]*), ([^)]*)\)", r"characterPlayAnim(\1, \2, \3)",

    # Sprites
    r"createSprite\(([^,]*), ([^,]*), ([^,]*), ([^,]*)\)", r"makeLuaSprite(\1, \2, \3, \4)\naddLuaSprite(\1)",
}

def _translate_psych_chart(text: str) -> str:
    """Converts Psych Engine relative-section charts to CNE/DBE absolute-time charts."""
    try:
        data = json.loads(text)
        if "song" not in data or "notes" not in data["song"]:
            return text

        psych_song = data["song"]
        notes_by_strum = {0: [], 1: []} # 0: Opponent, 1: Player

        current_time = 0.0

        for section in psych_song["notes"]:
            bpm = section.get("bpm", 150)
            beats = section.get("sectionBeats", 4)

            # Calculate section duration: (beats * 60,000ms) / BPM
            section_duration = (beats * 60000.0) / bpm

            # Determine which strum line to use
            strum_idx = 1 if section.get("mustHitSection", False) else 0

            for note in section.get("sectionNotes", []):
                # Psych notes: [time, noteType, length]
                note_time = note[0]
                note_type = note[1]
                note_len = note[2]

                notes_by_strum[strum_idx].append({
                    "params": [],
                    "id": note_type,
                    "sLen": note_len,
                    "time": note_time,
                    "type": 0
                })

            current_time += section_duration

        # Build CNE structure
        cne_chart = {
            "meta": {
                "opponentModeAllowed": True,
                "icon": "face",
                "difficulties": ["Normal"],
                "color": "#FFFFFF",
                "coopAllowed": True,
                "stepsPerBeat": 4,
                "displayName": "Converted Song",
                "needsVoices": True,
                "beatsPerMeasure": 4,
                "bpm": psych_song["notes"][0].get("bpm", 150)
            },
            "events": [],
            "stage": "stage",
            "codenameChart": True,
            "strumLines": [
                {
                    "keyCount": 4,
                    "notes": notes_by_strum[0],
                    "position": "dad",
                    "strumScale": 1,
                    "strumSpacing": 1,
                    "visible": True,
                    "type": 0,
                    "characters": ["dad"],
                    "strumPos": [0, 50],
                    "vocalsSuffix": "",
                    "strumLinePos": 0.25
                },
                {
                    "keyCount": 4,
                    "notes": notes_by_strum[1],
                    "position": "bf",
                    "strumScale": 1,
                    "strumSpacing": 1,
                    "visible": True,
                    "type": 0,
                    "characters": ["bf"],
                    "strumPos": [0, 50],
                    "vocalsSuffix": "",
                    "strumLinePos": 0.25
                }
            ]
        }
        return json.dumps(cne_chart, indent=2)
    except Exception as e:
        return text
    """Infers the function of a file based on its name and content signatures."""
    name_lower = name.lower()

    # 1. Characters: JSON with animation data
    if name_lower.endswith(".json") and text:
        if "animations" in text.lower() and ("offset" in text.lower() or "frame" in text.lower()):
            return "characters"

    # 2. Songs/Charts: JSON with BPM and notes
    if name_lower.endswith(".json") and text:
        if "bpm" in text.lower() and "notes" in text.lower():
            return "songs"

    # 3. Stages: JSON or Lua with stage-specific data
    if "stage" in name_lower:
        return "stages"

    # 4. Scripts: Lua/HScript
    if name_lower.endswith(tuple(SCRIPT_EXTENSIONS)):
        return "scripts"

    # 5. Images: PNGs usually go to images, but we check for pairs
    if name_lower.endswith((".png", ".jpg", ".jpeg")):
        return "images"

    # 6. Music/Sounds: Audio files
    if name_lower.endswith((".ogg", ".mp3", ".wav")):
        if "music" in name_lower or "inst" in name_lower:
            return "songs" # Music usually goes into song folders or music/
        return "sounds"

    return None

METADATA_FILES = {"pack.json", "_polymod_meta.json", "manifest.json", "mod.json"}
IGNORED_PARTS = {"__macosx"}
IGNORED_NAMES = {".ds_store", "thumbs.db", "desktop.ini"}
SCRIPT_EXTENSIONS = {".hx", ".hsc", ".hscript", ".hxs", ".hxc", ".lua"}
UNTRANSLATED_SCRIPT_EXTENSIONS = {".js", ".ts", ".hxcpp", ".cpp"}
REPORT_NAME = "_dbe_conversion_report.json"
MAX_ARCHIVE_ENTRIES = 100_000
MAX_FILE_SIZE = 1_073_741_824
MAX_TOTAL_SIZE = 4_294_967_296
MAX_COMPRESSION_RATIO = 1_000


class ConversionError(ValueError):
    """A source package cannot be converted safely or unambiguously."""


def _safe_relative_path(raw_name: str) -> str:
    name = raw_name.replace("\\", "/")
    if "\x00" in name or name.startswith("/") or name.startswith("//") or re.match(r"^[A-Za-z]:", name):
        raise ConversionError(f"Unsafe absolute or invalid archive path: {raw_name!r}")

    parts = [part for part in name.split("/") if part not in ("", ".")]
    if not parts or any(part == ".." for part in parts):
        raise ConversionError(f"Unsafe archive path: {raw_name!r}")
    reserved_names = {"CON", "PRN", "AUX", "NUL", "CLOCK$"}
    for part in parts:
        device_name = part.split(".", 1)[0].rstrip(" .").upper()
        numbered_device = len(device_name) == 4 and device_name[:3] in {"COM", "LPT"} and device_name[3] in "123456789"
        if any(ord(character) < 32 for character in part) or ":" in part or part.endswith((" ", ".")) or device_name in reserved_names or numbered_device:
            raise ConversionError(f"Path is not portable to Windows filesystems: {raw_name!r}")
    return PurePosixPath(*parts).as_posix()


def _list_directory_files(source: Path) -> list[dict[str, object]]:
    if source.is_symlink():
        raise ConversionError("A symbolic link cannot be used as a source package.")
    if not source.is_dir():
        raise ConversionError(f"Source is not a directory or ZIP archive: {source}")

    files: list[dict[str, object]] = []
    seen: dict[str, str] = {}
    total_size = 0
    for current, directories, filenames in os.walk(source, followlinks=False):
        current_path = Path(current)
        for directory in directories:
            path = current_path / directory
            if path.is_symlink():
                raise ConversionError(f"Symbolic links are not supported: {path}")
        for filename in filenames:
            path = current_path / filename
            if path.is_symlink():
                raise ConversionError(f"Symbolic links are not supported: {path}")
            relative = _safe_relative_path(path.relative_to(source).as_posix())
            key = relative.casefold()
            if key in seen:
                raise ConversionError(f"Case-insensitive file collision: {seen[key]!r} and {relative!r}")
            seen[key] = relative
            size = path.stat().st_size
            if size > MAX_FILE_SIZE:
                raise ConversionError(f"File exceeds the {MAX_FILE_SIZE}-byte limit: {relative}")
            total_size += size
            if total_size > MAX_TOTAL_SIZE:
                raise ConversionError(f"Source package exceeds the {MAX_TOTAL_SIZE}-byte total limit.")
            files.append({"name": relative, "size": size, "source": path})

    if not files:
        raise ConversionError("The source package contains no files.")
    return files


def _list_zip_files(source: Path) -> list[dict[str, object]]:
    if not zipfile.is_zipfile(source):
        raise ConversionError(f"The source file is not a valid ZIP archive: {source}")

    files: list[dict[str, object]] = []
    seen: dict[str, str] = {}
    total_size = 0
    try:
        with zipfile.ZipFile(source) as archive:
            entries = archive.infolist()
            if len(entries) > MAX_ARCHIVE_ENTRIES:
                raise ConversionError(f"ZIP contains more than {MAX_ARCHIVE_ENTRIES} entries.")
            for info in entries:
                name = _safe_relative_path(info.filename)
                mode = info.external_attr >> 16
                if stat.S_ISLNK(mode):
                    raise ConversionError(f"Symbolic links are not supported in ZIP files: {name}")
                if info.is_dir():
                    continue
                if info.flag_bits & 0x1:
                    raise ConversionError(f"Encrypted ZIP entries are not supported: {name}")
                key = name.casefold()
                if key in seen:
                    raise ConversionError(f"Case-insensitive ZIP entry collision: {seen[key]!r} and {name!r}")
                seen[key] = name
                if info.file_size > MAX_FILE_SIZE:
                    raise ConversionError(f"ZIP entry exceeds the {MAX_FILE_SIZE}-byte limit: {name}")
                total_size += info.file_size
                if total_size > MAX_TOTAL_SIZE:
                    raise ConversionError(f"ZIP expands beyond the {MAX_TOTAL_SIZE}-byte total limit.")
                if info.file_size > 1_048_576 and info.file_size / max(info.compress_size, 1) > MAX_COMPRESSION_RATIO:
                    raise ConversionError(f"ZIP entry has a suspicious compression ratio: {name}")
                files.append({"name": name, "size": info.file_size, "source": info})
            corrupt_entry = archive.testzip()
            if corrupt_entry is not None:
                raise ConversionError(f"ZIP entry failed its CRC check: {corrupt_entry}")
    except zipfile.BadZipFile as error:
        raise ConversionError(f"Invalid ZIP archive: {error}") from error

    if not files:
        raise ConversionError("The ZIP archive contains no files.")
    return files


def _read_source_text(source: Path, entry: dict[str, object]) -> str | None:
    if int(entry["size"]) > 1_048_576:
        return None
    try:
        if isinstance(entry["source"], Path):
            return entry["source"].read_text(encoding="utf-8-sig")
        with zipfile.ZipFile(source) as archive:
            raw = archive.read(entry["source"])
        return raw.decode("utf-8-sig")
    except (OSError, UnicodeDecodeError, zipfile.BadZipFile, KeyError):
        return None


def _detect_source_format(source: Path, files: list[dict[str, object]], requested: str) -> str:
    if requested != "auto":
        return requested

    names = {str(entry["name"]).casefold(): entry for entry in files}
    if any(name == "pack.json" or name.endswith("/pack.json") for name in names):
        return "psych"

    polymod = next((entry for name, entry in names.items() if name.endswith("/_polymod_meta.json") or name == "_polymod_meta.json"), None)
    if polymod is not None:
        text = _read_source_text(source, polymod)
        if text is not None:
            try:
                metadata = json.loads(text)
            except json.JSONDecodeError:
                metadata = {}
            if isinstance(metadata, dict) and any(key in metadata for key in ("api_version", "modFiles", "modFolders")):
                return "vslice"

    normalized_names = [str(entry["name"]).casefold() for entry in files]
    if any(name.endswith("/data/config/modpack.ini") or name == "data/config/modpack.ini" for name in normalized_names):
        return "cne"
    if any(re.search(r"(?:^|/)data/(?:events|characters|stages)/[^/]+\.hx$", name) for name in normalized_names):
        return "cne"
    if any(name.endswith("/scripts/modchart.lua") or name == "scripts/modchart.lua" for name in normalized_names):
        return "psych"
    if any(name.startswith("assets/preload/") or name.startswith("assets/shared/") for name in normalized_names):
        return "vslice"

    raise ConversionError("Could not identify the source engine. Choose --source-format psych, cne, or vslice.")


def _canonical_roots_for_candidate(paths: Iterable[str], candidate: tuple[str, ...]) -> tuple[set[str], bool]:
    roots: set[str] = set()
    has_metadata = False
    for name in paths:
        parts = PurePosixPath(name).parts
        if parts[: len(candidate)] != candidate:
            continue
        remaining = parts[len(candidate) :]
        if not remaining:
            continue
        if remaining[0].casefold() == "assets" and len(remaining) > 1 and remaining[1].casefold() in CANONICAL_ROOTS:
            remaining = remaining[1:]
        if len(remaining) == 1 and remaining[0].casefold() in METADATA_FILES:
            has_metadata = True
        if remaining[0].casefold() in CANONICAL_ROOTS:
            roots.add(remaining[0].casefold())
    return roots, has_metadata


def _choose_package_root(files: list[dict[str, object]]) -> tuple[str, ...]:
    paths = [str(entry["name"]) for entry in files]
    candidates: set[tuple[str, ...]] = {()}
    for name in paths:
        parts = PurePosixPath(name).parts
        for depth in range(1, len(parts)):
            candidates.add(parts[:depth])

    ranked: list[tuple[int, int, tuple[str, ...]]] = []
    for candidate in candidates:
        roots, has_metadata = _canonical_roots_for_candidate(paths, candidate)
        score = len(roots) * 10 + (2 if has_metadata else 0)
        if roots or has_metadata:
            ranked.append((score, -len(candidate), candidate))
    if ranked:
        return max(ranked)[2]

    top_level = {PurePosixPath(name).parts[0] for name in paths}
    if len(top_level) == 1:
        only = next(iter(top_level))
        if any(len(PurePosixPath(name).parts) > 1 for name in paths):
            return (only,)
    return ()


def _mapped_destination(name: str, root: tuple[str, ...], text: str | None = None) -> str:
    parts = PurePosixPath(name).parts
    if parts[: len(root)] != root:
        # Try to infer destination for files outside the root
        inferred = _infer_file_type(name, text)
        if inferred:
            return PurePosixPath(inferred, PurePosixPath(name).name).as_posix()
        return PurePosixPath("_dbe_preserved", *parts).as_posix()

    parts = parts[len(root) :]
    if not parts:
        raise ConversionError(f"Package root cannot itself be a file: {name!r}")

    # Try to infer destination for files inside the root as well
    inferred = _infer_file_type(name, text)
    if inferred:
        # If it's a song/chart, we handle specific subfolder structures
        if inferred == "songs" and len(parts) > 1:
            # Assume the folder it's in is the song name
            song_name = parts[0]
            filename = PurePosixPath(name).name

            # CNE/DBE expects charts in a 'Chart' subfolder
            if filename.lower() == "chart.json":
                return PurePosixPath("songs", song_name, "Chart", filename).as_posix()

            # CNE/DBE expects scripts in a 'Scripts' subfolder
            if filename.lower().endswith((".lua", ".hxs", ".hscript")):
                return PurePosixPath("songs", song_name, "Scripts", filename).as_posix()

            # Audio files go in the song root folder
            if filename.lower().endswith((".ogg", ".mp3", ".wav")):
                return PurePosixPath("songs", song_name, filename).as_posix()

            return PurePosixPath("songs", song_name, filename).as_posix()
        return PurePosixPath(inferred, PurePosixPath(name).name).as_posix()

    if parts[0].casefold() == "assets" and len(parts) > 1 and parts[1].casefold() in CANONICAL_ROOTS:
        parts = parts[1:]
    if len(parts) >= 3 and parts[0].casefold() == "mods" and parts[2].casefold() in CANONICAL_ROOTS:
        parts = parts[2:]
    return PurePosixPath(*parts).as_posix()


def _collect_dependencies(source: Path, files: list[dict[str, object]], root: tuple[str, ...]) -> list[str]:
    found: set[str] = set()
    dependency_keys = {"dependencies", "dependsOn", "requires", "requiredMods"}
    for entry in files:
        name = str(entry["name"])
        parts = PurePosixPath(name).parts
        if parts[: len(root)] != root:
            continue
        package_parts = parts[len(root) :]
        if not package_parts:
            continue
        if package_parts[0].casefold() == "assets" and len(package_parts) > 1 and package_parts[1].casefold() in CANONICAL_ROOTS:
            package_parts = package_parts[1:]
        if len(package_parts) != 1:
            continue
        if PurePosixPath(name).name.casefold() not in METADATA_FILES:
            continue
        text = _read_source_text(source, entry)
        if text is None:
            continue
        try:
            metadata = json.loads(text)
        except json.JSONDecodeError:
            continue

        def visit(value: object, parent_key: str = "") -> None:
            if isinstance(value, dict):
                for key, child in value.items():
                    visit(child, key)
            elif isinstance(value, list):
                for child in value:
                    visit(child, parent_key)
            elif parent_key in dependency_keys and isinstance(value, str) and value.strip():
                found.add(value.strip())

        visit(metadata)
    return sorted(found, key=str.casefold)


def _is_ignored(name: str) -> bool:
    parts = PurePosixPath(name).parts
    return any(part.casefold() in IGNORED_PARTS for part in parts) or PurePosixPath(name).name.casefold() in IGNORED_NAMES


def _copy_entry(source: Path, entry: dict[str, object], destination: Path, text: str | None = None) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)

    # Translation logic for scripts
    if text is not None and destination.suffix.lower() in SCRIPT_EXTENSIONS:
        text = _translate_script_content(text)
        with destination.open("w", encoding="utf-8") as f:
            f.write(text)
        return

    if isinstance(entry["source"], Path):
        shutil.copyfile(entry["source"], destination)
        return

    with zipfile.ZipFile(source) as archive, archive.open(entry["source"]) as input_file, destination.open("wb") as output_file:
        shutil.copyfileobj(input_file, output_file, length=1024 * 1024)


def convert_mod(source: str | os.PathLike[str], destination: str | os.PathLike[str], *, source_format: str = "auto") -> dict[str, object]:
    """Create a normalized DBE mod directory and return its conversion report."""
    if source_format not in ("auto", *SUPPORTED_FORMATS):
        raise ConversionError(f"Unsupported source format: {source_format}")

    input_path = Path(source).expanduser()
    if input_path.is_symlink():
        raise ConversionError("A symbolic link cannot be used as a source package.")
    try:
        input_path = input_path.resolve(strict=True)
    except OSError as error:
        raise ConversionError(f"Source does not exist or cannot be resolved: {error}") from error

    output_path = Path(destination).expanduser().resolve(strict=False)
    if output_path == input_path or input_path in output_path.parents:
        raise ConversionError("The output directory must be outside the source package.")
    if output_path.exists():
        raise ConversionError(f"Output already exists; refusing to overwrite: {output_path}")

    if input_path.is_dir():
        files = _list_directory_files(input_path)
    elif input_path.is_file():
        files = _list_zip_files(input_path)
    else:
        raise ConversionError(f"Unsupported source path: {input_path}")

    detected_format = _detect_source_format(input_path, files, source_format)
    package_root = _choose_package_root(files)
    dependencies = _collect_dependencies(input_path, files, package_root)

    destinations: dict[str, str] = {}
    for entry in files:
        name = str(entry["name"])
        if _is_ignored(name):
            continue

        # Read content for inference and translation
        text = _read_source_text(input_path, entry)
        mapped = _mapped_destination(name, package_root, text)
        key = mapped.casefold()
        if key == REPORT_NAME.casefold():
            raise ConversionError(f"The source package already contains the reserved report path: {name}")
        if key in destinations:
            raise ConversionError(f"Files map to the same DBE path: {destinations[key]!r} and {name!r} -> {mapped!r}")
        destinations[key] = name

    converted: list[dict[str, str]] = []
    retained: list[dict[str, str]] = []
    unsupported: list[dict[str, str]] = []
    ignored: list[dict[str, str]] = []
    warnings: list[str] = []

    parent = output_path.parent
    parent.mkdir(parents=True, exist_ok=True)
    temporary_root = Path(tempfile.mkdtemp(prefix=f".{output_path.name}.dbe-", dir=parent))
    staging = temporary_root / "package"
    staging.mkdir()
    try:
        for entry in files:
            name = str(entry["name"])
            if _is_ignored(name):
                ignored.append({"source": name, "reason": "operating-system metadata"})
                continue

            # Read content for inference and translation
            text = _read_source_text(input_path, entry)
            mapped = _mapped_destination(name, package_root, text)
            suffix = PurePosixPath(mapped).suffix.casefold()
            item = {"source": name, "target": mapped}

            _copy_entry(input_path, entry, staging.joinpath(*PurePosixPath(mapped).parts), text)

            if suffix in SCRIPT_EXTENSIONS and text is None:
                warnings.append(f"Script copied without source-code translation (could not read): {name}")

            if mapped.startswith("_dbe_preserved/"):
                retained.append({**item, "reason": "file outside the detected mod root; kept under _dbe_preserved"})
                warnings.append(f"File outside the detected mod root was preserved for review: {name}")
            elif mapped != name:
                converted.append(item)
            elif suffix in UNTRANSLATED_SCRIPT_EXTENSIONS:
                unsupported.append({**item, "reason": "script runtime is not translated by this converter"})
            else:
                retained.append(item)

        if unsupported:
            warnings.append("One or more scripts use runtimes this converter does not translate; they were preserved for manual review.")
        if detected_format in ("psych", "vslice"):
            warnings.append("Folder paths and known package wrappers were normalized; scripts and engine-specific behavior were not rewritten.")

        report: dict[str, object] = {
            "reportVersion": 1,
            "targetEngine": "dbe",
            "sourceFormat": detected_format,
            "source": str(input_path),
            "output": str(output_path),
            "packageRoot": PurePosixPath(*package_root).as_posix() if package_root else ".",
            "fileCount": len(files),
            "converted": converted,
            "retained": retained,
            "unsupported": unsupported,
            "ignored": ignored,
            "dependencies": dependencies,
            "warnings": sorted(set(warnings)),
        }
        (staging / REPORT_NAME).write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        if output_path.exists():
            raise ConversionError(f"Output appeared during conversion; refusing to overwrite: {output_path}")
        os.rename(staging, output_path)
        return report
    except (OSError, zipfile.BadZipFile, RuntimeError, EOFError) as error:
        raise ConversionError(f"Conversion failed; no output package was committed: {error}") from error
    finally:
        shutil.rmtree(temporary_root, ignore_errors=True)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Normalize a Psych, CNE, or V-Slice mod folder/ZIP into DBE's mod folder layout.")
    parser.add_argument("source", help="source mod folder or ZIP archive")
    parser.add_argument("destination", help="new DBE mod folder to create; an existing directory is never overwritten")
    parser.add_argument("--source-format", choices=("auto", *SUPPORTED_FORMATS), default="auto", help="source engine (auto detects known metadata and layouts)")
    arguments = parser.parse_args(argv)

    try:
        report = convert_mod(arguments.source, arguments.destination, source_format=arguments.source_format)
    except ConversionError as error:
        print(f"DBE mod conversion failed: {error}", file=sys.stderr)
        return 2

    print(json.dumps(report, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
