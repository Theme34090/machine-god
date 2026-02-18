#!/usr/bin/env python3
"""Search the web using Tavily API.

Supports full Tavily search capabilities including filtering by domain, date,
topic, and various output options. See SKILL.md for details.
"""

import argparse
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


def search(api_key: str, query: str, options: dict) -> dict:
    """Execute a single Tavily search and return results."""
    req_body = {"query": query}

    # Search depth and topic
    if options.get("search_depth"):
        req_body["search_depth"] = options["search_depth"]
    if options.get("topic"):
        req_body["topic"] = options["topic"]

    # Result limits
    if options.get("max_results") is not None:
        req_body["max_results"] = options["max_results"]
    if options.get("chunks_per_source") is not None:
        req_body["chunks_per_source"] = options["chunks_per_source"]

    # Date filtering
    if options.get("time_range"):
        req_body["time_range"] = options["time_range"]
    if options.get("start_date"):
        req_body["start_date"] = options["start_date"]
    if options.get("end_date"):
        req_body["end_date"] = options["end_date"]

    # Domain filtering
    if options.get("include_domains"):
        req_body["include_domains"] = options["include_domains"]
    if options.get("exclude_domains"):
        req_body["exclude_domains"] = options["exclude_domains"]

    # Country boost
    if options.get("country"):
        req_body["country"] = options["country"]

    # Output options
    if options.get("include_answer") is not None:
        req_body["include_answer"] = options["include_answer"]
    if options.get("include_raw_content") is not None:
        req_body["include_raw_content"] = options["include_raw_content"]
    if options.get("include_images") is not None:
        req_body["include_images"] = options["include_images"]
    if options.get("include_image_descriptions") is not None:
        req_body["include_image_descriptions"] = options["include_image_descriptions"]
    if options.get("include_favicon") is not None:
        req_body["include_favicon"] = options["include_favicon"]

    # Other options
    if options.get("auto_parameters") is not None:
        req_body["auto_parameters"] = options["auto_parameters"]
    if options.get("include_usage") is not None:
        req_body["include_usage"] = options["include_usage"]

    resp = requests.post(
        "https://api.tavily.com/search",
        json=req_body,
        headers={"Authorization": f"Bearer {api_key}"},
        timeout=60,
    )

    if resp.status_code != 200:
        raise Exception(f"tavily returned status {resp.status_code} for query {query!r}")

    data = resp.json()

    # Build result objects with all available fields
    results = []
    for r in data.get("results", []):
        result = {
            "title": r.get("title", ""),
            "url": r.get("url", ""),
            "content": r.get("content", ""),
            "score": r.get("score"),
        }
        if r.get("raw_content"):
            result["raw_content"] = r["raw_content"]
        if r.get("published_date"):
            result["published_date"] = r["published_date"]
        if r.get("favicon"):
            result["favicon"] = r["favicon"]
        results.append(result)

    output = {
        "query": query,
        "results": results,
    }

    # Optional top-level fields
    if data.get("answer"):
        output["answer"] = data["answer"]
    if data.get("images"):
        output["images"] = data["images"]
    if data.get("response_time"):
        output["response_time"] = data["response_time"]
    if data.get("request_id"):
        output["request_id"] = data["request_id"]

    return output


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Search the web using Tavily API",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  %(prog)s "latest AI trends"
  %(prog)s "AAPL earnings" --topic finance --time-range week
  %(prog)s "machine learning" --include-domains arxiv.org,github.com --max-results 10
  %(prog)s "quantum computing" --depth advanced --include-answer --include-raw-content
