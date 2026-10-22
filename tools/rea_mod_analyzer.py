#!/usr/bin/env python3
"""DBE REA Mod Analyzer: Reverse-engineer custom executables and standalone mods.

This tool investigates unknown or custom executables, standalone FNF game builds,
and mod packages using binary analysis, Haxe/C++ RTTI signature extraction,
and optional REA (Reverse Engineer Anything) CLI integrations.

It identifies the underlying engine, script systems, asset structures, and
generates an actionable prescription to run or convert the mod for DBE (Debug Engine).
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import struct
import subprocess
import sys
import tempfile
import zipfile
from dataclasses import asdict, dataclass, field
from pathlib import Path
from typing import Any, Dict, List, Optional, Set, Tuple


# ==============================================================================
# Engine Signatures & Rules
# ==============================================================================

ENGINE_SIGNATURES = {
    "CodenameEngine": [
        rb"fnf\.codename\.engine",
        rb"CodenameEngine",
        rb"CustomState",
        rb"codenameengine",
        rb"FunkinEngine",
    ],
    "PsychEngine": [
        rb"psychlua\.FunkinLua",
        rb"psychlua\.",
        rb"PsychEngineVersion",
        rb"PsychEngine",
        rb"flixel\.addons\.ui\.FlxUIDropDownMenuCustom",
        rb"editors\.MasterEditorMenu",
    ],
    "KadeEngine": [
        rb"kade\.KadeEngine",
        rb"KadeEngineData",
        rb"PlayStateChangeables",
        rb"kadeEngine",
    ],
    "MicdUp": [
        rb"MicdUp",
        rb"CustomModifier",
        rb"OptionsMenuOld",
    ],
    "LeatherEngine": [
        rb"LeatherEngine",
        rb"leather\.",
    ],
    "ForeverEngine": [
        rb"ForeverEngine",
        rb"forever\.",
    ],
    "VanillaFNF": [
        rb"ninja\.muffin99",
        rb"ninjamuffin99",
        rb"funkin\.vis\.",
    ],
    "Electron": [
        rb"electron\.asar",
        rb"process\.versions\.electron",
        rb"ELECTRON_RUN_AS_NODE",
    ],
    "Godot": [
        rb"GDScript",
        rb"Godot Engine",
        rb"engine\.cfg",
    ],
    "Unity": [
        rb"UnityPlayer\.dll",
        rb"UnityEngine",
        rb"Unity Technologies",
    ],
}

PSYCH_VERSION_INDICATORS = [
    (re.compile(rb"0\.7\.[0-9]+"), "0.7.x"),
    (re.compile(rb"0\.6\.[0-9]+"), "0.6.x"),
    (re.compile(rb"0\.5\.[0-9]+"), "0.5.x"),
    (re.compile(rb"1\.0\.[0-9]+"), "1.0.x"),
]

KNOWN_LUA_HOOKS = [
    "onCreate",
    "onCreatePost",
    "onDestroy",
    "onUpdate",
    "onUpdatePost",
    "onStepHit",
    "onBeatHit",
    "onSectionHit",
    "goodNoteHit",
    "opponentNoteHit",
    "noteMiss",
    "onEvent",
    "onTimerCompleted",
    "onTweenCompleted",
    "onCustomSubstateCreate",
    "onCustomSubstateUpdate",
]

RISKY_LUA_APIS = {
    "runHaxeCode": "Executes arbitrary raw Haxe strings via hscript; requires DBE HScript bridge or manual rewrite.",
    "addHaxeLibrary": "Dynamically imports Haxe classes into Lua runtime; needs DBE equivalent classes.",
    "initLuaShader": "Initializes custom runtime GLSL shader; requires DBE shader pipeline.",
    "setShaderFloat": "Shader uniform binding; map to DBE shader variables.",
    "createCustomSubstate": "Spawns custom substate; map to DBE FlxSubState / CustomSubstate.",
    "runProcess": "Spawns OS subprocess; high security risk & engine specific.",
}


# ==============================================================================
# Data Structures
# ==============================================================================

@dataclass
class PESection:
    name: str
    virtual_size: int
    virtual_address: int
    raw_size: int
    raw_offset: int
    entropy: float = 0.0


@dataclass
class BinaryProfile:
    file_path: str
    file_size: int
    is_pe: bool = False
    machine: str = "Unknown"
    subsystem: str = "Unknown"
    compile_time: str = ""
    sections: List[PESection] = field(default_factory=list)
    is_packed: bool = False
    detected_engines: List[str] = field(default_factory=list)
    version_hint: str = "Unknown"
    haxe_classes: List[str] = field(default_factory=list)
    referenced_assets: List[str] = field(default_factory=list)
    detected_songs: List[str] = field(default_factory=list)


@dataclass
class DirectoryProfile:
    root_path: str
    total_files: int = 0
    has_mods_folder: bool = False
    has_assets_folder: bool = False
    has_data_folder: bool = False
    has_songs_folder: bool = False
    has_shared_folder: bool = False
    lua_scripts: List[str] = field(default_factory=list)
    hscript_files: List[str] = field(default_factory=list)
    chart_files: List[str] = field(default_factory=list)
    character_files: List[str] = field(default_factory=list)
    shader_files: List[str] = field(default_factory=list)
    used_lua_hooks: Set[str] = field(default_factory=set)
    risky_lua_calls: Dict[str, int] = field(default_factory=dict)


@dataclass
class ModReport:
    target: str
    target_type: str  # "executable", "directory", "archive"
    primary_engine: str = "Unknown"
    engine_confidence: str = "low"  # low, medium, high
    scripting_mode: str = "none"   # lua, hscript, compiled-only, hybrid
    asset_layout: str = "unknown"  # psych, codename, embedded, loose
    binary_profile: Optional[BinaryProfile] = None
    dir_profile: Optional[DirectoryProfile] = None
    rea_evidence: Dict[str, Any] = field(default_factory=dict)
    can_convert_to_dbe: bool = False
    conversion_complexity: str = "Low"  # Low, Medium, High, Complex
    issues_and_warnings: List[str] = field(default_factory=list)
    prescriptions: List[str] = field(default_factory=list)
    suggested_commands: List[str] = field(default_factory=list)


# ==============================================================================
# PE Parsing & String Analysis
# ==============================================================================

def calculate_entropy(data: bytes) -> float:
    """Calculate Shannon entropy for packing/compression detection."""
    if not data:
        return 0.0
    import math
    from collections import Counter
    counts = Counter(data)
    total = len(data)
    return -sum((count / total) * math.log2(count / total) for count in counts.values())


def parse_pe_header(raw_data: bytes) -> Optional[Tuple[str, str, str, List[PESection], bool]]:
    """Parse PE header directly without third-party dependencies."""
    if len(raw_data) < 64 or raw_data[:2] != b"MZ":
        return None

    try:
        e_lfanew = struct.unpack("<I", raw_data[60:64])[0]
        if e_lfanew + 24 > len(raw_data) or raw_data[e_lfanew:e_lfanew+4] != b"PE\x00\x00":
            return None

        # COFF File Header
        coff_offset = e_lfanew + 4
        machine_raw, num_sections, time_date_stamp, _, _, opt_hdr_size, characteristics = struct.unpack(
            "<HHIIIHH", raw_data[coff_offset:coff_offset+20]
        )

        machine = {0x014c: "x86 (32-bit)", 0x8664: "x64 (64-bit)", 0xaa64: "ARM64"}.get(
            machine_raw, f"0x{machine_raw:04x}"
        )

        import datetime
        try:
            compile_time = datetime.datetime.fromtimestamp(
                time_date_stamp, tz=datetime.timezone.utc
            ).strftime("%Y-%m-%d %H:%M:%S UTC")
        except Exception:
            compile_time = f"0x{time_date_stamp:08x}"

        # Optional Header Subsystem
        opt_hdr_offset = coff_offset + 20
        subsystem = "Unknown"
        if opt_hdr_size >= 68:
            magic = struct.unpack("<H", raw_data[opt_hdr_offset:opt_hdr_offset+2])[0]
            subsystem_offset = opt_hdr_offset + (68 if magic == 0x10b else 68)
            subsys_val = struct.unpack("<H", raw_data[subsystem_offset:subsystem_offset+2])[0]
            subsystem = {2: "Windows GUI", 3: "Windows CUI (Console)"}.get(subsys_val, f"Subsystem({subsys_val})")

        # Sections
        sections_offset = opt_hdr_offset + opt_hdr_size
        sections: List[PESection] = []
        is_packed = False

        for i in range(num_sections):
            sec_start = sections_offset + i * 40
            if sec_start + 40 > len(raw_data):
                break
            sec_name_raw, v_size, v_addr, raw_sz, raw_off = struct.unpack(
                "<8sIIII", raw_data[sec_start:sec_start+24]
            )
            sec_name = sec_name_raw.rstrip(b"\x00").decode("latin-1", errors="ignore")
            sec_data = raw_data[raw_off:raw_off + min(raw_sz, 65536)]
            ent = calculate_entropy(sec_data)
            if ent > 7.2 or sec_name.upper().startswith(("UPX", ".MPRESS", "ASPACK")):
                is_packed = True
            sections.append(PESection(
                name=sec_name,
                virtual_size=v_size,
                virtual_address=v_addr,
                raw_size=raw_sz,
                raw_offset=raw_off,
                entropy=round(ent, 2)
            ))

        return machine, subsystem, compile_time, sections, is_packed
    except Exception:
        return None


def extract_strings(raw_data: bytes, min_len: int = 4) -> List[str]:
    """Fast extraction of printable ASCII and UTF-16LE strings."""
    ascii_pat = re.compile(rb"[\x20-\x7e]{" + str(min_len).encode() + rb",}")
    found = [s.decode("latin-1") for s in ascii_pat.findall(raw_data)]
    return found


def analyze_binary_content(path: Path, raw_data: bytes) -> BinaryProfile:
    """Analyze executable bytes to detect Haxe/C++ runtime signatures and engine details."""
    pe_info = parse_pe_header(raw_data)
    is_pe = pe_info is not None
    machine = pe_info[0] if pe_info else "Unknown"
    subsystem = pe_info[1] if pe_info else "Unknown"
    compile_time = pe_info[2] if pe_info else ""
    sections = pe_info[3] if pe_info else []
    is_packed = pe_info[4] if pe_info else False

    profile = BinaryProfile(
        file_path=str(path),
        file_size=len(raw_data),
        is_pe=is_pe,
        machine=machine,
        subsystem=subsystem,
        compile_time=compile_time,
        sections=sections,
        is_packed=is_packed,
    )

    # Detect engines
    for engine, sigs in ENGINE_SIGNATURES.items():
        if any(re.search(sig, raw_data) for sig in sigs):
            profile.detected_engines.append(engine)

    # Detect Psych version hints
    for regex, hint in PSYCH_VERSION_INDICATORS:
        if regex.search(raw_data):
            profile.version_hint = hint
            break

    # Extract strings for deeper analysis
    strings = extract_strings(raw_data)

    # Detect Haxe classes & namespaces
    haxe_class_set: Set[str] = set()
    haxe_pattern = re.compile(r"^[a-zA-Z0-9_]+(?:\.[a-zA-Z0-9_]+)+(?:_obj)?$")
    for s in strings:
        if 6 <= len(s) <= 80 and haxe_pattern.match(s):
            if any(s.startswith(p) for p in ("flixel.", "funkin.", "psychlua.", "states.", "backend.", "objects.", "shaders.")):
                haxe_class_set.add(s)

    profile.haxe_classes = sorted(list(haxe_class_set))[:50]

    # Detect referenced assets / songs / charts
    asset_set: Set[str] = set()
    song_set: Set[str] = set()
    for s in strings:
        if ("assets/" in s or "mods/" in s or "shared/" in s) and ("." in s):
            if any(s.endswith(ext) for ext in (".json", ".png", ".xml", ".ogg", ".lua", ".hx", ".frag")):
                asset_set.add(s.strip())
        if s.startswith("songs/") or s.startswith("data/"):
            parts = s.split("/")
            if len(parts) >= 2 and parts[1]:
                song_set.add(parts[1].lower())

    profile.referenced_assets = sorted(list(asset_set))[:40]
    profile.detected_songs = sorted(list(song_set))[:30]

    return profile


# ==============================================================================
# Directory & Script Analysis
# ==============================================================================

def analyze_directory(root: Path) -> DirectoryProfile:
    """Analyze folder structure, Lua scripts, HScript, charts, and assets."""
    profile = DirectoryProfile(root_path=str(root))

    if not root.is_dir():
        return profile

    profile.has_mods_folder = (root / "mods").is_dir()
    profile.has_assets_folder = (root / "assets").is_dir()
    profile.has_data_folder = (root / "data").is_dir() or (root / "assets" / "data").is_dir()
    profile.has_songs_folder = (root / "songs").is_dir() or (root / "assets" / "songs").is_dir()
    profile.has_shared_folder = (root / "assets" / "shared").is_dir()

    total_files = 0
    for current_dir, _, files in os.walk(root):
        for f in files:
            total_files += 1
            file_path = Path(current_dir) / f
            rel = file_path.relative_to(root).as_posix()
            lower = f.lower()

            if lower.endswith(".lua"):
                profile.lua_scripts.append(rel)
                _scan_lua_file(file_path, profile)
            elif lower.endswith((".hx", ".hscript", ".hxs")):
                profile.hscript_files.append(rel)
            elif lower.endswith(".json"):
                if "data/" in rel or "charts/" in rel or "songs/" in rel:
                    profile.chart_files.append(rel)
                elif "characters/" in rel:
                    profile.character_files.append(rel)
            elif lower.endswith((".frag", ".vert")):
                profile.shader_files.append(rel)

    profile.total_files = total_files
    return profile


def _scan_lua_file(file_path: Path, profile: DirectoryProfile) -> None:
    """Scan Lua file for hooks and risky APIs."""
    try:
        content = file_path.read_text(encoding="utf-8", errors="ignore")
    except Exception:
        return

    # Check hooks
    for hook in KNOWN_LUA_HOOKS:
        if re.search(r"\bfunction\s+" + hook + r"\b", content):
            profile.used_lua_hooks.add(hook)

    # Check risky APIs
    for api in RISKY_LUA_APIS:
        matches = len(re.findall(r"\b" + api + r"\b", content))
        if matches > 0:
            profile.risky_lua_calls[api] = profile.risky_lua_calls.get(api, 0) + matches


# ==============================================================================
# REA Integration (Reverse Engineer Anything)
# ==============================================================================

class REABridge:
    """Executes deep reverse engineering commands via REA CLI or MCP tools."""

    @staticmethod
    def is_available() -> bool:
        """Check if rea-agents CLI is installed and available."""
        try:
            res = subprocess.run(
                ["npx", "-y", "rea-agents@6.5.0", "--version"],
                capture_output=True,
                text=True,
                timeout=10,
                shell=True,
            )
            return res.returncode == 0
        except Exception:
            return False

    @staticmethod
    def inspect_binary_with_rea(exe_path: Path) -> Dict[str, Any]:
        """Run REA objdump / PE inspection on the binary target."""
        evidence: Dict[str, Any] = {}
        try:
            # Run objdump inspect
            cmd = [
                "npx", "-y", "rea-agents@6.5.0",
                "inspect-with-objdump",
                str(exe_path.resolve()),
                "--format", "json",
            ]
            res = subprocess.run(cmd, capture_output=True, text=True, timeout=25, shell=True)
            if res.returncode == 0 and res.stdout.strip():
                try:
                    evidence["objdump"] = json.loads(res.stdout)
                except Exception:
                    evidence["objdump_raw"] = res.stdout[:2000]
        except Exception as exc:
            evidence["rea_error"] = str(exc)

        return evidence


# ==============================================================================
# Diagnosis & Prescription Engine
# ==============================================================================

def generate_report(target_path: Path, use_deep_rea: bool = False) -> ModReport:
    """Analyze target and synthesize a full diagnostic report with DBE prescriptions."""
    target_path = target_path.resolve()

    if not target_path.exists():
        raise FileNotFoundError(f"Target path '{target_path}' does not exist.")

    report = ModReport(target=str(target_path), target_type="unknown")

    temp_dir: Optional[Path] = None
    executables: List[Path] = []
    dir_to_scan: Path = target_path

    # Handle ZIP / Archive
    if target_path.is_file() and target_path.suffix.lower() in (".zip", ".rar", ".7z"):
        report.target_type = "archive"
        temp_dir = Path(tempfile.mkdtemp(prefix="rea_mod_"))
        if target_path.suffix.lower() == ".zip":
            with zipfile.ZipFile(target_path, "r") as zf:
                zf.extractall(temp_dir)
            dir_to_scan = temp_dir
        else:
            report.issues_and_warnings.append(
                f"Archive format {target_path.suffix} requires external unpacking. Extract to folder first."
            )

    # Handle Executable
    elif target_path.is_file() and target_path.suffix.lower() == ".exe":
        report.target_type = "executable"
        executables.append(target_path)
        dir_to_scan = target_path.parent

    # Handle Directory
    elif target_path.is_dir():
        report.target_type = "directory"
        dir_to_scan = target_path

    # Find executables in directory if not single exe
    if not executables:
        for f in dir_to_scan.glob("*.exe"):
            executables.append(f)

    # 1. Analyze Directory Content
    dir_profile = analyze_directory(dir_to_scan)
    report.dir_profile = dir_profile

    # 2. Analyze Primary Binary if present
    primary_exe: Optional[Path] = None
    if executables:
        primary_exe = executables[0]
        try:
            raw_bin = primary_exe.read_bytes()
            bin_profile = analyze_binary_content(primary_exe, raw_bin)
            report.binary_profile = bin_profile

            # Deep REA if requested
            if use_deep_rea:
                report.rea_evidence = REABridge.inspect_binary_with_rea(primary_exe)
        except Exception as exc:
            report.issues_and_warnings.append(f"Failed to read binary '{primary_exe.name}': {exc}")

    # 3. Determine Engine & Confidence
    engine_votes: Dict[str, int] = {}
    if report.binary_profile:
        for eng in report.binary_profile.detected_engines:
            engine_votes[eng] = engine_votes.get(eng, 0) + 3

    # Folder clues
    if dir_profile.has_mods_folder or dir_profile.lua_scripts:
        engine_votes["PsychEngine"] = engine_votes.get("PsychEngine", 0) + 2
    if dir_profile.hscript_files:
        engine_votes["CodenameEngine"] = engine_votes.get("CodenameEngine", 0) + 2

    if engine_votes:
        top_engine = max(engine_votes.items(), key=lambda x: x[1])
        report.primary_engine = top_engine[0]
        report.engine_confidence = "high" if top_engine[1] >= 3 else "medium"
    else:
        report.primary_engine = "Unknown / Custom FNF"
        report.engine_confidence = "low"

    # 4. Scripting Mode
    if dir_profile.lua_scripts and dir_profile.hscript_files:
        report.scripting_mode = "hybrid (Lua + HScript)"
    elif dir_profile.lua_scripts:
        report.scripting_mode = "Lua (Psych / Polymod)"
    elif dir_profile.hscript_files:
        report.scripting_mode = "HScript (Codename Engine / DBE native)"
    elif report.binary_profile and report.binary_profile.haxe_classes:
        report.scripting_mode = "Compiled-Only (Hardcoded Haxe C++ logic)"
    else:
        report.scripting_mode = "Static Data Only (JSON / Assets)"

    # 5. Asset Layout
    if dir_profile.has_mods_folder:
        report.asset_layout = "Psych Mods Layout (mods/)"
    elif dir_profile.has_assets_folder:
        report.asset_layout = "Standard Assets Layout (assets/data, assets/shared)"
    elif dir_profile.has_data_folder or dir_profile.has_songs_folder:
        report.asset_layout = "Loose Layout (data/, songs/ in root)"
    else:
        report.asset_layout = "Embedded in Binary or Missing"

    # 6. Assess DBE Conversion Feasibility & Prescriptions
    _evaluate_prescriptions(report, dir_to_scan)

    # Cleanup temp
    if temp_dir and temp_dir.exists():
        shutil.rmtree(temp_dir, ignore_errors=True)

    return report


def _evaluate_prescriptions(report: ModReport, dir_path: Path) -> None:
    """Formulate actionable steps for running or converting the mod into DBE."""
    prescriptions: List[str] = []
    commands: List[str] = []
    warnings: List[str] = []
    complexity = "Low"
    can_convert = True

    # Check packing
    if report.binary_profile and report.binary_profile.is_packed:
        warnings.append("Binary appears to be packed/compressed (UPX/entropy > 7.2). Embedded strings may be hidden.")
        prescriptions.append("1. If extracting embedded assets, unpack binary first using 'upx -d <exe>'.")

    # Engine specific prescriptions
    if report.primary_engine == "PsychEngine":
        prescriptions.append("Target is Psych Engine format. DBE features built-in chart and layout conversion.")

        # Check risky calls
        if report.dir_profile and report.dir_profile.risky_lua_calls:
            complexity = "Medium"
            for api, count in report.dir_profile.risky_lua_calls.items():
                warnings.append(f"Lua uses '{api}' ({count}x): {RISKY_LUA_APIS.get(api, 'Custom hook')}")
                if api in ("runHaxeCode", "addHaxeLibrary"):
                    complexity = "High"

        # Chart conversion recommendation
        if report.dir_profile and report.dir_profile.chart_files:
            prescriptions.append(f"Found {len(report.dir_profile.chart_files)} chart(s). Convert Psych section-based notes to CNE/DBE absolute-time.")

        # Standard command
        conv_script = Path("tools/dbe_mod_converter.py").resolve()
        out_folder = Path("mods") / dir_path.name
        commands.append(f"python tools/dbe_mod_converter.py \"{dir_path}\" --output \"{out_folder}\"")
        prescriptions.append(f"Execute 'dbe_mod_converter.py' to produce a normalized DBE mod in '{out_folder}'.")

    elif report.primary_engine == "CodenameEngine":
        prescriptions.append("Target already uses Codename Engine / DBE layout!")
        prescriptions.append(f"Copy directory directly into 'mods/{dir_path.name}' and launch Debug Engine.")
        commands.append(f"robocopy \"{dir_path}\" \"mods\\{dir_path.name}\" /E")

    elif report.primary_engine in ("KadeEngine", "VanillaFNF"):
        complexity = "High"
        warnings.append("Legacy engine format. Charts require legacy-to-psych or legacy-to-CNE migration.")
        prescriptions.append("1. Extract audio (Inst.ogg / Voices.ogg) and charts from assets/data/.")
        prescriptions.append("2. Convert chart notes to DBE strumLines schema.")

    else:
        complexity = "Complex"
        warnings.append(f"Engine '{report.primary_engine}' may have custom compiled C++ game states.")
        if report.binary_profile and report.binary_profile.haxe_classes:
            prescriptions.append("Custom Haxe classes detected in binary. Check for custom PlayState or Song mechanics:")
            for cls in report.binary_profile.haxe_classes[:10]:
                prescriptions.append(f"  - {cls}")
        prescriptions.append("Reconstruct mechanics into DBE scripts (source/funkin/backend/scripting/) or custom HScript.")

    report.can_convert_to_dbe = can_convert
    report.conversion_complexity = complexity
    report.issues_and_warnings.extend(warnings)
    report.prescriptions = prescriptions
    report.suggested_commands = commands


# ==============================================================================
# Presentation & CLI Formatters
# ==============================================================================

def print_pretty_report(report: ModReport) -> None:
    """Print a clean, structured diagnostic report to stdout."""
    print("=" * 80)
    print("  DBE REA MOD ANALYZER - REVERSE ENGINEERING & COMPATIBILITY REPORT")
    print("=" * 80)
    print(f" Target:              {report.target}")
    print(f" Type:                {report.target_type.upper()}")
    print(f" Detected Engine:     {report.primary_engine} (Confidence: {report.engine_confidence.upper()})")
    print(f" Scripting Engine:    {report.scripting_mode}")
    print(f" Asset Layout:        {report.asset_layout}")
    print(f" Conversion Feasible: {'YES' if report.can_convert_to_dbe else 'NO'} (Complexity: {report.conversion_complexity})")

    # Binary details
    if report.binary_profile and report.binary_profile.is_pe:
        bp = report.binary_profile
        print("\n--- Binary Inspection (PE / RTTI) ---")
        print(f"  Architecture:       {bp.machine}")
        print(f"  Subsystem:          {bp.subsystem}")
        print(f"  Compiled At:        {bp.compile_time or 'Unknown'}")
        print(f"  Packed/Protected:   {'YES (UPX/High Entropy)' if bp.is_packed else 'No (Standard PE)'}")
        print(f"  Sections ({len(bp.sections)}):      {', '.join(s.name for s in bp.sections)}")
        if bp.version_hint != "Unknown":
            print(f"  Engine Version:     {bp.version_hint}")
        if bp.detected_songs:
            print(f"  Embedded Songs ({len(bp.detected_songs)}): {', '.join(bp.detected_songs[:12])}")
        if bp.haxe_classes:
            print(f"  Haxe Symbols ({len(bp.haxe_classes)}): {', '.join(bp.haxe_classes[:8])}...")

    # Directory & Scripts details
    if report.dir_profile:
        dp = report.dir_profile
        print("\n--- Asset & Script Inventory ---")
        print(f"  Total Files:        {dp.total_files}")
        print(f"  Lua Scripts:        {len(dp.lua_scripts)}")
        print(f"  HScript Files:      {len(dp.hscript_files)}")
        print(f"  Charts Found:       {len(dp.chart_files)}")
        print(f"  Characters Found:   {len(dp.character_files)}")
        print(f"  Shaders Found:      {len(dp.shader_files)}")
        if dp.used_lua_hooks:
            print(f"  Active Lua Hooks:   {', '.join(sorted(list(dp.used_lua_hooks))[:10])}")

    # Warnings / Issues
    if report.issues_and_warnings:
        print("\n--- Warnings & Potential Friction Points ---")
        for warn in report.issues_and_warnings:
            print(f"  [!] {warn}")

    # Prescriptions (How to run / convert)
    print("\n--- Prescription (How to Run / Convert this Mod in DBE) ---")
    for step in report.prescriptions:
        print(f"  {step}")

    # Suggested Commands
    if report.suggested_commands:
        print("\n--- Ready-to-Run Commands ---")
        for cmd in report.suggested_commands:
            print(f"  > {cmd}")

    print("=" * 80 + "\n")


def generate_markdown_report(report: ModReport, out_path: Path) -> None:
    """Generate Markdown report artifact."""
    lines = [
        f"# Mod Reverse Engineering & Compatibility Report",
        f"",
        f"- **Target**: `{report.target}`",
        f"- **Type**: `{report.target_type}`",
        f"- **Primary Engine**: `{report.primary_engine}` ({report.engine_confidence})",
        f"- **Scripting Mode**: `{report.scripting_mode}`",
        f"- **Conversion Complexity**: `{report.conversion_complexity}`",
        f"",
        f"## 1. Engine & Binary Profile",
        f"",
    ]

    if report.binary_profile:
        bp = report.binary_profile
        lines.extend([
            f"| Attribute | Value |",
            f"|---|---|",
            f"| Architecture | {bp.machine} |",
            f"| Subsystem | {bp.subsystem} |",
            f"| Compile Timestamp | {bp.compile_time} |",
            f"| Packed / Compressed | {'Yes' if bp.is_packed else 'No'} |",
            f"| Sections | {', '.join(s.name for s in bp.sections)} |",
            f"",
        ])

    lines.extend([
        f"## 2. Issues & Warnings",
        f"",
    ])
    for w in report.issues_and_warnings:
        lines.append(f"- ⚠️ {w}")

    lines.extend([
        f"",
        f"## 3. Prescriptions (How to Run Mod)",
        f"",
    ])
    for p in report.prescriptions:
        lines.append(f"- {p}")

    if report.suggested_commands:
        lines.extend([
            f"",
            f"### Suggested Conversion Commands",
            f"```bash",
        ])
        for c in report.suggested_commands:
            lines.append(c)
        lines.append("```")

    out_path.write_text("\n".join(lines), encoding="utf-8")


# ==============================================================================
# CLI Entry Point
# ==============================================================================

def main() -> int:
    parser = argparse.ArgumentParser(
        description="DBE REA Mod Analyzer: Reverse-engineer custom executables and mods to understand how to run them in DBE."
    )
    parser.add_argument("target", help="Path to custom executable (.exe), mod directory, or archive (.zip)")
    parser.add_argument("--json", action="store_true", help="Output report in JSON format")
    parser.add_argument("--deep-rea", action="store_true", help="Invoke REA CLI (rea-agents objdump/inspections)")
    parser.add_argument("--report", type=str, help="Output markdown report file path")
    parser.add_argument("--auto-convert", action="store_true", help="Automatically trigger dbe_mod_converter.py if feasible")

    args = parser.parse_args()

    target_path = Path(args.target)
    if not target_path.exists():
        print(f"Error: target path '{args.target}' does not exist.", file=sys.stderr)
        return 1

    report = generate_report(target_path, use_deep_rea=args.deep_rea)

    if args.json:
        # Convert dataclass to dict cleanly
        class EnhancedJSONEncoder(json.JSONEncoder):
            def default(self, o):
                if isinstance(o, set):
                    return sorted(list(o))
                return super().default(o)

        print(json.dumps(asdict(report), indent=2, cls=EnhancedJSONEncoder))
    else:
        print_pretty_report(report)

    if args.report:
        report_file = Path(args.report)
        generate_markdown_report(report, report_file)
        print(f"Markdown report generated at: {report_file}")

    if args.auto_convert and report.can_convert_to_dbe and report.suggested_commands:
        print("\n[Auto-Convert] Running conversion command...")
        cmd = report.suggested_commands[0]
        ret = subprocess.run(cmd, shell=True)
        return ret.returncode

    return 0


if __name__ == "__main__":
    sys.exit(main())
