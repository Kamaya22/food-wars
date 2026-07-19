#!/usr/bin/env python3
"""Compile les sources YAML de content/source/ en content/compiled/content.json.

Usage:  python scripts/build_content.py
Dépendance: pip install pyyaml
"""
import json
import sys
from pathlib import Path

try:
    import yaml
except ImportError:
    sys.exit("PyYAML requis : pip install pyyaml")

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "content" / "source"
OUT = ROOT / "content" / "compiled" / "content.json"

# fichier source -> clé dans le JSON final (les 5 premiers sont des listes)
LIST_FILES = {
    "ingredients": "ingredients",
    "actions": "actions",
    "cards": "cards",
    "events": "events",
    "criteria": "criteria",
}

def main() -> None:
    data = {}
    for stem, key in LIST_FILES.items():
        path = SRC / f"{stem}.yaml"
        if not path.exists():
            sys.exit(f"Source manquante : {path}")
        with path.open(encoding="utf-8") as f:
            data[key] = yaml.safe_load(f) or []

    cfg_path = SRC / "match_config.yaml"
    if not cfg_path.exists():
        sys.exit(f"Source manquante : {cfg_path}")
    with cfg_path.open(encoding="utf-8") as f:
        data["match_config"] = yaml.safe_load(f) or {}

    OUT.parent.mkdir(parents=True, exist_ok=True)
    with OUT.open("w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
    print(f"Écrit : {OUT}")

if __name__ == "__main__":
    main()
