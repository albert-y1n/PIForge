#!/usr/bin/env python3
"""Download a released PIForge attacker checkpoint from Hugging Face."""

import argparse
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CATALOG = ROOT / "checkpoints" / "models.json"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("model", nargs="?", help="Model ID or short name from --list")
    parser.add_argument("--all", action="store_true", help="Download every released model")
    parser.add_argument("--list", action="store_true", help="List released models")
    parser.add_argument("--output-dir", type=Path, default=ROOT / "checkpoints")
    args = parser.parse_args()

    catalog = json.loads(CATALOG.read_text())
    models = catalog["models"]
    if args.list:
        for model in models:
            print(f'{model["id"]}  {model["url"]}')
        return
    if args.all:
        selected = models
    elif args.model:
        selected = [m for m in models if args.model in (m["id"], m["id"].split("/", 1)[1])]
        if not selected:
            parser.error(f"Unknown model: {args.model}. Use --list to see available models.")
    else:
        parser.error("Pass a model ID, --all, or --list.")

    from huggingface_hub import snapshot_download

    for model in selected:
        destination = args.output_dir / model["id"].split("/", 1)[1]
        print(f'Downloading {model["id"]} to {destination}')
        snapshot_download(repo_id=model["id"], local_dir=destination)


if __name__ == "__main__":
    main()
