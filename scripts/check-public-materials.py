#!/usr/bin/env python3
"""Keep machine-specific evidence out of every file that would be published.

In a Git checkout this scans what Git would publish (tracked plus untracked, non-ignored
files). Outside Git it walks the tree and skips the ignored build, project and signing paths.
This is a privacy guard, not a substitute for a credential scanner or image review.
Run from any directory; diagnostics contain only file names, line numbers and rule names.
"""
import json
import os
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SELF = Path(__file__).resolve()
# Placeholder accounts that docs and tests may use, such as /Users/example/report.md.
PLACEHOLDER_USERS = r"(?:example|username|you)"
# RFC 2606 / 6761 names reserved for documentation and tests.
RESERVED_DOMAIN = r"(?:[A-Za-z0-9-]+\.)*(?:example\.(?:com|net|org)|test|example|invalid|localhost)(?!\.?[A-Za-z0-9-])"
RULES = {
    "personal home path": re.compile(rf"/(?:Users|home)/(?!{PLACEHOLDER_USERS}/)[^/\s]+/"),
    "private execution directory": re.compile(r"/private/tmp/claude-\d+/|/var/folders/|-[Uu]sers-[^/\s]+-[Pp]rojects-"),
    "physical device identifier": re.compile(r"\b[0-9A-Fa-f]{8}-[0-9A-Fa-f]{16}\b"),
    "private deployment link": re.compile(r"https?://[^\s/)]+\.icework\.space\b"),
    "non-reserved email address": re.compile(rf"[A-Za-z0-9._%+-]+@(?!{RESERVED_DOMAIN})(?:[A-Za-z0-9-]+\.)+[A-Za-z]{{2,}}\b"),
}
# Mirrors the ignored build, generated-project and signing paths in .gitignore.
SKIP_DIRS = {".git", ".build", ".swiftpm", "DerivedData", "build", "xcuserdata"}
SKIP_DIR_SUFFIXES = (".xcodeproj", ".xcworkspace", ".xcresult", ".xcarchive")
SKIP_FILES = {"Config/Local.xcconfig"}
JSON_SUFFIXES = {".json", ".xcstrings"}


def strings(value):
    if isinstance(value, str):
        yield value
    elif isinstance(value, dict):
        for child in value.values():
            yield from strings(child)
    elif isinstance(value, list):
        for child in value:
            yield from strings(child)


def publishable_files():
    try:
        listing = subprocess.run(
            ["git", "-C", str(ROOT), "ls-files", "-z", "--cached", "--others", "--exclude-standard"],
            capture_output=True, check=True,
        ).stdout.decode()
        return sorted(ROOT / name for name in listing.split("\0") if name)
    except (OSError, subprocess.CalledProcessError):
        pass
    files = []
    for directory, subdirectories, names in os.walk(ROOT):
        subdirectories[:] = [d for d in subdirectories if d not in SKIP_DIRS and not d.endswith(SKIP_DIR_SUFFIXES)]
        for name in names:
            path = Path(directory) / name
            if path.relative_to(ROOT).as_posix() not in SKIP_FILES:
                files.append(path)
    return sorted(files)


def findings(path):
    """Yields (line number or None, rule) pairs; binary files are left to manual review."""
    try:
        content = path.read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError):
        return
    if path.suffix in JSON_SUFFIXES:
        # Decode first: JSON encoders may escape "/" and hide paths from a raw-text match.
        for value in strings(json.loads(content)):
            for rule, pattern in RULES.items():
                if pattern.search(value):
                    yield None, rule
        return
    for number, line in enumerate(content.splitlines(), start=1):
        for rule, pattern in RULES.items():
            if pattern.search(line):
                yield number, rule


def main():
    errors = []
    scanned = 0
    for path in publishable_files():
        if path.resolve() == SELF or not path.is_file():
            continue
        scanned += 1
        name = path.relative_to(ROOT).as_posix()
        for number, rule in findings(path):
            errors.append(f"{name}: {rule}" if number is None else f"{name}:{number}: {rule}")
    for path in (ROOT / "docs/verification/assets").glob("*"):
        if path.suffix.lower() in {".jpg", ".jpeg", ".png", ".heic", ".webp"}:
            errors.append(f"{path.relative_to(ROOT)}: verification screenshots belong in a private archive")
    if errors:
        print("\n".join(sorted(set(errors))))
        return 1
    print(f"PASS: {scanned} publishable files; no personal paths, private execution paths, deployment links, "
          "device IDs, or non-reserved email addresses.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
