import os
from typing import Any

import httpx
from rapidfuzz import fuzz

OPEN_LIBRARY_SEARCH = "https://openlibrary.org/search.json"
OPEN_LIBRARY_ISBN = "https://openlibrary.org/isbn/{isbn}.json"
REQUEST_TIMEOUT = float(os.getenv("REQUEST_TIMEOUT_SECONDS", "8"))


def _author_name(authors: list[dict[str, Any]] | None) -> str:
    if not authors:
        return "Autor desconocido"
    first = authors[0]
    if isinstance(first, dict):
        return first.get("name") or first.get("key", "").split("/")[-1]
    return str(first)


async def identify_by_isbn(isbn: str) -> tuple[dict[str, Any] | None, float, str]:
    async with httpx.AsyncClient(timeout=REQUEST_TIMEOUT) as client:
        response = await client.get(OPEN_LIBRARY_ISBN.format(isbn=isbn))
        if response.status_code != 200:
            return None, 0.0, "isbn_not_found"

        data = response.json()
        title = data.get("title", "Libro desconocido")
        authors = data.get("authors", [])
        author = "Autor desconocido"
        if authors:
            author_key = authors[0].get("key", "")
            if author_key:
                author_resp = await client.get(f"https://openlibrary.org{author_key}.json")
                if author_resp.status_code == 200:
                    author = author_resp.json().get("name", author)

        return {
            "title": title,
            "author": author,
            "isbn13": isbn,
        }, 0.95, "isbn_exact_match"


async def identify_by_ocr(ocr_text: str) -> tuple[dict[str, Any] | None, float, list[dict[str, Any]], str]:
    query = ocr_text.strip()
    async with httpx.AsyncClient(timeout=REQUEST_TIMEOUT) as client:
        response = await client.get(OPEN_LIBRARY_SEARCH, params={"q": query, "limit": 5})
        if response.status_code != 200:
            return None, 0.0, [], "search_failed"

        docs = response.json().get("docs", [])
        if not docs:
            return None, 0.0, [], "no_match"

        scored: list[tuple[float, dict[str, Any]]] = []
        for doc in docs:
            title = doc.get("title", "")
            author = _author_name(doc.get("author_name"))
            combined = f"{title} {author}".strip()
            score = fuzz.token_set_ratio(query.lower(), combined.lower()) / 100.0
            isbn13 = None
            isbn_list = doc.get("isbn") or []
            if isbn_list:
                isbn13 = next((i for i in isbn_list if len(i) == 13), isbn_list[0])
            scored.append((score, {
                "title": title,
                "author": author,
                "isbn13": isbn13,
            }))

        scored.sort(key=lambda item: item[0], reverse=True)
        best_score, best = scored[0]

        if best_score >= 0.85:
            return best, best_score, [], "ocr_strong_match"

        if best_score >= 0.60:
            candidates = [item[1] for item in scored[1:3] if item[0] >= 0.55]
            return best, best_score, candidates, "ocr_ambiguous"

        return None, best_score, [], "ocr_weak_match"
