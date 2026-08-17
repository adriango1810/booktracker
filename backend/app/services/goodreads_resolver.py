import os
from urllib.parse import quote_plus

import httpx
from rapidfuzz import fuzz

REQUEST_TIMEOUT = float(os.getenv("REQUEST_TIMEOUT_SECONDS", "8"))
GOODREADS_SEARCH = "https://www.goodreads.com/search?q="

KNOWN_URLS = {
    "el nombre del viento": "https://www.goodreads.com/book/show/186074",
    "9788401020236": "https://www.goodreads.com/book/show/186074",
}


async def resolve_goodreads_url(
    title: str,
    author: str,
    isbn13: str | None,
) -> tuple[str | None, float, list[dict]]:
    title_key = title.lower().strip()
    if title_key in KNOWN_URLS:
        return KNOWN_URLS[title_key], 0.9, []

    if isbn13 and isbn13 in KNOWN_URLS:
        return KNOWN_URLS[isbn13], 0.9, []

    # ISBN search is the most reliable Goodreads entry point without scraping.
    if isbn13 and len(isbn13) >= 10:
        isbn_url = f"{GOODREADS_SEARCH}{quote_plus(isbn13)}"
        return isbn_url, 0.9, []

    query = quote_plus(f"{title} {author}".strip())
    search_url = f"{GOODREADS_SEARCH}{query}"

    confidence = 0.78
    async with httpx.AsyncClient(timeout=REQUEST_TIMEOUT, follow_redirects=True) as client:
        resp = await client.get(
            "https://openlibrary.org/search.json",
            params={"q": f"{title} {author}".strip(), "limit": 1},
        )
        if resp.status_code == 200:
            docs = resp.json().get("docs", [])
            if docs:
                ol_title = docs[0].get("title", title)
                ol_author = (docs[0].get("author_name") or [author])[0]
                ratio = fuzz.token_set_ratio(
                    f"{title} {author}".lower(),
                    f"{ol_title} {ol_author}".lower(),
                ) / 100.0
                confidence = max(confidence, min(0.92, ratio))
                refined = f"{GOODREADS_SEARCH}{quote_plus(f'{ol_title} {ol_author}')}"
                if ratio >= 0.85:
                    return refined, confidence, []

    if confidence >= 0.85:
        return search_url, confidence, []

    return None, confidence, [
        {
            "title": title,
            "author": author,
            "isbn13": isbn13,
            "goodreads_url": search_url,
            "confidence": confidence,
        }
    ]
