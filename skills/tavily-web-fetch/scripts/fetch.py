#!/usr/bin/env python3
"""Fetch raw content from web pages via Tavily extract API."""

import json
import os
import sys
import time
from typing import Any

import requests


def fatal(msg: str, *args: Any) -> None:
    """Print error to stderr and exit."""
    print(msg % args, file=sys.stderr)
    sys.exit(1)


def main() -> None:
    if len(sys.argv) < 2:
        fatal("usage: fetch.py <url>")

    raw_url = sys.argv[1]

    api_key = os.environ.get("TAVILY_API_KEY")
    if not api_key:
        fatal("TAVILY_API_KEY not set")

    last_err: Exception | None = None

    for attempt in range(5):
        extract_depth = "advanced" if attempt >= 3 else "basic"

        if attempt > 0:
            time.sleep(3)

        req_body = {
            "urls": [raw_url],
            "chunks_per_source": 5,
            "extract_depth": extract_depth,
            "timeout": 60,
            "include_images": True,
            "include_usage": True,
        }

        try:
            resp = requests.post(
                "https://api.tavily.com/extract",
                json=req_body,
                headers={"Authorization": f"Bearer {api_key}"},
                timeout=90,
            )

            if resp.status_code != 200:
                last_err = Exception(f"tavily returned status {resp.status_code}")
                continue

            data = resp.json()

            if data.get("failed_results"):
                last_err = Exception(f"extract failed: {data['failed_results'][0].get('error')}")
                continue

            results = data.get("results", [])
            if not results:
                last_err = Exception("no content extracted")
                continue

            result = results[0]
            output = {
                "type": "webpage",
                "title": result.get("title", ""),
                "author": "",
                "text": result.get("raw_content", ""),
                "images": result.get("images", []),
                "url": raw_url,
            }
            print(json.dumps(output))
            return

        except Exception as e:
            last_err = e
            continue

    fatal("tavily extraction failed after 5 attempts: %s", last_err)


if __name__ == "__main__":
    main()
