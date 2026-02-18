---
name: tavily-web-search
description: Search the web using Tavily API for real-time information
---

# tavily-web-search

Searches the web using Tavily's search API. Returns AI-generated answer plus top results with content. Supports filtering by domain, date, topic, and country.

## Usage

```bash
cd skills/tavily-web-search/scripts && uv run --with requests search.py <query1> [query2] ... [options]
```

## Input

- **Args:** One or more search queries (keep each under 400 chars)
- **Env:** `TAVILY_API_KEY` must be set

## Options

### Search Configuration

| Flag | Values | Description |
|------|--------|-------------|
| `--depth` | `ultra-fast`, `fast`, `basic`, `advanced` | Search depth. Advanced (default) has highest relevance. |
| `--topic` | `general`, `news`, `finance` | Topic category. News includes `published_date`. |
| `--max-results` | 0-20 | Maximum results per query (default: 5) |
| `--chunks-per-source` | int | Chunks per source for advanced/fast depth (default: 3) |

### Date Filtering

| Flag | Example | Description |
|------|---------|-------------|
| `--time-range` | `day`, `week`, `month`, `year` | Restrict to relative time range |
| `--start-date` | `2025-01-01` | Results after date |
| `--end-date` | `2025-02-01` | Results before date |

### Domain Filtering

| Flag | Example | Description |
|------|---------|-------------|
| `--include-domains` | `arxiv.org,github.com` | Only search these domains (supports `*.com` wildcards) |
| `--exclude-domains` | `reddit.com,quora.com` | Exclude these domains |

### Geographic

| Flag | Example | Description |
|------|---------|-------------|
| `--country` | `united states`, `japan` | Boost results from country |

### Output Options

| Flag | Description |
|------|-------------|
| `--include-answer` | Include AI-generated answer (use `=advanced` for better answers) |
| `--include-raw-content` | Include full page content (`=markdown` or `=text`) |
| `--include-images` | Include image results |
| `--include-image-descriptions` | AI descriptions for images |
| `--include-favicon` | Favicon URL per result |

### Other

| Flag | Description |
|------|-------------|
| `--auto-parameters` | Auto-configure based on query intent |
| `--include-usage` | Include credit usage info |

## Search Depth

Controls the latency vs. relevance tradeoff:

| Depth | Latency | Relevance | Content Type |
|-------|---------|-----------|--------------|
| `ultra-fast` | Lowest | Lower | NLP summary |
| `fast` | Low | Good | Chunks |
| `basic` | Medium | High | NLP summary |
| `advanced` | Higher | Highest | Chunks |

**When to use each:**
- `ultra-fast`: Real-time chat, autocomplete, latency-critical
- `fast`: Need chunks but latency matters
- `basic`: General-purpose, balanced
- `advanced`: Precision matters (default, suitable for most use cases)

## Tips

- **Keep queries under 400 characters** — think search query, not prompt
- **Break complex queries into sub-queries** — better results than one massive query
- **Use `--include-domains`** to focus on trusted sources
- **Use `--time-range`** for recent information
- **Filter by `score`** (0-1) to get highest relevance results
- **Use `--topic news`** when you need publication dates

## Output

JSON array to stdout:

```json
[
  {
    "query": "Apple stock price today",
    "answer": "Apple (AAPL) is currently trading at...",
    "results": [
      {
        "title": "Apple Inc. Stock Price",
        "url": "https://finance.yahoo.com/quote/AAPL",
        "content": "Current price...",
        "score": 0.92,
        "raw_content": "# Apple Inc...",
        "published_date": "2026-02-18",
        "favicon": "https://..."
      }
    ],
    "images": [{"url": "...", "description": "..."}],
    "response_time": 1.23,
    "request_id": "..."
  }
]
```

**Result fields:**

| Field | Always | Description |
|-------|--------|-------------|
| `title` | ✓ | Page title |
| `url` | ✓ | Source URL |
| `content` | ✓ | Extracted text snippet |
| `score` | ✓ | Semantic relevance (0-1) |
| `raw_content` | opt | Full page content (requires `--include-raw-content`) |
| `published_date` | opt | Publication date (requires `--topic news`) |
| `favicon` | opt | Favicon URL (requires `--include-favicon`) |

## Examples

Basic search:
```bash
search.py "latest AI trends"
```

Finance topic with date range:
```bash
search.py "AAPL earnings" --topic finance --time-range week
```

Domain filtering:
```bash
search.py "machine learning" --include-domains arxiv.org,github.com --max-results 10
```

Full content with answer:
```bash
search.py "quantum computing" --depth advanced --include-answer --include-raw-content
```

News search:
```bash
search.py "tech layoffs 2026" --topic news --time-range month
```

## Notes

- Queries run concurrently (up to 10 parallel)
- Failed queries emit warnings to stderr; successful results still output
- Non-zero exit only if all queries fail
