#!/usr/bin/env python3
"""Fetch content from X/Twitter URLs including posts, threads, and articles."""

import json
import os
import re
import sys
from typing import Any

import requests

X_URL_PATTERN = re.compile(r"https?://(?:www\.)?(?:x\.com|twitter\.com)/(\w+)/status/(\d+)")


def fatal(msg: str, *args: Any) -> None:
    """Print error to stderr and exit."""
    print(msg % args, file=sys.stderr)
    sys.exit(1)


def fetch_fx_twitter(username: str, tweet_id: str) -> dict:
    """Fetch tweet data from fxtwitter API."""
    url = f"https://api.fxtwitter.com/{username}/status/{tweet_id}"
    resp = requests.get(url, timeout=30)
    
    if resp.status_code != 200:
        raise Exception(f"fxtwitter returned status {resp.status_code}")
    
    data = resp.json()
    return data["tweet"]


def fetch_replies(tweet_id: str, api_key: str) -> list[dict]:
    """Fetch all replies to a tweet using twitterapi.io."""
    all_replies = []
    cursor = ""
    
    while True:
        params = {"tweetId": tweet_id, "queryType": "Relevance"}
        if cursor:
            params["cursor"] = cursor
        
        resp = requests.get(
            "https://api.twitterapi.io/twitter/tweet/replies/v2",
            params=params,
            headers={"X-API-Key": api_key},
            timeout=30,
        )
        
        data = resp.json()
        all_replies.extend(data.get("tweets", []))
        
        if not data.get("has_next_page"):
            break
        cursor = data.get("next_cursor", "")
    
    return all_replies


def extract_thread_from_replies(author: str, original_id: str, replies: list[dict]) -> list[dict]:
    """Extract a thread chain from replies by the same author."""
    chain = []
    current_id = original_id
    
    while True:
        found = False
        for r in replies:
            if r.get("author", {}).get("userName") == author and r.get("inReplyToId") == current_id:
                chain.append(r)
                current_id = r["id"]
                found = True
                break
        if not found:
            break
    
    return chain


def main() -> None:
    if len(sys.argv) < 2:
        fatal("usage: fetch.py <x-url>")
    
    raw_url = sys.argv[1]
    
    api_key = os.environ.get("TWITTERAPI_IO_KEY")
    if not api_key:
        fatal("TWITTERAPI_IO_KEY not set")
    
    match = X_URL_PATTERN.search(raw_url)
    if not match:
        fatal("invalid X URL: %s", raw_url)
    
    username, tweet_id = match.groups()
    
    try:
        tweet = fetch_fx_twitter(username, tweet_id)
    except Exception as e:
        fatal("fxtwitter: %v", e)
    
    author = tweet.get("author", {}).get("screen_name", "")
    
    images = []
    media = tweet.get("media")
    if media:
        for photo in media.get("photos", []):
            images.append(photo.get("url", ""))
    
    # Article?
    article = tweet.get("article")
    if article:
        parts = [f"Author: @{author}", "", article.get("title", ""), ""]
        for block in article.get("content", {}).get("blocks", []):
            text = block.get("text", "").strip()
            if text:
                parts.append(text)
                parts.append("")
        
        output = {
            "type": "x_article",
            "title": article.get("title", ""),
            "author": author,
            "text": "\n".join(parts).strip(),
            "images": images,
            "url": raw_url,
        }
        print(json.dumps(output))
        return
    
    # Fetch replies to detect thread
    try:
        replies = fetch_replies(tweet_id, api_key)
    except Exception:
        # Fall back to single post
        output = {
            "type": "x_post",
            "author": author,
            "text": f"Author: @{author}\n\n{tweet.get('text', '')}",
            "images": images,
            "url": raw_url,
        }
        print(json.dumps(output))
        return
    
    chain = extract_thread_from_replies(author, tweet_id, replies)
    if chain:
        parts = [f"Author: @{author}", "", f"1\n{tweet.get('text', '')}"]
        for i, t in enumerate(chain, start=2):
            parts.append(f"\n{i}\n{t.get('text', '')}")
        
        output = {
            "type": "x_thread",
            "author": author,
            "text": "\n".join(parts),
            "images": images,
            "url": raw_url,
        }
        print(json.dumps(output))
        return
    
    # Single post
    output = {
        "type": "x_post",
        "author": author,
        "text": f"Author: @{author}\n\n{tweet.get('text', '')}",
        "images": images,
        "url": raw_url,
    }
    print(json.dumps(output))


if __name__ == "__main__":
    main()
