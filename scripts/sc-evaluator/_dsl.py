#!/usr/bin/env python3
"""sc-evaluator journey DSL validator + step emitter.

Reads a journey YAML, validates it against the allowed step schema (see
SCHEMA.md), and prints a normalized tab-separated step stream on stdout for
run.sh to consume. Exits non-zero on any validation error.

Usage:
  _dsl.py <journey.yml>

Output format (one step per line, tab-separated):
  <index>\t<kind>\t<json-args>

Errors are written to stderr with the offending step name when applicable.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

try:
    import yaml
except ImportError as exc:  # pragma: no cover - environment guard
    sys.stderr.write(f"error: PyYAML required ({exc})\n")
    sys.exit(2)


# Allowed steps with their required and optional argument keys.
STEP_SCHEMA: dict[str, dict[str, bool]] = {
    "launch": {},
    "tap": {},  # either {x,y} or {accessibilityId} — validated below
    "longPress": {},  # same as tap; optional duration
    # `screenshot` accepts `label` (preferred, per US-018) or legacy `name`.
    # Validation lives in validate_step below; the normalized arg key is `label`.
    "screenshot": {},
    "assertVisible": {"accessibilityId": True},
    "assertText": {"text": True},
    "wait": {"seconds": True},
}


def fail(msg: str, step_index: int | None = None, step_name: str | None = None) -> None:
    where = ""
    if step_index is not None:
        where = f" at step #{step_index}"
        if step_name:
            where += f" ({step_name})"
    sys.stderr.write(f"error: {msg}{where}\n")
    sys.exit(2)


def validate_tap_like(step: dict, idx: int, kind: str) -> dict:
    has_xy = "x" in step and "y" in step
    has_aid = "accessibilityId" in step
    if has_xy and has_aid:
        fail(f"{kind} must specify EITHER (x,y) OR accessibilityId, not both", idx, kind)
    if not has_xy and not has_aid:
        fail(f"{kind} requires either (x,y) coordinates or accessibilityId", idx, kind)
    args: dict = {}
    if has_xy:
        for k in ("x", "y"):
            v = step[k]
            if not isinstance(v, (int, float)):
                fail(f"{kind}.{k} must be a number, got {type(v).__name__}", idx, kind)
            args[k] = float(v)
    else:
        aid = step["accessibilityId"]
        if not isinstance(aid, str) or not aid:
            fail(f"{kind}.accessibilityId must be a non-empty string", idx, kind)
        args["accessibilityId"] = aid
    if kind == "longPress":
        dur = step.get("duration", 1.0)
        if not isinstance(dur, (int, float)) or dur <= 0:
            fail("longPress.duration must be a positive number", idx, kind)
        args["duration"] = float(dur)
    return args


def validate_step(step: object, idx: int) -> tuple[str, dict]:
    if not isinstance(step, dict) or len(step) == 0:
        fail("each step must be a mapping with one key", idx)
        return ("", {})  # unreachable
    kind: str
    body: dict
    if "kind" in step:
        kind = step["kind"]
        body = {k: v for k, v in step.items() if k != "kind"}
    elif len(step) == 1:
        (only_key, only_val), = step.items()
        kind = only_key
        if only_val is None:
            body = {}
        elif isinstance(only_val, dict):
            body = only_val
        else:
            fail(f"step '{kind}' body must be a mapping or null", idx, kind)
            return ("", {})  # unreachable
    else:
        fail("step must use shorthand {kind: {...}} or explicit {kind: name, ...}", idx)
        return ("", {})  # unreachable

    if kind not in STEP_SCHEMA:
        allowed = ", ".join(sorted(STEP_SCHEMA.keys()))
        fail(f"unknown step '{kind}' (allowed: {allowed})", idx, kind)

    args: dict = {}
    if kind in ("tap", "longPress"):
        args = validate_tap_like(body, idx, kind)
    else:
        required = STEP_SCHEMA[kind]
        for key, is_required in required.items():
            if is_required and key not in body:
                fail(f"step '{kind}' missing required arg '{key}'", idx, kind)
            if key in body:
                args[key] = body[key]
        if kind == "assertText" and "accessibilityId" in body:
            if not isinstance(body["accessibilityId"], str):
                fail("assertText.accessibilityId must be a string", idx, kind)
            args["accessibilityId"] = body["accessibilityId"]
        if kind == "wait":
            v = args.get("seconds")
            if not isinstance(v, (int, float)) or v <= 0:
                fail("wait.seconds must be a positive number", idx, kind)
            args["seconds"] = float(v)
        if kind == "screenshot":
            # Accept either `label` (preferred) or legacy `name`. Normalize to `label`
            # in the emitted args so run.sh has a single field to read.
            label = body.get("label", body.get("name"))
            if not isinstance(label, str) or not label:
                fail("screenshot.label must be a non-empty string", idx, kind)
            # Drop legacy `name` if present; emit only `label`.
            args.pop("name", None)
            args["label"] = label
        if kind == "assertVisible":
            aid = args.get("accessibilityId")
            if not isinstance(aid, str) or not aid:
                fail("assertVisible.accessibilityId must be a non-empty string", idx, kind)
    return kind, args


def main() -> int:
    if len(sys.argv) != 2:
        sys.stderr.write("usage: _dsl.py <journey.yml>\n")
        return 2
    path = Path(sys.argv[1])
    if not path.is_file():
        sys.stderr.write(f"error: journey file not found: {path}\n")
        return 2
    try:
        doc = yaml.safe_load(path.read_text(encoding="utf-8"))
    except yaml.YAMLError as exc:
        sys.stderr.write(f"error: YAML parse failed in {path}: {exc}\n")
        return 2
    if doc is None:
        sys.stderr.write(f"error: journey {path} is empty\n")
        return 2
    if not isinstance(doc, dict):
        sys.stderr.write("error: top-level journey must be a mapping with a 'steps' key\n")
        return 2
    steps = doc.get("steps")
    if not isinstance(steps, list) or not steps:
        sys.stderr.write("error: journey requires a non-empty 'steps' list\n")
        return 2

    for idx, raw_step in enumerate(steps, start=1):
        kind, args = validate_step(raw_step, idx)
        sys.stdout.write(f"{idx}\t{kind}\t{json.dumps(args, sort_keys=True)}\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
