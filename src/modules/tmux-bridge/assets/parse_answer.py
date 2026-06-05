#!/usr/bin/env python3
# parse_answer.py — deterministic extraction + validation of an interactive Claude
# answer from a raw tmux pipe-pane stream. NO model inference; pure parsing.
#
# Kept as a standalone, importable module (not inlined in the .sh.tpl) so it can be
# unit-tested directly. claude-tmux invokes it as: python3 parse_answer.py <rawlog>
# with BEGIN_MARK / END_MARK / OUTPUT_FORMAT / JSON_SCHEMA in the environment.
#
# Exit codes mirror the bridge contract:
#   0 ok · 1 sentinels not found · 4 JSON requested but invalid / schema mismatch.

import sys
import os
import re
import json


def clean_stream(raw: str) -> str:
    """Strip CSI/charset/OSC escapes and CRs from a raw PTY stream."""
    raw = re.sub(r"\x1b\[[0-9;?]*[A-Za-z]", "", raw)
    raw = re.sub(r"\x1b[()][AB0]", "", raw)
    raw = re.sub(r"\x1b\].*?(?:\x07|\x1b\\)", "", raw)  # OSC (titles)
    raw = raw.replace("\r", "\n")
    return raw


def _marker_regex(mark: str) -> "re.Pattern[str]":
    """Match a marker even if the TUI line-wrapped it (whitespace — including a
    newline + gutter — spliced between characters at the column boundary)."""
    return re.compile(r"\s*".join(re.escape(c) for c in mark))


def extract_between(raw: str, begin: str, end: str) -> str:
    """Return the answer between the LAST begin marker and the first end marker
    after it.

    WHY "last begin": the prompt we inject CONTAINS the marker literals (as the
    output-protocol instruction), and the TUI echoes the typed prompt back into the
    stream BEFORE the answer. So begin/end each appear twice — once in the echoed
    prompt, once around the real answer. The real answer is always the LAST
    begin→end pair; taking the first begin would return the echoed instruction.

    Falls back to a whitespace-tolerant match when the literal marker isn't present
    (line-wrap case)."""
    # Fast path: literal markers present. Take the LAST begin, then the first end
    # that follows it.
    bi = raw.rfind(begin)
    if bi != -1:
        ei = raw.find(end, bi + len(begin))
        if ei != -1:
            return raw[bi + len(begin):ei]
    # Slow path: a marker got line-wrapped. Match tolerantly; take the last begin
    # and the first end after it.
    b_matches = list(_marker_regex(begin).finditer(raw))
    if b_matches:
        last_b = b_matches[-1]
        e_match = _marker_regex(end).search(raw, last_b.end())
        if e_match:
            return raw[last_b.end():e_match.start()]
    raise ValueError("sentinels not found")


def strip_chrome(answer: str) -> str:
    """Remove TUI box-drawing, prompt gutter, and spinner glyphs from the answer."""
    lines = []
    for ln in answer.split("\n"):
        ln = re.sub(r"[│╭╮╯╰─┌┐└┘├┤┬┴┼>]", "", ln)
        ln = re.sub(r"[⠁-⣿]", "", ln)  # braille spinner
        lines.append(ln.rstrip())
    return "\n".join(lines).strip()


def first_json_object(text: str):
    """Find and parse the first balanced {...} JSON object in text, or None."""
    start = text.find("{")
    while start != -1:
        depth = 0
        for k in range(start, len(text)):
            c = text[k]
            if c == "{":
                depth += 1
            elif c == "}":
                depth -= 1
                if depth == 0:
                    try:
                        return json.loads(text[start:k + 1])
                    except json.JSONDecodeError:
                        break
        start = text.find("{", start + 1)
    return None


# ── Minimal, dependency-free JSON Schema check ──────────────────────────────────
# The `jsonschema` package is not guaranteed on the runner, so we validate the
# subset of JSON Schema that auto-dev actually uses: object `required`, scalar
# `type`, and `enum`. Returns a list of human-readable errors ([] = valid).
_TYPE_PYTHON = {
    "object": dict,
    "array": list,
    "string": str,
    "number": (int, float),
    "integer": int,
    "boolean": bool,
}


def schema_errors(obj, schema, path="$"):
    errors = []
    if not isinstance(schema, dict):
        return errors
    t = schema.get("type")
    if t and t in _TYPE_PYTHON:
        expected = _TYPE_PYTHON[t]
        # bool is a subclass of int — guard against a bool matching "integer"/"number"
        if t in ("integer", "number") and isinstance(obj, bool):
            errors.append(f"{path}: expected {t}, got boolean")
        elif not isinstance(obj, expected):
            errors.append(f"{path}: expected {t}, got {type(obj).__name__}")
    if "enum" in schema and obj not in schema["enum"]:
        errors.append(f"{path}: {obj!r} not in enum {schema['enum']}")
    if t == "object" and isinstance(obj, dict):
        for req in schema.get("required", []):
            if req not in obj:
                errors.append(f"{path}: missing required key '{req}'")
        props = schema.get("properties", {})
        for key, subschema in props.items():
            if key in obj:
                errors.extend(schema_errors(obj[key], subschema, f"{path}.{key}"))
    if t == "array" and isinstance(obj, list) and "items" in schema:
        for i, item in enumerate(obj):
            errors.extend(schema_errors(item, schema["items"], f"{path}[{i}]"))
    return errors


def parse(raw: str, begin: str, end: str, output_format: str, json_schema: str = ""):
    """Full pipeline. Returns (stdout_str, exit_code)."""
    raw = clean_stream(raw)
    try:
        answer = extract_between(raw, begin, end)
    except ValueError:
        return ("", 1)
    text = strip_chrome(answer)
    if output_format != "json":
        return (text, 0)
    obj = first_json_object(text)
    if obj is None:
        return ("", 4)
    if json_schema:
        try:
            schema = json.loads(json_schema)
        except json.JSONDecodeError:
            schema = None
        if schema is not None:
            errs = schema_errors(obj, schema)
            if errs:
                sys.stderr.write("claude-tmux: JSON does not match schema:\n")
                sys.stderr.write("\n".join(errs) + "\n")
                return ("", 4)
    # Mirror `claude -p --output-format json`: wrap under structured_output.
    return (json.dumps({"structured_output": obj}), 0)


def main():
    raw = open(sys.argv[1], "rb").read().decode("utf-8", "replace")
    out, code = parse(
        raw,
        os.environ["BEGIN_MARK"],
        os.environ["END_MARK"],
        os.environ.get("OUTPUT_FORMAT", "text"),
        os.environ.get("JSON_SCHEMA", ""),
    )
    if code == 0:
        print(out)
    sys.exit(code)


if __name__ == "__main__":
    main()
