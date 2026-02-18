---
name: fetch-twitter
description: Fetch content from X/Twitter posts, threads, and articles
---

# fetch-twitter

Fetches and extracts content from X (Twitter) URLs including single posts, threads, and long-form articles.

## Usage

Run the script:

```bash
cd skills/fetch-twitter/scripts && uv run fetch.py <x-url>
```

## Input

- **Arg 1:** An X/Twitter URL matching `https://(x.com|twitter.com)/<user>/status/<id>`
- **Env:** `TWITTERAPI_IO_KEY` must be set

## Output

JSON to stdout:

```json
{"type": "x_post|x_thread|x_article", "title": "...", "author": "...", "text": "...", "images": ["..."], "url": "..."}
```

- `type`: `x_post` (single tweet), `x_thread` (author self-reply chain), `x_article` (long-form article)
- `text`: Prefixed with `Author: @handle\n\n`, then content. Threads are numbered.
- `images`: Photo URLs from tweet media
- Non-zero exit on error, message on stderr
