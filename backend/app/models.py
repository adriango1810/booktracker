from pydantic import BaseModel, Field


class IdentifyBookRequest(BaseModel):
    isbn: str | None = None
    ocr_text: str | None = None
    locale: str = "es-ES"
    device: str = "android"


class BookOut(BaseModel):
    title: str
    author: str
    isbn13: str | None = None


class BookCandidateOut(BaseModel):
    title: str
    author: str
    isbn13: str | None = None


class IdentifyBookResponse(BaseModel):
    status: str
    confidence: float
    book: BookOut | None = None
    candidates: list[BookCandidateOut] = Field(default_factory=list)
    reason: str = ""


class ResolveGoodreadsRequest(BaseModel):
    title: str
    author: str
    isbn13: str | None = None


class GoodreadsCandidateOut(BaseModel):
    title: str
    author: str
    isbn13: str | None = None
    goodreads_url: str
    confidence: float


class ResolveGoodreadsResponse(BaseModel):
    status: str
    confidence: float
    goodreads_url: str | None = None
    candidates: list[GoodreadsCandidateOut] = Field(default_factory=list)