""",
    )

    parser.add_argument(
        "queries",
        nargs="+",
        help="One or more search queries (keep each under 400 chars)",
    )

    # Search configuration
    parser.add_argument(
        "--depth",
        choices=["ultra-fast", "fast", "basic", "advanced"],
        help="Search depth: ultra-fast (lowest latency), fast (chunks, low latency), basic (balanced), advanced (highest relevance, default)",
    )
    parser.add_argument(
        "--topic",
        choices=["general", "news", "finance"],
        help="Topic category. News includes published_date. Finance for market data.",
    )
    parser.add_argument(
        "--max-results",
        type=int,
        help="Maximum results per query (0-20, default: 5)",
    )
    parser.add_argument(
        "--chunks-per-source",
        type=int,
        help="Chunks per source for advanced/fast depth (default: 3)",
    )

    # Date filtering
    parser.add_argument(
        "--time-range",
        choices=["day", "week", "month", "year"],
        help="Restrict to relative time range",
    )
    parser.add_argument(
        "--start-date",
        help="Results after date (YYYY-MM-DD)",
    )
    parser.add_argument(
        "--end-date",
        help="Results before date (YYYY-MM-DD)",
    )

    # Domain filtering
    parser.add_argument(
        "--include-domains",
        help="Comma-separated domains to include (supports wildcards like *.com)",
    )
    parser.add_argument(
        "--exclude-domains",
        help="Comma-separated domains to exclude",
    )

    # Geographic
    parser.add_argument(
        "--country",
        help="Boost results from country (e.g., 'united states', 'japan')",
    )

    # Output options
    parser.add_argument(
        "--include-answer",
        nargs="?",
        const="basic",
        choices=["basic", "advanced"],
        help="Include AI-generated answer. Use 'advanced' for better answers.",
    )
    parser.add_argument(
        "--include-raw-content",
        nargs="?",
        const="markdown",
        choices=["markdown", "text"],
        help="Include full page content in specified format",
    )
    parser.add_argument(
        "--include-images",
        action="store_true",
        help="Include image results",
    )
    parser.add_argument(
        "--include-image-descriptions",
        action="store_true",
        help="Include AI descriptions for images (requires --include-images)",
    )
    parser.add_argument(
        "--include-favicon",
        action="store_true",
        help="Include favicon URL per result",
    )

    # Other options
    parser.add_argument(
        "--auto-parameters",
        action="store_true",
        help="Let Tavily auto-configure based on query intent (may use advanced depth)",
    )
    parser.add_argument(
        "--include-usage",
        action="store_true",
        help="Include credit usage info in response",
    )

    return parser.parse_args()


def main() -> None:
    args = parse_args()

    api_key = os.environ.get("TAVILY_API_KEY")
    if not api_key:
        fatal("TAVILY_API_KEY not set")

    # Build options dict from args
    options: dict[str, Any] = {}

    if args.depth:
        options["search_depth"] = args.depth
    if args.topic:
        options["topic"] = args.topic
    if args.max_results is not None:
        options["max_results"] = args.max_results
    if args.chunks_per_source is not None:
        options["chunks_per_source"] = args.chunks_per_source
    if args.time_range:
        options["time_range"] = args.time_range
    if args.start_date:
        options["start_date"] = args.start_date
    if args.end_date:
        options["end_date"] = args.end_date
    if args.include_domains:
        options["include_domains"] = args.include_domains.split(",")
    if args.exclude_domains:
        options["exclude_domains"] = args.exclude_domains.split(",")
    if args.country:
        options["country"] = args.country

    # Output options
    if args.include_answer is not None:
        # --include-answer or --include-answer=advanced
        if args.include_answer == "basic":
            options["include_answer"] = True
        elif args.include_answer == "advanced":
            options["include_answer"] = "advanced"
        else:
            options["include_answer"] = True

    if args.include_raw_content is not None:
        options["include_raw_content"] = args.include_raw_content

    if args.include_images:
        options["include_images"] = True
    if args.include_image_descriptions:
        options["include_image_descriptions"] = True
    if args.include_favicon:
        options["include_favicon"] = True
    if args.auto_parameters:
        options["auto_parameters"] = True
    if args.include_usage:
        options["include_usage"] = True

    # Execute searches concurrently
    queries = args.queries
    results = []
    errors = []

    with ThreadPoolExecutor(max_workers=min(len(queries), 10)) as executor:
        future_to_query = {
            executor.submit(search, api_key, q, options): q for q in queries
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

    # Output as array for single query (consistent), or array for multiple
    print(json.dumps(results))


if __name__ == "__main__":
    main()
