#!/usr/bin/env python3
"""Check pinned agent download paths and find recently added GGUF files."""

import argparse
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timedelta, timezone
import json
import os
from pathlib import Path
import re
import sys
from urllib.request import Request, urlopen


def configured_files(scripts_dir: Path) -> dict[str, set[str]]:
    repositories: dict[str, set[str]] = {}
    for script in sorted(scripts_dir.glob("download-*.sh")):
        source = script.read_text()
        repo_match = re.search(r'^REPO="([^"]+)"', source, re.MULTILINE)
        if repo_match:
            files = set(re.findall(r'^\s+"([^"\n]+\.(?:gguf|bin))"\s*$', source, re.MULTILINE))
            files.update(re.findall(r'\b(?:MODELS|FILES)\+?=\("([^"\n]+\.(?:gguf|bin))"\)', source))
            single = re.search(r'^MODEL="([^"]+)"', source, re.MULTILINE)
            if single:
                files.add(single.group(1))
            if not files:
                raise ValueError(f"no model files found in {script}")
            repositories.setdefault(repo_match.group(1), set()).update(files)
        else:
            pairs = re.findall(r'^\s+"([^|"\n]+)\|([^|"\n]+)\|', source, re.MULTILINE)
            if not pairs:
                raise ValueError(f"no model files found in {script}")
            for repo, file in pairs:
                repositories.setdefault(repo, set()).add(file)
    return repositories


def tree(repo: str, token: str) -> tuple[str, dict[str, dict]]:
    url = f"https://huggingface.co/api/models/{repo}/tree/main?recursive=true&expand=true"
    files: dict[str, dict] = {}
    headers = {"Authorization": f"Bearer {token}"} if token else {}
    while url:
        with urlopen(Request(url, headers=headers), timeout=30) as response:
            for entry in json.load(response):
                if entry["type"] == "file":
                    files[entry["path"]] = entry
            link = response.headers.get("Link", "")
            next_page = re.search(r'<([^>]+)>; rel="next"', link)
            url = next_page.group(1) if next_page else ""
    return repo, files


def modified_since(entry: dict, cutoff: datetime) -> bool:
    commit = entry.get("lastCommit") or {}
    date = commit.get("date")
    return bool(date and datetime.fromisoformat(date.replace("Z", "+00:00")) >= cutoff)


def grouped_files(paths: list[str]) -> list[str]:
    groups: dict[str, int] = {}
    for path in paths:
        shard = re.fullmatch(r"(.*)-\d{5}-of-\d{5}\.gguf", path)
        label = f"{shard.group(1)}.gguf" if shard else path
        groups[label] = groups.get(label, 0) + 1
    return [f"{path} ({count} shards)" if count > 1 else path
            for path, count in sorted(groups.items())]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--since-days", type=int, default=30, help="recent-file window (default: 30)")
    args = parser.parse_args()
    if args.since_days < 0:
        parser.error("--since-days must be nonnegative")

    repositories = configured_files(Path(__file__).resolve().parent)
    token = os.environ.get("HF_TOKEN") or os.environ.get("HUGGING_FACE_HUB_TOKEN") or ""
    cutoff = datetime.now(timezone.utc) - timedelta(days=args.since_days)
    missing = 0
    try:
        with ThreadPoolExecutor(max_workers=6) as pool:
            results = dict(pool.map(lambda repo: tree(repo, token), sorted(repositories)))
    except Exception as error:
        print(f"Could not check Hugging Face: {error}", file=sys.stderr)
        return 2

    for repo, wanted in sorted(repositories.items()):
        available = results[repo]
        absent = sorted(wanted - available.keys())
        recent_selected = sorted(path for path in wanted if path in available and modified_since(available[path], cutoff))
        recent_extra = sorted(path for path, entry in available.items()
                              if path.endswith(".gguf") and path not in wanted and modified_since(entry, cutoff))
        missing += len(absent)
        print(f"{repo}: {len(wanted) - len(absent)}/{len(wanted)} configured files present")
        for path in absent:
            print(f"  MISSING  {path}")
        for path in grouped_files(recent_selected):
            print(f"  UPDATED  {path}")
        for path in grouped_files(recent_extra):
            print(f"  OTHER    {path}")
    print(f"Checked {len(repositories)} repositories; {missing} missing configured files.")
    print("UPDATED means changed within the selected time window; OTHER is a recent GGUF not selected by a downloader.")
    return 1 if missing else 0


if __name__ == "__main__":
    raise SystemExit(main())
