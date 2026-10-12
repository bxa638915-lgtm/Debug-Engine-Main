#!/usr/bin/env python3
"""Validate pinned Psych Lua contract inventories using only the Python stdlib."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CONTRACTS = ROOT / "docs/compatibility/contracts"
LOCK_PATH = CONTRACTS / "source-lock.json"
PROFILES = {
    "0.6.3": ("eb0ade39e8d1c5437db2166a9ddb6eb3c05956e1", "0.6.3"),
    "1.0.4": ("5c67ced49e5a98535298a6daa3f8f4ec79ac8399", "1.0.4"),
}
STATES = {"compatible", "adapted", "incompatible", "not-verified"}


def _read_json(path: Path):
    try:
        return json.loads(path.read_text(encoding="utf-8-sig"))
    except (OSError, json.JSONDecodeError) as exc:
        return None


def validate_lock_data(data) -> list[str]:
    errors = []
    if not isinstance(data, dict) or not isinstance(data.get("sources"), list):
        return ["source lock must contain a sources array"]
    if data.get("snapshotAlgorithm") != "dbe-file-tree-sha256-v1":
        errors.append("source lock snapshotAlgorithm must be dbe-file-tree-sha256-v1")
    found = {}
    for source in data["sources"]:
        if not isinstance(source, dict):
            errors.append("source lock entry must be an object")
            continue
        profile = source.get("profile")
        if profile not in PROFILES:
            errors.append(f"unknown source profile {profile!r}")
            continue
        commit, tag = PROFILES[profile]
        if source.get("tag") != tag:
            errors.append(f"{profile}: tag must be {tag}")
        if source.get("commit") != commit:
            errors.append(f"{profile}: commit must be {commit}")
        if source.get("repository") != "https://github.com/ShadowMario/FNF-PsychEngine.git":
            errors.append(f"{profile}: repository must be the official Psych Engine repository")
        if not re.fullmatch(r"[0-9a-f]{64}", str(source.get("snapshotSha256", ""))):
            errors.append(f"{profile}: snapshotSha256 must be a lowercase SHA-256")
        if source.get("snapshotPaths") != ["source"]:
            errors.append(f"{profile}: snapshotPaths must be [source]")
        if profile in found:
            errors.append(f"duplicate source lock profile {profile}")
        found[profile] = source
    for profile in PROFILES:
        if profile not in found:
            errors.append(f"missing source lock for {profile}")
    return errors


def validate_source_locks(root: Path = ROOT) -> bool:
    data = _read_json(root / "docs/compatibility/contracts/source-lock.json")
    if data is None:
        return False
    return not validate_lock_data(data)


def _validate_common(entry, kind: str) -> list[str]:
    errors = []
    name = entry.get("name", "<unnamed>") if isinstance(entry, dict) else "<invalid>"
    if not isinstance(entry, dict):
        return [f"{kind} entry must be an object"]
    if not isinstance(entry.get("name"), str) or not entry["name"].strip():
        errors.append(f"{kind} {name}: name is required")
    if entry.get("kind") != kind:
        errors.append(f"{kind} {name}: kind must be {kind}")
    if entry.get("status") not in STATES:
        errors.append(f"{kind} {name}: invalid contract state")
    source = entry.get("source")
    if not isinstance(source, dict) or not isinstance(source.get("path"), str) or not source.get("path") or not isinstance(source.get("line"), int) or source.get("line", 0) < 1:
        errors.append(f"{kind} {name}: source path and positive line are required")
    if not isinstance(entry.get("evidence"), dict) or not entry["evidence"].get("kind") or not entry["evidence"].get("note"):
        errors.append(f"{kind} {name}: evidence kind and note are required")
    if not isinstance(entry.get("dbeBinding"), dict) or entry["dbeBinding"].get("status") not in {"matched", "unmatched", "alias", "dynamic", "unclassified"}:
        errors.append(f"{kind} {name}: DBE binding reconciliation is required")
    if entry.get("status") in {"compatible", "adapted"} and not entry.get("fixtureId"):
        errors.append(f"{kind} {name}: compatible/adapted entries require a fixtureId")
    return errors


def validate_entry(entry, kind: str) -> list[str]:
    errors = _validate_common(entry, kind)
    if not isinstance(entry, dict):
        return errors
    name = entry.get("name", "<unnamed>")
    if kind == "function":
        required = ("signature", "defaults", "return", "effects", "preconditions", "platform", "errors")
        for field in required:
            if field not in entry:
                errors.append(f"function {name}: missing {field}")
        signature = entry.get("signature")
        if not isinstance(signature, dict) or not isinstance(signature.get("parameters"), list) or not isinstance(signature.get("variadic"), bool):
            errors.append(f"function {name}: signature requires ordered parameters and variadic behavior")
        elif any(not isinstance(p, dict) or not p.get("name") or "acceptedValues" not in p or "default" not in p for p in signature["parameters"]):
            errors.append(f"function {name}: each parameter requires name, acceptedValues, and default")
        if not isinstance(entry.get("defaults"), dict):
            errors.append(f"function {name}: defaults must be an object")
        if not isinstance(entry.get("return"), dict) or not entry["return"].get("type") or not entry["return"].get("conversion"):
            errors.append(f"function {name}: return type and conversion are required")
        if not isinstance(entry.get("effects"), list):
            errors.append(f"function {name}: effects must be an array")
        if not isinstance(entry.get("preconditions"), list):
            errors.append(f"function {name}: preconditions must be an array")
        platform = entry.get("platform")
        if not isinstance(platform, dict) or not isinstance(platform.get("targets"), list) or not isinstance(platform.get("buildRequirements"), list):
            errors.append(f"function {name}: platform targets and buildRequirements are required")
        if not isinstance(entry.get("errors"), dict) or not entry["errors"].get("behavior"):
            errors.append(f"function {name}: error behavior is required")
    elif kind == "callback":
        for field in ("eventSource", "triggerBoundary", "order", "arguments", "returnCancellation"):
            if field not in entry:
                errors.append(f"callback {name}: missing {field}")
    else:
        errors.append(f"unknown catalog entry kind {kind}")
    return errors


def validate_catalog_data(data) -> list[str]:
    if not isinstance(data, dict):
        return ["catalog must be an object"]
    errors = []
    entries = []
    for kind, key in (("function", "functions"), ("callback", "callbacks")):
        values = data.get(key)
        if not isinstance(values, list):
            errors.append(f"catalog {key} must be an array")
            continue
        seen = set()
        for entry in values:
            errors.extend(validate_entry(entry, kind))
            if isinstance(entry, dict):
                name = entry.get("name")
                if name in seen:
                    errors.append(f"duplicate {kind} name {name}")
                seen.add(name)
                entries.append(entry)
    dbe_only = data.get("dbeOnly", [])
    if not isinstance(dbe_only, list):
        errors.append("catalog dbeOnly must be an array")
    else:
        seen_dbe_only = set()
        for item in dbe_only:
            if not isinstance(item, dict):
                errors.append("DBE-only entry must be an object")
                continue
            name = item.get("name", "<unnamed>")
            if not isinstance(item.get("name"), str) or not item["name"].strip():
                errors.append("DBE-only entry requires a name")
            if item.get("classification") not in {"dbe-surface-only", "profile-gated-off"}:
                errors.append(f"DBE-only {name}: classification must be dbe-surface-only or profile-gated-off")
            if not isinstance(item.get("explanation"), str) or not item["explanation"].strip():
                errors.append(f"DBE-only {name}: explanation is required")
            binding_source = item.get("bindingSource")
            if not isinstance(binding_source, dict) or not isinstance(binding_source.get("path"), str) or not binding_source.get("path") or not isinstance(binding_source.get("line"), int) or binding_source.get("line", 0) < 1:
                errors.append(f"DBE-only {name}: bindingSource path and positive line are required")
            if isinstance(item.get("name"), str):
                if item["name"] in seen_dbe_only:
                    errors.append(f"duplicate DBE-only name {item['name']}")
                seen_dbe_only.add(item["name"])
    return errors


def validate_dbe_only_reconciliation(catalogs: dict[str, dict], bindings: dict[str, int]) -> list[str]:
    """Require every current DBE Lua binding to be source-matched or explicitly DBE-only."""
    errors = []
    expected_path = "source/funkin/backend/scripting/LuaScript.hx"
    for profile, catalog in catalogs.items():
        source_names = {entry.get("name") for entry in catalog.get("functions", []) if isinstance(entry, dict)}
        expected = set(bindings) - source_names
        entries = catalog.get("dbeOnly", [])
        actual = {entry.get("name") for entry in entries if isinstance(entry, dict)}
        for name in sorted(expected - actual, key=str.casefold):
            errors.append(f"{profile}: DBE binding {name} is not listed in dbeOnly")
        for name in sorted(actual - expected, key=str.casefold):
            errors.append(f"{profile}: dbeOnly entry {name} is not absent from the Psych function inventory")
        for entry in entries:
            if not isinstance(entry, dict):
                continue
            name = entry.get("name")
            if name not in bindings:
                continue
            location = entry.get("bindingSource", {})
            if location.get("path") != expected_path or location.get("line") != bindings[name]:
                errors.append(f"{profile}: DBE-only {name} bindingSource does not match LuaScript.hx")
    return errors


def validate_manifest(root: Path, catalogs: dict[str, dict]) -> list[str]:
    path = root / "tests/fixtures/psych-lua/fixture-manifest.json"
    manifest = _read_json(path)
    if not isinstance(manifest, dict) or not isinstance(manifest.get("fixtures"), list):
        return ["fixture manifest is missing or has no fixtures array"]
    errors = []
    fixtures = {}
    for item in manifest["fixtures"]:
        if not isinstance(item, dict):
            errors.append("fixture declaration must be an object")
            continue
        fixture_id = item.get("id")
        profile = item.get("profile")
        script_path = item.get("scriptPath", "")
        expected_profile = item.get("expectedProfile", profile)
        config_scenario = item.get("configScenario", "selected" if profile in PROFILES else None)
        covers = item.get("covers")
        if not isinstance(fixture_id, str) or not fixture_id:
            errors.append("fixture declaration requires an id")
            continue
        if fixture_id in fixtures:
            errors.append(f"duplicate fixture id {fixture_id}")
        fixtures[fixture_id] = item
        if profile in PROFILES:
            if not script_path.startswith(f"tests/fixtures/psych-lua/{profile}/"):
                errors.append(f"fixture {fixture_id}: script path does not match profile")
            if expected_profile != profile:
                errors.append(f"fixture {fixture_id}: selected profile must match its catalog profile")
            if config_scenario != "selected":
                errors.append(f"fixture {fixture_id}: versioned fixtures require configScenario selected")
        elif profile == "unspecified":
            if not script_path.startswith("tests/fixtures/psych-lua/profile-cases/"):
                errors.append(f"fixture {fixture_id}: unspecified profile fixtures must use profile-cases")
            if expected_profile != "unspecified":
                errors.append(f"fixture {fixture_id}: expectedProfile must be unspecified")
            config_text = item.get("configText")
            if config_scenario == "missing":
                if "configText" in item:
                    errors.append(f"fixture {fixture_id}: missing config scenario cannot provide configText")
            elif config_scenario == "malformed":
                if not isinstance(config_text, str) or not config_text:
                    errors.append(f"fixture {fixture_id}: malformed configText must be a non-empty string")
                else:
                    try:
                        json.loads(config_text)
                        errors.append(f"fixture {fixture_id}: malformed configText must not parse as JSON")
                    except json.JSONDecodeError:
                        pass
            elif config_scenario == "unsupported":
                if not isinstance(config_text, str) or not config_text:
                    errors.append(f"fixture {fixture_id}: unsupported configText must be a non-empty string")
                else:
                    try:
                        config_data = json.loads(config_text)
                        if not isinstance(config_data, dict):
                            errors.append(f"fixture {fixture_id}: unsupported configText must be a JSON object")
                        else:
                            requested_profile = config_data.get("psychLuaProfile")
                            if not isinstance(requested_profile, str) or requested_profile in PROFILES:
                                errors.append(f"fixture {fixture_id}: unsupported configText must select an unknown profile")
                    except json.JSONDecodeError:
                        errors.append(f"fixture {fixture_id}: unsupported configText must be valid JSON")
            else:
                errors.append(f"fixture {fixture_id}: unspecified profile requires missing, malformed, or unsupported configScenario")
        else:
            errors.append(f"fixture {fixture_id}: unknown profile {profile!r}")
        if not isinstance(covers, dict) or not isinstance(covers.get("apis"), list) or not isinstance(covers.get("callbacks"), list):
            errors.append(f"fixture {fixture_id}: covers must list APIs and callbacks")
        if item.get("physicalStatus") not in {"pending", "present"}:
            errors.append(f"fixture {fixture_id}: physicalStatus must be pending or present")
        expected_markers = item.get("expectedMarkers")
        pass_marker = f"DBE_PSYCH_FIXTURE_PASS:{fixture_id}"
        if not isinstance(expected_markers, list) or pass_marker not in expected_markers or any(not isinstance(marker, str) or not marker for marker in expected_markers):
            errors.append(f"fixture {fixture_id}: expectedMarkers must include {pass_marker}")
        callback_order = item.get("expectedCallbackOrder")
        if not isinstance(callback_order, list) or any(not isinstance(marker, str) or not marker for marker in callback_order):
            errors.append(f"fixture {fixture_id}: expectedCallbackOrder must be an array of non-empty markers")
    for profile, catalog in catalogs.items():
        actual_coverage = {"apis": set(), "callbacks": set()}
        for kind, key, cover_key in (("function", "functions", "apis"), ("callback", "callbacks", "callbacks")):
            cover_map = {}
            for fixture_id, item in fixtures.items():
                if item.get("profile") == profile:
                    for name in item.get("covers", {}).get(cover_key, []):
                        cover_map.setdefault(name, set()).add(fixture_id)
                        actual_coverage[cover_key].add(name)
            for entry in catalog.get(key, []):
                fixture_id = entry.get("fixtureId")
                if entry.get("status") in {"compatible", "adapted"} and not fixture_id:
                    errors.append(f"{profile} {kind} {entry.get('name')}: missing required fixture")
                if fixture_id:
                    declaration = fixtures.get(fixture_id)
                    if not declaration or declaration.get("profile") != profile:
                        errors.append(f"{profile} {kind} {entry.get('name')}: unresolved or wrong-profile fixture {fixture_id}")
                    elif entry.get("name") not in declaration.get("covers", {}).get(cover_key, []):
                        errors.append(f"{profile} {kind} {entry.get('name')}: fixture {fixture_id} does not cover this name")
        for key, label in (("functions", "apis"), ("callbacks", "callbacks")):
            expected = {entry.get("name") for entry in catalog.get(key, []) if isinstance(entry, dict)}
            missing = expected - actual_coverage[label]
            extra = actual_coverage[label] - expected
            if missing:
                errors.append(f"{profile}: fixture manifest does not declare coverage for {len(missing)} {label} names")
            if extra:
                errors.append(f"{profile}: fixture manifest covers {len(extra)} unknown {label} names")
    return errors


def validate_profile_differences(catalogs: dict[str, dict]) -> list[str]:
    errors = []
    for profile, catalog in catalogs.items():
        other = "1.0.4" if profile == "0.6.3" else "0.6.3"
        other_catalog = catalogs.get(other)
        if other_catalog is None:
            continue
        expected = []
        for kind, key in (("function", "functions"), ("callback", "callbacks")):
            own_names = {entry.get("name") for entry in catalog.get(key, []) if isinstance(entry, dict)}
            other_names = {entry.get("name") for entry in other_catalog.get(key, []) if isinstance(entry, dict)}
            expected.extend({"kind": kind, "name": name, "otherProfile": other, "classification": "source-surface-only", "behaviorStatus": "not-verified"} for name in own_names - other_names)
        expected.sort(key=lambda item: (item["kind"], item["name"].casefold()))
        actual = catalog.get("profileDifferences")
        if actual != expected:
            errors.append(f"{profile}: profileDifferences do not match the two extracted source surfaces")
    return errors


def load_evidence_runs(root: Path = ROOT) -> tuple[list[dict], list[str]]:
    """Load native build/gameplay results emitted by psych-lua-test.ps1."""
    evidence_root = root / "export/compat-tests"
    runs = []
    errors = []
    if not evidence_root.is_dir():
        return runs, errors
    for path in sorted(evidence_root.glob("psych-lua-evidence-*.json")):
        data = _read_json(path)
        if not isinstance(data, dict) or data.get("schemaVersion") != 1:
            errors.append(f"invalid Psych Lua evidence record: {path.relative_to(root).as_posix()}")
            continue
        runs.append(data)
    return runs, errors


def _safe_evidence_file(root: Path, relative_path) -> Path | None:
    if not isinstance(relative_path, str) or not relative_path.strip():
        return None
    candidate = (root / relative_path.replace("\\", "/")).resolve()
    try:
        candidate.relative_to(root.resolve())
    except ValueError:
        return None
    return candidate if candidate.is_file() else None


def _fixture_result_passes(root: Path, evidence_runs: list[dict], profile: str, fixture: dict, platform: str) -> bool:
    fixture_id = fixture.get("id")
    pass_marker = f"DBE_PSYCH_FIXTURE_PASS:{fixture_id}"
    for run in evidence_runs:
        for result in run.get("fixtureRuns", []):
            if not isinstance(result, dict) or result.get("status") != "passed":
                continue
            if result.get("profile") != profile or result.get("platform") != platform or fixture_id not in result.get("fixtureIds", []):
                continue
            paths = [
                _safe_evidence_file(root, result.get("stdoutLog")),
                _safe_evidence_file(root, result.get("stderrLog")),
            ]
            log_text = "\n".join(path.read_text(encoding="utf-8", errors="replace") for path in paths if path)
            expected = fixture.get("expectedMarkers", [])
            if pass_marker not in log_text or any(marker not in log_text for marker in expected):
                continue
            last_index = -1
            ordered = True
            for callback_name in fixture.get("expectedCallbackOrder", []):
                marker = f"DBE_PSYCH_CALLBACK:{fixture_id}:{callback_name}"
                next_index = log_text.find(marker, last_index + 1)
                if next_index < 0 or next_index <= last_index:
                    ordered = False
                    break
                last_index = next_index
            if ordered:
                return True
    return False


def _has_lua_build(evidence_runs: list[dict], platform: str, root: Path = ROOT) -> bool:
    for run in evidence_runs:
        for result in run.get("builds", []):
            if isinstance(result, dict) and result.get("target") == platform and result.get("luaEnabled") is True and result.get("status") == "passed":
                build_log = _safe_evidence_file(root, result.get("log"))
                if build_log is not None and "Link: ApplicationMain.exe" in build_log.read_text(encoding="utf-8", errors="replace"):
                    return True
    return False


def _contract_semantics_are_complete(entry: dict, kind: str) -> bool:
    if kind == "function":
        signature = entry.get("signature", {})
        returned = entry.get("return", {})
        platform = entry.get("platform", {})
        errors = entry.get("errors", {})
        placeholders = {"", "unknown", "not-extracted", "not-verified"}
        return not (
            signature.get("observation") == "not-extracted"
            or entry.get("defaults", {}).get("observation") == "not-extracted"
            or returned.get("type") in placeholders
            or returned.get("conversion") in placeholders
            or errors.get("behavior") in placeholders
            or any(target in placeholders for target in platform.get("targets", []))
        )
    placeholders = {"", "unknown", "not-extracted", "not-verified"}
    return not any(
        entry.get(field) in placeholders
        for field in ("eventSource", "triggerBoundary", "returnCancellation")
    )


def profile_platform_claim(catalog: dict, platform: str, evidence_runs: list[dict], root: Path = ROOT) -> dict:
    """Derive a profile/platform claim from catalog status and recorded native evidence."""
    if not _has_lua_build(evidence_runs, platform, root):
        return {"status": "unvalidated", "reason": f"No passing Lua-enabled {platform} build is recorded."}
    profile = catalog.get("profile", "<unknown>")
    functions = catalog.get("functions", [])
    callbacks = catalog.get("callbacks", [])
    entries = [entry for entry in functions + callbacks if isinstance(entry, dict)]
    counts = {state: sum(entry.get("status") == state for entry in entries) for state in STATES}
    if counts["not-verified"]:
        return {"status": "blocked", "reason": f"{counts['not-verified']} contract(s) remain not-verified."}
    if counts["incompatible"]:
        return {"status": "partial", "reason": f"{counts['incompatible']} contract(s) are explicitly incompatible."}
    manifest_data = _read_json(root / "tests/fixtures/psych-lua/fixture-manifest.json") or {}
    fixture_map = {item.get("id"): item for item in manifest_data.get("fixtures", []) if isinstance(item, dict)}
    for entry in entries:
        if entry.get("status") not in {"compatible", "adapted"}:
            continue
        fixture = fixture_map.get(entry.get("fixtureId"))
        if fixture is None or not _fixture_result_passes(root, evidence_runs, profile, fixture, platform):
            return {"status": "blocked", "reason": f"No passing {platform} result covers {entry.get('name')} / {entry.get('fixtureId')}."}
    if not any(
        isinstance(result, dict)
        and result.get("profile") == profile
        and result.get("platform") == platform
        and result.get("status") == "passed"
        for run in evidence_runs for result in run.get("fixtureRuns", [])
    ):
        return {"status": "unvalidated", "reason": f"No passing {profile} gameplay smoke is recorded for {platform}."}
    return {"status": "supported", "reason": "All contracts and required native evidence passed."}


def validate_final_evidence(root: Path, catalogs: dict[str, dict], evidence_runs: list[dict]) -> list[str]:
    """Gate full support claims on classified contracts and passing fixture evidence."""
    errors = []
    manifest = _read_json(root / "tests/fixtures/psych-lua/fixture-manifest.json")
    fixtures = {item.get("id"): item for item in manifest.get("fixtures", []) if isinstance(item, dict)} if isinstance(manifest, dict) else {}
    for profile, catalog in catalogs.items():
        for kind, key, cover_key in (("function", "functions", "apis"), ("callback", "callbacks", "callbacks")):
            for entry in catalog.get(key, []):
                if not isinstance(entry, dict):
                    continue
                name = entry.get("name", "<unnamed>")
                status = entry.get("status")
                binding_status = entry.get("dbeBinding", {}).get("status")
                if status == "not-verified":
                    errors.append(f"{profile} {kind} {name}: not-verified contract remains")
                if binding_status in {None, "unclassified"}:
                    errors.append(f"{profile} {kind} {name}: unclassified DBE mapping")
                if status not in {"compatible", "adapted"}:
                    continue
                if binding_status == "unmatched":
                    errors.append(f"{profile} {kind} {name}: compatible/adapted status has no DBE binding")
                if not _contract_semantics_are_complete(entry, kind):
                    errors.append(f"{profile} {kind} {name}: compatible/adapted status has placeholder contract semantics")
                fixture_id = entry.get("fixtureId")
                fixture = fixtures.get(fixture_id)
                if not fixture or fixture.get("profile") != profile:
                    errors.append(f"{profile} {kind} {name}: fixture {fixture_id!r} is missing or has the wrong profile")
                    continue
                if fixture.get("physicalStatus") != "present":
                    errors.append(f"{profile} {kind} {name}: fixture {fixture_id} is not present on disk")
                    continue
                script_path = _safe_evidence_file(root, fixture.get("scriptPath"))
                if script_path is None:
                    errors.append(f"{profile} {kind} {name}: fixture {fixture_id} has no on-disk script")
                    continue
                if name not in fixture.get("covers", {}).get(cover_key, []):
                    errors.append(f"{profile} {kind} {name}: fixture {fixture_id} does not declare this contract")
                    continue
                if not _fixture_result_passes(root, evidence_runs, profile, fixture, "windows-x64"):
                    errors.append(f"{profile} {kind} {name}: no passing fixture result for {fixture_id}")
        claim = profile_platform_claim(catalog, "windows-x64", evidence_runs, root)
        if claim["status"] != "supported":
            errors.append(f"{profile}: Windows x64 full-support claim is {claim['status']}: {claim['reason']}")
    return errors


def generate_evidence_report(root: Path, catalogs: dict[str, dict], evidence_runs: list[dict]) -> str:
    lock = _read_json(root / "docs/compatibility/contracts/source-lock.json") or {"sources": []}
    source_map = {source.get("profile"): source for source in lock.get("sources", []) if isinstance(source, dict)}
    lines = [
        "# Evidência de compatibilidade Psych Lua",
        "",
        "Relatório gerado por `tools/psych-compat/verify_contracts.py`. Status de cobertura depende de fixtures executados; presença de nomes não comprova comportamento.",
        "",
        "## Fontes fixadas",
        "",
        "| Perfil | Commit | SHA-256 do snapshot |",
        "|---|---|---|",
    ]
    for profile in sorted(source_map):
        source = source_map[profile]
        lines.append(f"| {profile} | `{source.get('commit', '—')}` | `{source.get('snapshotSha256', '—')}` |")
    lines.extend(["", "## Contratos por perfil", "", "| Perfil | Tipo | Compatible | Adapted | Incompatible | Not verified |", "|---|---|---:|---:|---:|---:|"])
    for profile, catalog in sorted(catalogs.items()):
        for kind, key in (("funções", "functions"), ("callbacks", "callbacks")):
            entries = catalog.get(key, [])
            counts = {state: sum(entry.get("status") == state for entry in entries if isinstance(entry, dict)) for state in STATES}
            lines.append(f"| {profile} | {kind} | {counts['compatible']} | {counts['adapted']} | {counts['incompatible']} | {counts['not-verified']} |")
    lines.extend(["", "## Build e smoke por plataforma", "", "| Perfil | Alvo | Build Lua | Fixtures aprovados | Claim derivado | Motivo |", "|---|---|---|---:|---|---|"])
    platforms = sorted({result.get("target") for run in evidence_runs for result in run.get("builds", []) if isinstance(result, dict) and result.get("target")})
    platforms = platforms or ["windows-x64"]
    for profile, catalog in sorted(catalogs.items()):
        for platform in platforms:
            build_passed = _has_lua_build(evidence_runs, platform, root)
            passed_profiles = {result.get("profile") for run in evidence_runs for result in run.get("fixtureRuns", []) if isinstance(result, dict) and result.get("platform") == platform and result.get("status") == "passed"}
            fixture_count = sum(1 for run in evidence_runs for result in run.get("fixtureRuns", []) if isinstance(result, dict) and result.get("platform") == platform and result.get("profile") == profile and result.get("status") == "passed")
            claim = profile_platform_claim(catalog, platform, evidence_runs, root)
            lines.append(f"| {profile} | {platform} | {'PASS' if build_passed else 'não registrado'} | {fixture_count} grupos | {claim['status']} | {claim['reason']} |")
    lines.extend(["", "## Execuções de fixtures", "", "| Perfil | Alvo | Fixtures | Resultado | Log |", "|---|---|---|---|---|"])
    for run in evidence_runs:
        for result in run.get("fixtureRuns", []):
            if isinstance(result, dict):
                ids = ", ".join(result.get("fixtureIds", []))
                lines.append(f"| {result.get('profile', '—')} | {result.get('platform', '—')} | {ids} | {result.get('status', '—')} | `{result.get('stdoutLog', '—')}` |")
    lines.extend(["", "## Contratos incompatíveis ou pendentes", "", "| Perfil | Tipo | Nome | Estado | Binding DBE | Fixture |", "|---|---|---|---|---|---|"])
    for profile, catalog in sorted(catalogs.items()):
        for kind, key in (("função", "functions"), ("callback", "callbacks")):
            for entry in catalog.get(key, []):
                if isinstance(entry, dict) and entry.get("status") in {"incompatible", "not-verified"}:
                    binding = entry.get("dbeBinding", {})
                    lines.append(f"| {profile} | {kind} | `{entry.get('name', '—')}` | {entry.get('status')} | {binding.get('status', '—')}: `{binding.get('name', '—')}` | {entry.get('fixtureId') or '—'} |")
    return "\n".join(lines) + "\n"


def _snapshot_sha256(repo: Path, paths=("source",)) -> str:
    """Hash a sorted path/content snapshot, independent of ZIP/TAR metadata."""
    digest = hashlib.sha256()
    for relative in paths:
        base = repo / relative
        if not base.exists():
            raise ValueError(f"snapshot path is missing: {relative}")
        files = [base] if base.is_file() else sorted((item for item in base.rglob("*") if item.is_file()), key=lambda item: item.relative_to(repo).as_posix())
        for path in files:
            name = path.relative_to(repo).as_posix().encode("utf-8")
            payload = path.read_bytes()
            digest.update(name + b"\0" + len(payload).to_bytes(8, "big") + payload)
    return digest.hexdigest()


def fetch_source(source: dict, temp_root: Path) -> Path:
    profile = source["profile"]
    repo = temp_root / f"psych-{profile}"
    if repo.exists():
        import shutil
        shutil.rmtree(repo)
    subprocess.run(["git", "init", str(repo)], check=True, stdout=subprocess.DEVNULL)
    subprocess.run(["git", "-C", str(repo), "remote", "add", "origin", source["repository"]], check=True)
    remote = subprocess.run(["git", "ls-remote", source["repository"], f"refs/tags/{source['tag']}"], check=True, capture_output=True, text=True).stdout
    resolved = remote.split()[0] if remote.split() else ""
    if resolved != source["commit"]:
        raise ValueError(f"{profile}: tag {source['tag']} resolves to {resolved or '<missing>'}, expected {source['commit']}")
    subprocess.run(["git", "-C", str(repo), "fetch", "--depth=1", "--filter=blob:none", "--no-tags", "origin", source["commit"]], check=True)
    actual = subprocess.run(["git", "-C", str(repo), "rev-parse", "FETCH_HEAD^{commit}"], check=True, capture_output=True, text=True).stdout.strip()
    if actual != source["commit"]:
        raise ValueError(f"{profile}: fetched commit {actual} does not match lock")
    subprocess.run(["git", "-C", str(repo), "sparse-checkout", "init", "--cone"], check=True, stdout=subprocess.DEVNULL)
    subprocess.run(["git", "-C", str(repo), "sparse-checkout", "set", "source"], check=True, stdout=subprocess.DEVNULL)
    subprocess.run(["git", "-C", str(repo), "checkout", "--detach", actual], check=True, stdout=subprocess.DEVNULL)
    digest = _snapshot_sha256(repo, source.get("snapshotPaths", ["source"]))
    if digest != source["snapshotSha256"]:
        raise ValueError(f"{profile}: snapshot SHA-256 {digest} does not match lock {source['snapshotSha256']}")
    return repo


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--fetch-pinned-sources", action="store_true", help="fetch and verify each official tag/commit and snapshot hash")
    parser.add_argument("--final-gate", action="store_true", help="reject incomplete catalog claims or missing native fixture evidence")
    parser.add_argument("--write-evidence-report", type=Path, help="write a Markdown report derived from catalogs and recorded native runs")
    args = parser.parse_args()
    lock = _read_json(LOCK_PATH)
    lock_errors = validate_lock_data(lock)
    if lock_errors:
        print("Source lock errors:")
        for error in lock_errors:
            print(f"  - {error}")
        return 1
    errors = []
    evidence_runs, evidence_errors = load_evidence_runs(ROOT)
    errors.extend(evidence_errors)
    catalogs = {}
    schema_path = CONTRACTS / "psych-contract.schema.json"
    schema = _read_json(schema_path)
    if not isinstance(schema, dict):
        errors.append(f"missing or invalid JSON Schema: {schema_path}")
    else:
        try:
            import jsonschema
            jsonschema.Draft202012Validator.check_schema(schema)
        except ImportError:
            pass  # Structural checks below use the same required contract fields.
        except Exception as exc:
            errors.append(f"invalid JSON Schema: {exc}")
    for profile in PROFILES:
        path = CONTRACTS / f"psych-{profile}.json"
        data = _read_json(path)
        if data is None:
            errors.append(f"missing or invalid catalog: {path}")
            continue
        if data.get("profile") != profile:
            errors.append(f"{path}: profile field mismatch")
        for error in validate_catalog_data(data):
            errors.append(f"{path.name}: {error}")
        if schema is not None:
            try:
                import jsonschema
                for error in jsonschema.Draft202012Validator(schema).iter_errors(data):
                    errors.append(f"{path.name}: schema: {error.message} at {list(error.absolute_path)}")
            except ImportError:
                pass
        catalogs[profile] = data
        names = {entry.get("name") for key in ("functions", "callbacks") for entry in data.get(key, []) if isinstance(entry, dict)}
        for item in data.get("dbeOnly", []):
            if not isinstance(item, dict) or not item.get("name") or not item.get("explanation"):
                errors.append(f"{path.name}: every DBE-only entry needs a name and explanation")
            elif item["name"] in names:
                errors.append(f"{path.name}: DBE-only name {item['name']} is also a source entry")
        if any(entry.get("dbeBinding", {}).get("status") == "unclassified" for key in ("functions", "callbacks") for entry in data.get(key, []) if isinstance(entry, dict)):
            errors.append(f"{path.name}: unclassified DBE mapping remains")
    if len(catalogs) == len(PROFILES):
        errors.extend(validate_manifest(ROOT, catalogs))
        errors.extend(validate_profile_differences(catalogs))
        import extract_catalog
        errors.extend(validate_dbe_only_reconciliation(catalogs, extract_catalog._dbe_bindings()))
    if args.write_evidence_report and len(catalogs) == len(PROFILES):
        report_path = args.write_evidence_report if args.write_evidence_report.is_absolute() else ROOT / args.write_evidence_report
        report_path.parent.mkdir(parents=True, exist_ok=True)
        report_path.write_text(generate_evidence_report(ROOT, catalogs, evidence_runs), encoding="utf-8")
        print(f"Psych Lua evidence report written: {report_path}")
    if args.final_gate and len(catalogs) == len(PROFILES):
        errors.extend(validate_final_evidence(ROOT, catalogs, evidence_runs))
    if args.fetch_pinned_sources:
        import extract_catalog
        sources = {source["profile"]: source for source in lock["sources"]}
        try:
            with tempfile.TemporaryDirectory(prefix="psych-contracts-") as temp:
                for profile in PROFILES:
                    repo = fetch_source(sources[profile], Path(temp))
                    inventory = extract_catalog.scan_tree(repo)
                    catalog = _read_json(CONTRACTS / f"psych-{profile}.json")
                    source_names = {(entry["kind"], entry["name"], entry["source"]["path"], entry["source"]["line"]) for key in ("functions", "callbacks") for entry in catalog[key]}
                    extracted = {(entry["kind"], entry["name"], entry["source"]["path"], entry["source"]["line"]) for key in ("functions", "callbacks") for entry in inventory[key]}
                    if extracted != source_names:
                        errors.append(f"{profile}: catalog inventory differs from fetched source (missing={len(extracted-source_names)}, extra={len(source_names-extracted)})")
                    print(f"{profile}: tag/commit and source snapshot SHA-256 verified")
        except (OSError, ValueError, subprocess.CalledProcessError) as exc:
            errors.append(f"source fetch/verification failed: {exc}")
    if errors:
        label = "Final compatibility gate rejected" if args.final_gate else "Contract validation failed"
        print(f"{label}: {len(errors)} finding(s).")
        if args.final_gate:
            not_verified = sum(": not-verified contract remains" in error for error in errors)
            fixture_results = sum(": no passing fixture result" in error for error in errors)
            print(f"  {not_verified} not-verified contract(s); {fixture_results} compatible/adapted contract(s) missing passing fixture evidence.")
        display_errors = errors[:30] if args.final_gate else errors
        for error in display_errors:
            print(f"  - {error}")
        if len(display_errors) < len(errors):
            print(f"  - ... {len(errors) - len(display_errors)} more finding(s); see docs/compatibility/COMPATIBILITY-EVIDENCE.md")
        return 1
    print("Both Psych contract catalogs are structurally valid.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
