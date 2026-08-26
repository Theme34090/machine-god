#!/usr/bin/env python3
"""Fetch raw content from web pages via Tavily extract API."""

import argparse
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


def extract(
    api_key: str,
    urls: list[str],
    query: str | None,
    chunks_per_source: int,
    extract_depth: str,
    format: str,
    include_images: bool,
    include_favicon: bool,
    timeout: float,
) -> dict:
    """Call Tavily extract API and return response data."""
    req_body: dict[str, Any] = {
        "urls": urls,
        "extract_depth": extract_depth,
        "timeout": timeout,
        "include_images": include_images,
        "include_favicon": include_favicon,
    }

    if query:
        req_body["query"] = query
        req_body["chunks_per_source"] = chunks_per_source

    resp = requests.post(
        "https://api.tavily.com/extract",
        json=req_body,
        headers={"Authorization": f"Bearer {api_key}"},
        timeout=timeout + 30,
    )

    if resp.status_code != 200:
        raise Exception(f"tavily returned status {resp.status_code}")

    return resp.json()


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Fetch raw content from web pages via Tavily extract API"
    )
    parser.add_argument(
        "urls",
        nargs="+",
        help="One or more URLs to extract (max 20)",
    )
    parser.add_argument(
        "--query", "-q",
        help="Query for targeted extraction; reranks chunks by relevance",
    )
    parser.add_argument(
        "--chunks", "-c",
        type=int,
        default=3,
        help="Chunks per source (1-5). Only used with --query (default: 3)",
    )
    parser.add_argument(
        "--depth", "-d",
        choices=["basic", "advanced"],
        default="basic",
        help="Extract depth: basic (faster) or advanced (for JS/complex pages)",
    )
    parser.add_argument(
        "--format", "-f",
        choices=["markdown", "text"],
        default="markdown",
        help="Output format (default: markdown)",
    )
    parser.add_argument(
        "--no-images",
        action="store_true",
        help="Don't include image URLs",
    )
    parser.add_argument(
        "--favicon",
        action="store_true",
        help="Include favicon URL",
    )
    parser.add_argument(
        "--timeout", "-t",
        type=float,
        default=60.0,
        help="Max wait time in seconds (default: 60)",
    )
    parser.add_argument(
        "--max-retries",
        type=int,
        default=5,
        help="Max retry attempts (default: 5)",
    )
    args = parser.parse_args()

    if len(args.urls) > 20:
        fatal("maximum 20 URLs allowed")

    if args.chunks < 1 or args.chunks > 5:
        fatal("chunks must be between 1 and 5")

    api_key = os.environ.get("TAVILY_API_KEY")
    if not api_key:
        fatal("TAVILY_API_KEY not set")

    last_err: Exception | None = None

    for attempt in range(args.max_retries):
        # Escalate to advanced after half the retries failed
        depth = args.depth
        if attempt >= args.max_retries // 2 and args.depth == "basic":
            depth = "advanced"

        if attempt > 0:
            time.sleep(3)

        try:
            data = extract(
                api_key=api_key,
                urls=args.urls,
                query=args.query,
                chunks_per_source=args.chunks,
                extract_depth=depth,
                format=args.format,
                include_images=not args.no_images,
                include_favicon=args.favicon,
                timeout=args.timeout,
            )

            if data.get("failed_results"):
                # If all URLs failed, treat as error and retry
                if len(data.get("results", [])) == 0:
                    last_err = Exception(
                        f"extract failed: {data['failed_results'][0].get('error')}"
                    )
                    continue

            results = data.get("results", [])
            if not results:
                last_err = Exception("no content extracted")
                continue

            # Output one JSON object per result (JSON lines format)
            for result in results:
                output = {
                    "type": "webpage",
                    "title": result.get("title", ""),
                    "author": "",
                    "text": result.get("raw_content", ""),
                    "images": result.get("images", []),
                    "url": result.get("url", ""),
                }
                if args.favicon and result.get("favicon"):
                    output["favicon"] = result["favicon"]
                print(json.dumps(output))

            # Report failed URLs to stderr
            for failed in data.get("failed_results", []):
                print(
                    f"warning: failed to extract {failed.get('url')}: {failed.get('error')}",
                    file=sys.stderr,
                )

            return

        except Exception as e:
            last_err = e
            continue

    fatal("tavily extraction failed after %d attempts: %s", args.max_retries, last_err)


if __name__ == "__main__":
    main()
