import os
import re
from typing import Any

import httpx
from rapidfuzz import fuzz

OPEN_LIBRARY_SEARCH = "https://openlibrary.org/search.json"
OPEN_LIBRARY_ISBN = "https://openlibrary.org/isbn/{isbn}.json"
REQUEST_TIMEOUT = float(os.getenv("REQUEST_TIMEOUT_SECONDS", "8"))


def _author_name(authors: list[Any] | None) -> str:
    if not authors:
        return "Autor desconocido"
    first = authors[0]
    if isinstance(first, dict):
        return first.get("name") or first.get("key", "").split("/")[-1]
    return str(first)


def _normalize_query(text: str) -> str:
    text = text.replace("\n", " ").replace("\r", " ")
    text = re.sub(r"\s+", " ", text).strip()
    # Prefer first ~80 chars (title-like); avoid dumping entire OCR blob.
    if len(text) > 80:
        text = text[:80].rsplit(" ", 1)[0]
    return text


async def identify_by_isbn(isbn: str) -> tuple[dict[str, Any] | None, float, str]:
    async with httpx.AsyncClient(timeout=REQUEST_TIMEOUT) as client:
        response = await client.get(OPEN_LIBRARY_ISBN.format(isbn=isbn))
        if response.status_code != 200:
            # Fallback search by ISBN field
            search = await client.get(
                OPEN_LIBRARY_SEARCH,
                params={"isbn": isbn, "limit": 1},
            )
            if search.status_code != 200:
                return None, 0.0, "isbn_not_found"
            docs = search.json().get("docs", [])
            if not docs:
                return None, 0.0, "isbn_not_found"
            doc = docs[0]
            return {
                "title": doc.get("title", "Libro desconocido"),
                "author": _author_name(doc.get("author_name")),
                "isbn13": isbn,
            }, 0.92, "isbn_search_match"

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


async def identify_by_ocr(
    ocr_text: str,
) -> tuple[dict[str, Any] | None, float, list[dict[str, Any]], str]:
    query = _normalize_query(ocr_text)
    if len(query) < 5:
        return None, 0.0, [], "query_too_short"

    async with httpx.AsyncClient(timeout=REQUEST_TIMEOUT) as client:
        response = await client.get(
            OPEN_LIBRARY_SEARCH,
            params={"q": query, "limit": 8},
        )
        if response.status_code != 200:
            return None, 0.0, [], "search_failed"

        docs = response.json().get("docs", [])
        if not docs:
            return None, 0.0, [], "no_match"

        scored: list[tuple[float, dict[str, Any]]] = []
        for doc in docs:
            title = (doc.get("title") or "").strip()
            if not title:
                continue
            # Prefer matching against title alone (shorter = better signal).
            author = _author_name(doc.get("author_name"))
            title_score = fuzz.token_set_ratio(query.lower(), title.lower()) / 100.0
            combined_score = (
                fuzz.token_set_ratio(query.lower(), f"{title} {author}".lower()) / 100.0
            )
            # Bias toward title-only match; slight boost if title is short.
            score = max(title_score, combined_score * 0.95)
            if 8 <= len(title) <= 60:
                score = min(1.0, score + 0.03)

            isbn13 = None
            isbn_list = doc.get("isbn") or []
            if isbn_list:
                isbn13 = next((i for i in isbn_list if len(str(i)) == 13), str(isbn_list[0]))

            scored.append((
                score,
                {
                    "title": title,
                    "author": author,
                    "isbn13": isbn13,
                },
            ))

        if not scored:
            return None, 0.0, [], "no_match"

        scored.sort(key=lambda item: item[0], reverse=True)
        best_score, best = scored[0]

        # Always expose up to 3 candidates when ambiguous.
        candidate_pool = [item[1] for item in scored[:3] if item[0] >= 0.55]

        if best_score >= 0.85:
            return best, best_score, [], "ocr_strong_match"

        if best_score >= 0.60:
            # Ambiguous: candidates only (best first); client shows picker.
            return None, best_score, candidate_pool[:3], "ocr_ambiguous"

        return None, best_score, [], "ocr_weak_match"
