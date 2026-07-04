#!/bin/bash
set -Eeuo pipefail

SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
cd "${SCRIPT_DIR}"

STRICT=false
if [ "${1:-}" = "--strict" ]; then
    STRICT=true
    shift
fi

if [ "$#" -ne 0 ]; then
    echo "Usage: $0 [--strict]" >&2
    exit 2
fi

python3 - "$STRICT" <<'PY'
import json
import pathlib
import re
import subprocess
import sys

repo = pathlib.Path.cwd()
strict = sys.argv[1] == "true"

missing = []
legacy_refs = []
declared_count = 0


def resolve_patch(build_file: pathlib.Path, ref: str):
    candidates = []
    path = pathlib.Path(ref)
    if path.is_absolute():
        candidates.append(path)
    else:
        candidates.append(build_file.parent / ref)
        candidates.append(repo / ref)
        candidates.append(repo / "patches" / ref)
    for candidate in candidates:
        if candidate.is_file():
            return candidate
    return None


def rel(path: pathlib.Path) -> str:
    try:
        return str(path.resolve().relative_to(repo))
    except ValueError:
        return str(path)


build_files = sorted(
    p for p in repo.glob("*/BUILD")
    if p.is_file() and not p.parts[-2].startswith(".")
)
for build_file in build_files:
    proc = subprocess.run(
        [str(repo / "builder.sh"), "--print-meta", str(build_file)],
        cwd=repo,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    if proc.returncode != 0:
        print(proc.stderr, end="", file=sys.stderr)
        print(f"ERROR: failed to read metadata from {rel(build_file)}", file=sys.stderr)
        sys.exit(proc.returncode)

    meta = json.loads(proc.stdout)
    for ref in meta.get("patch_files", []):
        declared_count += 1
        if resolve_patch(build_file, ref) is None:
            missing.append((rel(build_file), ref))

    text = build_file.read_text(encoding="utf-8", errors="ignore")
    patterns = [
        r"\$\{?PATCH_FILE_ROOT\}?/([^\s'\";&|<>]+)",
        r"\$\{?native_project_root\}?/patches/([^\s'\";&|<>]+)",
        r"(?<![\w/])\.\./patches/([^\s'\";&|<>]+)",
    ]
    seen = set()
    for pattern in patterns:
        for match in re.findall(pattern, text):
            key = (rel(build_file), match)
            if key not in seen:
                seen.add(key)
                legacy_refs.append(key)

for build_file, ref in missing:
    print(f"ERROR: declared patch not found: {build_file}: {ref}", file=sys.stderr)

for build_file, ref in legacy_refs:
    print(f"WARNING: legacy root patch reference: {build_file}: {ref}", file=sys.stderr)

print(
    f"patch lint: {len(build_files)} BUILD files, "
    f"{declared_count} declared patch files, "
    f"{len(legacy_refs)} legacy root references"
)

if missing or (strict and legacy_refs):
    sys.exit(1)
PY
