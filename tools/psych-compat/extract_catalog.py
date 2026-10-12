#!/usr/bin/env python3
"""Extract name/location inventories from a pinned Psych source tree."""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DBE_LUA = ROOT / "source/funkin/backend/scripting/LuaScript.hx"
DBE_HOOKS = ROOT / "source/cne/compat/PsychHookMap.hx"
PROFILES = {
    "0.6.3": ("eb0ade39e8d1c5437db2166a9ddb6eb3c05956e1", "0.6.3"),
    "1.0.4": ("5c67ced49e5a98535298a6daa3f8f4ec79ac8399", "1.0.4"),
}


def _files(root: Path):
    for path in root.rglob("*"):
        if path.is_file() and path.suffix.lower() in {".hx", ".lua"}:
            yield path


def _lines(path: Path):
    try:
        return path.read_text(encoding="utf-8-sig", errors="replace").splitlines()
    except OSError:
        return []


def _strip_comments(text: str):
    """Remove Haxe/Lua comments while preserving line numbers and strings."""
    result = []
    index = 0
    quote = None
    escaped = False
    line_comment = False
    block_comment = False
    while index < len(text):
        char = text[index]
        next_char = text[index + 1] if index + 1 < len(text) else ""
        if line_comment:
            if char == "\n":
                line_comment = False
                result.append(char)
            else:
                result.append(" ")
            index += 1
            continue
        if block_comment:
            if char == "*" and next_char == "/":
                result.extend((" ", " "))
                block_comment = False
                index += 2
            else:
                result.append("\n" if char == "\n" else " ")
                index += 1
            continue
        if quote is not None:
            result.append(char)
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == quote:
                quote = None
            index += 1
            continue
        if char in ("'", '"'):
            quote = char
            result.append(char)
            index += 1
            continue
        if char == "/" and next_char == "*":
            result.extend((" ", " "))
            block_comment = True
            index += 2
            continue
        if (char == "/" and next_char == "/") or (char == "-" and next_char == "-"):
            result.extend((" ", " "))
            line_comment = True
            index += 2
            continue
        result.append(char)
        index += 1
    return "".join(result)


def _dbe_bindings(path: Path = DBE_LUA):
    names = {}
    pattern = re.compile(r'(?:callbackScope\.)?bind\(\s*["\']([A-Za-z_][A-Za-z0-9_]*)["\']')
    for line_no, line in enumerate(_lines(path), 1):
        for name in pattern.findall(line):
            names.setdefault(name, line_no)
    return names


def _dbe_callbacks(path: Path = DBE_HOOKS):
    names = set()
    for line in _lines(path):
        if ":" in line and "[" in line and "]" in line:
            rhs = line.split(":", 1)[1]
            names.update(re.findall(r'["\']([A-Za-z_][A-Za-z0-9_]*)["\']', rhs))
    return names


def _entry(name, kind, relpath, line, binding):
    matched = name in binding
    if matched and kind == "function":
        binding_status = "matched"
        binding_name = name
        binding_explanation = "A same-name LuaScript binding was located; this is inventory evidence only, not behavioral proof."
    elif matched:
        binding_status = "matched"
        binding_name = name
        binding_explanation = "A same-name PsychHookMap target was located; this is dispatch inventory evidence only, not behavioral proof."
    elif kind == "callback":
        binding_status = "dynamic"
        binding_name = name
        binding_explanation = "LuaScript dispatch uses PsychHookMap.getHooks, whose default [engineHook] branch passes unmapped callback names through unchanged; timing, arguments, and runtime delivery remain not verified."
    else:
        binding_status = "unmatched"
        binding_name = None
        binding_explanation = "No same-name LuaScript binding was located; aliases and dynamic registrations remain not verified."
    entry = {
        "name": name,
        "kind": kind,
        "status": "not-verified",
        "dbeBinding": {
            "status": binding_status,
            "name": binding_name,
            "explanation": binding_explanation,
        },
        "fixtureId": None,
        "source": {"path": relpath.replace("\\", "/"), "line": line},
        "evidence": {"kind": "source-inventory", "note": "Name and line extracted mechanically from the pinned source; semantics are not yet reviewed."}
    }
    if kind == "function":
        entry.update({
            "signature": {"parameters": [], "variadic": False, "observation": "not-extracted"},
            "defaults": {"observation": "not-extracted"},
            "return": {"type": "unknown", "conversion": "not-extracted"},
            "effects": [],
            "preconditions": [],
            "platform": {"targets": ["unknown"], "buildRequirements": []},
            "errors": {"behavior": "not-verified"},
        })
    else:
        entry.update({
            "eventSource": "not-verified",
            "triggerBoundary": "not-verified",
            "order": [],
            "arguments": [],
            "returnCancellation": "not-verified",
        })
    return entry


