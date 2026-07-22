# Book Scanner Backend (FastAPI)

Endpoints compartidos con el cliente Flutter (`mobile/`).

## Arranque (Windows)

```powershell
cd backend
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
copy .env.example .env
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

Docs: http://127.0.0.1:8000/docs

Desde el teléfono en la misma WiFi: `http://<IP_PC>:8000`.

## Endpoints

- `POST /identify-book` — ISBN o `ocr_text` vía Open Library
- `POST /resolve-goodreads` — heurística de búsqueda Goodreads + URLs conocidas de demo
- `GET /health`

## Fuentes

- Identify: Open Library (sin API key)
- Resolve: heurística `search_heuristic` + mapa de títulos/ISBN de prueba
