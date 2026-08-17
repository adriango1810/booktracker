import os
from pathlib import Path

from dotenv import load_dotenv
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware

from app.models import (
    BookCandidateOut,
    BookOut,
    GoodreadsCandidateOut,
    IdentifyBookRequest,
    IdentifyBookResponse,
    ResolveGoodreadsRequest,
    ResolveGoodreadsResponse,
)
from app.services.goodreads_resolver import resolve_goodreads_url
from app.services.open_library import identify_by_isbn, identify_by_ocr

load_dotenv(Path(__file__).resolve().parents[1] / ".env")

app = FastAPI(title="Book Scanner API", version="1.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.get("/health")
async def health() -> dict[str, str]:
    return {"status": "ok"}


@app.post("/identify-book", response_model=IdentifyBookResponse)
async def identify_book(body: IdentifyBookRequest) -> IdentifyBookResponse:
    if body.isbn:
        book, confidence, reason = await identify_by_isbn(body.isbn)
        if book is None:
            return IdentifyBookResponse(
                status="error",
                confidence=0.0,
                reason=reason,
            )
        return IdentifyBookResponse(
            status="ok",
            confidence=confidence,
            book=BookOut(**book),
            reason=reason,
        )

    if body.ocr_text:
        book, confidence, candidates, reason = await identify_by_ocr(body.ocr_text)
        candidate_models = [BookCandidateOut(**c) for c in candidates[:3]]

        if candidate_models and confidence < 0.85:
            return IdentifyBookResponse(
                status="ok",
                confidence=confidence,
                candidates=candidate_models,
                reason=reason,
            )

        if book is None:
            return IdentifyBookResponse(
                status="error",
                confidence=confidence,
                reason=reason,
            )

        return IdentifyBookResponse(
            status="ok",
            confidence=confidence,
            book=BookOut(**book),
            candidates=candidate_models,
            reason=reason,
        )

    raise HTTPException(status_code=422, detail="isbn or ocr_text required")


@app.post("/resolve-goodreads", response_model=ResolveGoodreadsResponse)
async def resolve_goodreads(body: ResolveGoodreadsRequest) -> ResolveGoodreadsResponse:
    url, confidence, candidates = await resolve_goodreads_url(
        body.title,
        body.author,
        body.isbn13,
    )

    if url and confidence >= 0.85:
        return ResolveGoodreadsResponse(
            status="ok",
            confidence=confidence,
            goodreads_url=url,
        )

    if candidates:
        return ResolveGoodreadsResponse(
            status="ok",
            confidence=confidence,
            candidates=[GoodreadsCandidateOut(**c) for c in candidates[:3]],
        )

    if url and confidence >= 0.60:
        return ResolveGoodreadsResponse(
            status="ok",
            confidence=confidence,
            goodreads_url=url,
        )

    return ResolveGoodreadsResponse(
        status="error",
        confidence=confidence,
    )
