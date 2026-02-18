#!/usr/bin/env python3
"""Search the web using Tavily API."""

import json
import os
import sys
from concurrent.futures import ThreadPoolExecutor, as_completed
from typing import Any

import requests


def fatal(msg: str, *args: Any) -> None:
    """Print error to stderr and exit."""
    print(msg % args, file=sys.stderr)
    sys.exit(1)


def search(api_key: str, query: str) -> dict:
    """Execute a single Tavily search and return results."""
    req_body = {
        "query": query,
        "topic": "general",
        "search_depth": "advanced",
        "max_results": 5,
        "include_answer": True,
        "include_raw_content": "markdown",
    }

    resp = requests.post(
        "https://api.tavily.com/search",
        json=req_body,
        headers={"Authorization": f"Bearer {api_key}"},
        timeout=30,
    )

    if resp.status_code != 200:
        raise Exception(f"tavily returned status {resp.status_code} for query {query!r}")

    data = resp.json()

    results = []
    for r in data.get("results", []):
        results.append({
            "title": r.get("title", ""),
            "url": r.get("url", ""),
            "content": r.get("content", ""),
            "raw_content": r.get("raw_content", ""),
        })

    return {
        "query": query,
        "answer": data.get("answer", ""),
        "results": results,
    }


def main() -> None:
    if len(sys.argv) < 2:
        fatal("usage: search.py <query1> [query2] [query3] ...")

    api_key = os.environ.get("TAVILY_API_KEY")
    if not api_key:
        fatal("TAVILY_API_KEY not set")

    queries = sys.argv[1:]
    results = []
    errors = []

    with ThreadPoolExecutor(max_workers=len(queries)) as executor:
        future_to_query = {
            executor.submit(search, api_key, q): q for q in queries
        }

        for future in as_completed(future_to_query):
            query = future_to_query[future]
            try:
                result = future.result()
                results.append(result)
            except Exception as e:
                errors.append((query, str(e)))
                print(f"warning: query {query!r} failed: {e}", file=sys.stderr)

    if not results:
        fatal("all queries failed")

    # Sort results by original query order
    query_order = {q: i for i, q in enumerate(queries)}
    results.sort(key=lambda r: query_order.get(r["query"], 999))

    print(json.dumps(results))


if __name__ == "__main__":
    main()
