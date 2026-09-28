#!/usr/bin/env python3
"""Prints a machine-readable report of balanced-plate classification coverage
of the canonical nutrition catalog (protocol/nutrition/catalog.json).

Standard library only. Usage:

    python scripts/catalog-plate-report.py [path/to/catalog.json]
"""

import json
import sys
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DEFAULT_CATALOG = ROOT / "protocol/nutrition/catalog.json"


def build_report(catalog: dict) -> dict:
    foods = catalog["foods"]
    total = len(foods)
    groups = Counter()
    mixed = 0
    classified = 0
    for food in foods:
        plate = food.get("plate")
        if not plate:
            continue
        classified += 1
        groups[plate["group"]] += 1
        if plate.get("quality") == "mixed":
            mixed += 1
    unknown = total - classified
    coverage_percent = round(100 * classified / total, 2) if total else 0.0
    return {
        "total": total,
        "classified": classified,
        "unknown": unknown,
        "mixed": mixed,
        "coveragePercent": coverage_percent,
        "groups": dict(sorted(groups.items())),
    }


def main() -> int:
    path = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_CATALOG
    with path.open(encoding="utf-8") as f:
        catalog = json.load(f)
    print(json.dumps(build_report(catalog), indent=2, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
