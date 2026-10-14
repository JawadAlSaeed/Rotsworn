"""Pastes a GOLDEN_REGEN block (saved from the test output) into tests/unit/test_choreography_golden.gd.

    python tools/regen_golden.py <file holding the output between GOLDEN_REGEN_BEGIN and _END>

Only for a deliberate change to the enemy choreography (an attack added or retimed, a retuned
combat_visuals.tres or tuning.tres): the test explains when.
"""
from __future__ import annotations

import re
import sys

TEST = "tests/unit/test_choreography_golden.gd"


def main() -> int:
    block = open(sys.argv[1], encoding="utf-8-sig").read()
    new_hash = re.search(r'const EXPECTED_HASH := "([0-9a-f]+)"', block).group(1)
    entries = re.findall(r'^\s*"([a-z0-9_]+)": "([0-9a-f]+)",\s*$', block, re.M)
    s = open(TEST, encoding="utf-8").read()
    s = re.sub(r'const EXPECTED_HASH := "[0-9a-f]+"', 'const EXPECTED_HASH := "%s"' % new_hash, s)
    body = "".join('\t"%s": "%s",\n' % e for e in entries)
    s = re.sub(r"(const EXPECTED_BY_ATTACK: Dictionary = \{\n)(.*?)(\})", lambda m: m.group(1) + body + m.group(3),
               s, flags=re.S)
    s = re.sub(r"const EXPECTED_ATTACKS: int = \d+", "const EXPECTED_ATTACKS: int = %d" % len(entries), s)
    open(TEST, "w", encoding="utf-8", newline="\n").write(s)
    print("golden: %d attacks" % len(entries))
    return 0


if __name__ == "__main__":
    sys.exit(main())
