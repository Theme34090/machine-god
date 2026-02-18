---
name: tavily-web-fetch
description: Fetch raw content from web pages via Tavily
---

# tavily-web-fetch

Fetches raw web page content using the Tavily extract API. Returns unclean content — pipe through content-cleaning for article extraction.

## Usage

```bash
cd skills/tavily-web-fetch/scripts && uv run --with requests fetch.py <url>
```

## Input

- **Arg 1:** Any HTTP/HTTPS URL
- **Env:** `TAVILY_API_KEY` must be set

## Output

JSON to stdout:

```json
{"type": "webpage", "title": "...", "author": "", "text": "...", "images": ["..."], "url": "..."}
```

- `text`: Raw page content (not cleaned — includes nav, footers, etc.)
- `images`: Image URLs found on the page
- Retries up to 5 times, escalating to advanced extraction after 3 attempts
- Non-zero exit on error, message on stderr
