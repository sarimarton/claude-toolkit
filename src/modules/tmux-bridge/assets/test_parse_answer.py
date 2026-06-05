#!/usr/bin/env python3
# Unit tests for parse_answer.py — the deterministic stream parser of claude-tmux.
# Run: python3 test_parse_answer.py   (stdlib unittest, no dependencies)

import unittest
import parse_answer as P

UNIQ = "T_1"
B = f"<<<CLAUDE_TMUX_BEGIN_{UNIQ}>>>"
E = f"<<<CLAUDE_TMUX_END_{UNIQ}>>>"

# A realistic raw PTY frame: ANSI, box-drawing chrome, spinner, sentinels.
def frame(body: str) -> str:
    return (
        "\x1b[2J\x1b[H╭───────────╮\n"
        "│ ❯ echo of prompt │\n"
        "\x1b[58G⠋ Working…\n"
        f"│ {B}\n"
        f"│ {body}\n"
        f"│ {E}\n"
        "╰───────────╯\n❯ \n"
    )

AUTODEV_SCHEMA = (
    '{"type":"object","properties":'
    '{"decision":{"type":"string","enum":["epic","clarify","ready","blocked"]},'
    '"summary":{"type":"string"}},"required":["decision"]}'
)


class TestExtraction(unittest.TestCase):
    def test_text_mode_strips_chrome(self):
        out, code = P.parse(frame("hello world"), B, E, "text")
        self.assertEqual(code, 0)
        self.assertEqual(out, "hello world")

    def test_json_mode_wraps_structured_output(self):
        out, code = P.parse(frame('{"decision": "ready"}'), B, E, "json")
        self.assertEqual(code, 0)
        self.assertEqual(out, '{"structured_output": {"decision": "ready"}}')

    def test_missing_sentinels_exit_1(self):
        out, code = P.parse("no markers here at all", B, E, "text")
        self.assertEqual(code, 1)

    def test_invalid_json_exit_4(self):
        out, code = P.parse(frame("not json {oops"), B, E, "json")
        self.assertEqual(code, 4)

    def test_prompt_echo_does_not_leak_into_answer(self):
        # Regression for the live-run bug: the injected prompt CONTAINS the marker
        # literals (as the output-protocol instruction), and the TUI echoes the
        # typed prompt back BEFORE the answer. So BEGIN/END each appear twice — once
        # in the echoed prompt, once around the real answer. The extractor must
        # return the real answer (the LAST begin→end pair), not the echoed prompt.
        echoed_prompt = (
            "❯ Compute 17*3.\n"
            "  OUTPUT PROTOCOL (parsed by a script):\n"
            f"  Print the line {B} on its own line, then your answer, then {E}.\n"
            "  ⠋ Working…\n"
        )
        real_answer = f"{B}\n51\n{E}\n❯ \n"
        out, code = P.parse(echoed_prompt + real_answer, B, E, "text")
        self.assertEqual(code, 0)
        self.assertEqual(out, "51")

    def test_prompt_echo_json_mode(self):
        # Same collision, JSON mode: the echoed protocol text must not be mistaken
        # for the answer object.
        echoed_prompt = (
            f"❯ Reply JSON. Print {B} then the object then {E}.\n"
            "  ⠋ Working…\n"
        )
        real_answer = f'{B}\n{{"decision": "ready"}}\n{E}\n❯ \n'
        out, code = P.parse(echoed_prompt + real_answer, B, E, "json")
        self.assertEqual(code, 0)
        self.assertEqual(out, '{"structured_output": {"decision": "ready"}}')


class TestSchemaValidation(unittest.TestCase):
    """The bridge degrades --json-schema to a soft prompt instruction, so it MUST
    validate the returned object client-side. A schema-violating-but-valid-JSON
    answer has to be rejected (exit 4), not passed through."""

    def test_schema_conforming_passes(self):
        out, code = P.parse(
            frame('{"decision": "ready", "summary": "do it"}'),
            B, E, "json", AUTODEV_SCHEMA,
        )
        self.assertEqual(code, 0)
        self.assertIn('"structured_output"', out)

    def test_enum_violation_rejected(self):
        # "maybe" is valid JSON but not in the decision enum → must be exit 4.
        out, code = P.parse(
            frame('{"decision": "maybe"}'),
            B, E, "json", AUTODEV_SCHEMA,
        )
        self.assertEqual(code, 4)

    def test_missing_required_key_rejected(self):
        out, code = P.parse(
            frame('{"summary": "no decision field"}'),
            B, E, "json", AUTODEV_SCHEMA,
        )
        self.assertEqual(code, 4)

    def test_wrong_scalar_type_rejected(self):
        out, code = P.parse(
            frame('{"decision": 123}'),
            B, E, "json", AUTODEV_SCHEMA,
        )
        self.assertEqual(code, 4)


if __name__ == "__main__":
    unittest.main(verbosity=2)
