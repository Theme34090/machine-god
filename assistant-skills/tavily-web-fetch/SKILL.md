---
name: tavily-web-fetch
description: Fetch raw content from web pages via Tavily
---

# tavily-web-fetch

Fetches raw web page content using the Tavily extract API. Returns unclean content — pipe through content-cleaning for article extraction.

## Usage

```bash
cd skills/tavily-web-fetch/scripts && uv run --with requests fetch.py <url...> [options]
```

## Authentication

Requires a Tavily API key. Get one at [tavily.com](https://tavily.com).

Set via environment:
```bash
export TAVILY_API_KEY=tvly-your-key-here
```

## Input

- **Args:** One or more HTTP/HTTPS URLs (**max 20**)

### Options

| Option | Default | Description |
|--------|---------|-------------|
| `--query`, `-q` | - | Target specific content within pages; reranks chunks by relevance (not for searching) |
| `--chunks`, `-c` | 3 | Chunks per source (1-5). Only used with `--query` |
| `--depth`, `-d` | basic | `basic` (faster) or `advanced` (for JS/complex pages) |
| `--format`, `-f` | markdown | Output format: `markdown` or `text` |
| `--no-images` | - | Don't include image URLs |
| `--favicon` | - | Include favicon URL in output |
| `--timeout`, `-t` | 60 | Max wait time in seconds |
| `--max-retries` | 5 | Max retry attempts |

## Output

JSON lines to stdout (one object per URL):

```json
{"type": "webpage", "title": "...", "author": "", "text": "...", "images": ["..."], "url": "..."}
```

**Fields:**

| Field | Description |
|-------|-------------|
| `type` | Always `"webpage"` |
| `title` | Page title |
| `author` | Author (if detected) |
| `text` | Raw content (or top-ranked chunks when using `--query`) |
| `images` | Image URLs found on the page |
| `url` | Source URL |
| `favicon` | Favicon URL (only with `--favicon`) |

## Examples

```bash
# Basic extraction
fetch.py https://example.com/article

# Multiple URLs
fetch.py https://site1.com https://site2.com

# Targeted extraction with query (returns relevant chunks only)
fetch.py https://docs.example.com/api -q "authentication tokens"

# Advanced depth for JS-heavy pages
fetch.py https://spa-example.com --depth advanced

# Include favicon, exclude images
fetch.py https://example.com --favicon --no-images
```

## Behavior

- Retries up to `--max-retries` times with 3s delay between attempts
- Escalates to `advanced` depth after half the retries if using `basic`
- Reports failed URLs to stderr (non-zero exit only if all URLs fail)

## Tips

- **Max 20 URLs per call** - split larger batches into multiple requests
- **Try `basic` first**, fall back to `advanced` if content is missing or incomplete
- **Use `--query` + `--chunks`** for long documents to get only relevant portions instead of full page content
- **Set higher `--timeout`** (up to 60s) for slow or complex pages
- **Check stderr** for warnings about failed URLs - partial success exits 0
