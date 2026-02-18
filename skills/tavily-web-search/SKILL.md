---
name: tavily-web-search
description: Search the web using Tavily API for real-time information
---

# tavily-web-search

Searches the web using Tavily's search API. Returns an AI-generated answer plus top results with raw markdown content. Supports multiple concurrent queries.

## Usage

```bash
cd skills/tavily-web-search/scripts && uv run --with requests search.py <query1> [query2] ...
```

## Input

- **Args:** One or more search queries
- **Env:** `TAVILY_API_KEY` must be set

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
        "raw_content": "# Apple Inc...\n\n## Stock Price..."
      }
    ]
  }
]
```

**Fields:**

| Field | Type | Description |
|-------|------|-------------|
| `query` | string | Original search query |
| `answer` | string | AI-generated answer (may be empty) |
| `results` | array | Top 5 search results |
| `results[].title` | string | Page title |
| `results[].url` | string | Source URL |
| `results[].content` | string | Brief content snippet |
| `results[].raw_content` | string | Full page content in markdown |

- Queries run concurrently
- Failed queries emit warnings to stderr; successful results still output
- Non-zero exit only if all queries fail
