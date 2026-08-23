#!/usr/bin/env python3
"""Flags a confirmed V codegen hazard: narrowing an interface value to a
CONCRETE type via `if x is T { ... }` and then calling a method on x inside
that same block.

See CONTRIBUTING.md's "Narrowing a shared interface" section and
server/entity/actor.v's own doc comment. The safe pattern, used everywhere
this codebase actually does this (see as_network_session/as_entity-style
helpers), is: narrow and return the concrete value from inside the block,
then call methods on it from outside that scope.

Narrowing one interface to ANOTHER interface (e.g. item.Item to
item.ConsumableItem) is a different code path and was verified separately,
empirically, not to share this bug. This
script excludes any `is T` where T is itself a declared interface and
only flags narrows to a concrete struct/type - matching the actually
confirmed hazard shape, not a broader guess.

This remains a heuristic, not a type checker: interface names are collected
textually (every `interface Name {` declaration under the scanned roots),
so a target type declared outside those roots would not be recognized and
could produce a false positive - acceptable, since a false positive here is
cheap to review and a false negative is the expensive failure mode.

Usage: scripts/check_interface_narrowing.py [path ...]
Exit code 1 if any hazard is found, 0 otherwise.
"""

import re
import sys
from pathlib import Path

IF_IS_RE = re.compile(r"\bif\s+(?:mut\s+)?(\w+)\s+is\s+&?(\w+)(?:\s*\[[^\]]*\])?\s*\{")
INTERFACE_DECL_RE = re.compile(r"^\s*(?:pub\s+)?interface\s+(\w+)\s*\{", re.MULTILINE)


def strip_comments_and_strings(text: str) -> str:
    """Replaces string/char literal and comment contents with spaces so brace
    matching and method-call detection never trips on `{`, `}` or `.` inside
    them, while preserving line numbers (newlines are kept as-is)."""
    out = []
    i = 0
    n = len(text)
    while i < n:
        c = text[i]
        if c == "/" and i + 1 < n and text[i + 1] == "/":
            j = text.find("\n", i)
            j = n if j == -1 else j
            out.append(" " * (j - i))
            i = j
            continue
        if c == "/" and i + 1 < n and text[i + 1] == "*":
            j = text.find("*/", i + 2)
            j = n if j == -1 else j + 2
            chunk = text[i:j]
            out.append("".join(ch if ch == "\n" else " " for ch in chunk))
            i = j
            continue
        if c in "\"'":
            quote = c
            j = i + 1
            while j < n and text[j] != quote:
                if text[j] == "\\" and j + 1 < n:
                    j += 2
                    continue
                j += 1
            j = min(j + 1, n)
            chunk = text[i:j]
            out.append("".join(ch if ch == "\n" else " " for ch in chunk))
            i = j
            continue
        out.append(c)
        i += 1
    return "".join(out)


def collect_interface_names(files: list[Path]) -> set[str]:
    names: set[str] = set()
    for f in files:
        raw = f.read_text(encoding="utf-8", errors="replace")
        clean = strip_comments_and_strings(raw)
        names.update(m.group(1) for m in INTERFACE_DECL_RE.finditer(clean))
    return names


def find_hazards(path: Path, interface_names: set[str]) -> list[tuple[int, str]]:
    raw = path.read_text(encoding="utf-8", errors="replace")
    clean = strip_comments_and_strings(raw)
    hazards = []
    for m in IF_IS_RE.finditer(clean):
        ident, target_type = m.group(1), m.group(2)
        if target_type in interface_names:
            continue
        brace_start = m.end() - 1
        depth = 0
        j = brace_start
        block_end = len(clean)
        while j < len(clean):
            if clean[j] == "{":
                depth += 1
            elif clean[j] == "}":
                depth -= 1
                if depth == 0:
                    block_end = j
                    break
            j += 1
        body = clean[brace_start + 1 : block_end]
        call_re = re.compile(r"\b" + re.escape(ident) + r"\.\w+\s*\(")
        call = call_re.search(body)
        if call:
            line_no = clean.count("\n", 0, brace_start + 1 + call.start()) + 1
            snippet = raw.splitlines()[line_no - 1].strip()
            hazards.append((line_no, snippet))
    return hazards


def main(argv: list[str]) -> int:
    roots = [Path(p) for p in argv] or [Path("server")]
    files: list[Path] = []
    for root in roots:
        if root.is_file():
            files.append(root)
        else:
            files.extend(sorted(root.rglob("*.v")))

    interface_names = collect_interface_names(files)

    found = False
    for f in files:
        for line_no, snippet in find_hazards(f, interface_names):
            found = True
            print(f"{f}:{line_no}: possible interface-narrowing codegen hazard: {snippet}")

    if found:
        print()
        print(
            "One or more `if x is T { ... x.method(...) ... }` blocks narrow to a "
            "concrete type T and call a method on the narrowed value inside the "
            "same block - a confirmed V codegen hazard (see CONTRIBUTING.md). "
            "Narrow and return the concrete value instead, then call methods on "
            "it outside the block."
        )
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
