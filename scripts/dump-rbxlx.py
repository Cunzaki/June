#!/usr/bin/env python3
"""Fast Operation One rbxlx extractor — scripts + structure only."""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_SRC = Path(
    r"c:\Users\Cunza\AppData\Local\Volt\workspace\place 72920620366355 SEASON 3 Operation One.rbxlx"
)
OUT = ROOT / "dump"

SCRIPT_BLOCK = re.compile(
    r'<Item class="(?P<class>ModuleScript|LocalScript|Script)" referent="(?P<ref>\d+)">'
    r'<Properties>.*?<string name="Name"><!\[CDATA\[(?P<name>[^\]]*)\]\]></string>'
    r'.*?<ProtectedString name="Source"><!\[CDATA\[(?P<source>.*?)\]\]></ProtectedString>',
    re.DOTALL,
)

SERVICE = re.compile(
    r'<Item class="(?P<class>\w+)" referent="\d+"><Properties>.*?'
    r'<string name="Name"><!\[CDATA\[(?P<name>[^\]]+)\]\]></string></Properties>',
    re.DOTALL,
)


def main() -> int:
    src = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_SRC
    if not src.exists():
        print(f"missing: {src}")
        return 1

    OUT.mkdir(parents=True, exist_ok=True)
    scripts_dir = OUT / "scripts"
    scripts_dir.mkdir(exist_ok=True)

    print(f"reading {src.name}...")
    data = src.read_text(encoding="utf-8", errors="replace")

    index = []
    counts: dict[str, int] = {}
    for i, m in enumerate(SCRIPT_BLOCK.finditer(data)):
        cls = m.group("class")
        name = m.group("name") or f"script_{i}"
        ref = m.group("ref")
        source = m.group("source")
        safe = re.sub(r'[<>:"/\\|?*]', "_", name)[:60]
        fname = f"{safe}_{ref}.lua"
        path = scripts_dir / fname
        if len(source) > 250000:
            source = source[:250000] + "\n-- [truncated]\n"
        path.write_text(source, encoding="utf-8")
        counts[cls] = counts.get(cls, 0) + 1
        index.append({"file": fname, "class": cls, "name": name, "referent": ref, "bytes": len(source)})

    services = []
    for m in SERVICE.finditer(data[:5_000_000]):
        services.append({"class": m.group("class"), "name": m.group("name")})

    signatures = {
        "setup_health": data.count("function setup_health"),
        "Viewmodels": data.count("Viewmodels"),
        "ownership_calls": data.count("ownership("),
        "Health_XML": data.count("Health_XML"),
        "Garbage_parent": data.count('Name"><![CDATA[Garbage]]'),
        "ReplicatedStorage": data.count("ReplicatedStorage"),
    }

    (OUT / "scripts_index.json").write_text(json.dumps(index, indent=2), encoding="utf-8")
    (OUT / "signatures.json").write_text(json.dumps(signatures, indent=2), encoding="utf-8")
    (OUT / "services.json").write_text(json.dumps(services[:200], indent=2), encoding="utf-8")

    summary = {
        "place_id": 72920620366355,
        "source": str(src),
        "scripts": len(index),
        "script_counts": counts,
        "signatures": signatures,
    }
    (OUT / "structure.json").write_text(json.dumps(summary, indent=2), encoding="utf-8")

    (OUT / "INDEX.md").write_text(
        "\n".join(
            [
                "# Operation One Dump",
                "",
                f"Scripts: {len(index)}",
                f"Counts: {counts}",
                "",
                "See `scripts_index.json`, `signatures.json`, `services.json`.",
            ]
        ),
        encoding="utf-8",
    )

    print(f"done: {len(index)} scripts -> {OUT}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