def scan_tree(root: Path):
    """Extract public Lua registrations and statically named callback dispatches."""
    binding = _dbe_bindings()
    functions = {}
    callbacks = {}
    # The upstream Lua bridge registers callable API names across FunkinLua and
    # psychlua helper modules via Lua_helper.add_callback.
    api_re = re.compile(r'\bLua_helper\.add_callback\(\s*lua\s*,\s*["\']([A-Za-z_][A-Za-z0-9_]*)["\']\s*,')
    # Statically named calls to script dispatchers identify callback source sites.
    callback_re = re.compile(r'\b(?:callOnLuas|callOnScripts|callOnHScript|callOnHScript)\(\s*["\']([A-Za-z_][A-Za-z0-9_]*)["\']')
    callback_binding = _dbe_callbacks()
    for path in _files(root):
        relpath = path.relative_to(root).as_posix()
        clean_lines = _strip_comments("\n".join(_lines(path))).splitlines()
        for line_no, text in enumerate(clean_lines, 1):
            for name in api_re.findall(text):
                functions.setdefault(name, _entry(name, "function", relpath, line_no, binding))
            for name in callback_re.findall(text):
                callbacks.setdefault(name, _entry(name, "callback", relpath, line_no, callback_binding))
    return {
        "functions": sorted(functions.values(), key=lambda item: item["name"].casefold()),
        "callbacks": sorted(callbacks.values(), key=lambda item: item["name"].casefold()),
        "dbeOnly": [
            {
                "name": name,
                "classification": "dbe-surface-only",
                "explanation": "DBE registers this Lua API, but the pinned Psych source inventory has no same-name function. This is a Lua API-surface difference only; the behavior remains unverified.",
                "bindingSource": {
                    "path": DBE_LUA.relative_to(ROOT).as_posix(),
                    "line": binding[name],
                },
            }
            for name in sorted(set(binding) - set(functions), key=str.casefold)
        ],
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--source-root", required=True, type=Path)
    parser.add_argument("--profile", required=True, choices=PROFILES)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--catalog", action="store_true", help="write a full not-verified catalog using the source lock metadata")
    args = parser.parse_args()
    inventory = scan_tree(args.source_root)
    if args.catalog:
        lock_path = ROOT / "docs/compatibility/contracts/source-lock.json"
        lock = json.loads(lock_path.read_text(encoding="utf-8"))
        source = next(entry for entry in lock["sources"] if entry["profile"] == args.profile)
        inventory = {
            "schemaVersion": 1,
            "profile": args.profile,
            "source": {key: source[key] for key in ("repository", "tag", "commit", "snapshotSha256")},
            "profileDifferences": [],
            **inventory,
        }
    else:
        inventory["profile"] = args.profile
        inventory["sourceCommit"] = PROFILES[args.profile][0]
    text = json.dumps(inventory, indent=2, ensure_ascii=False) + "\n"
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(text, encoding="utf-8")
    else:
        print(text, end="")


if __name__ == "__main__":
    main()
