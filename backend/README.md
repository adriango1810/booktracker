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

En el cliente Flutter (`mobile/assets/.env`):

```env
USE_MOCK=false
API_BASE_URL=http://192.168.4.68:8000
```

Actualiza la IP si cambia (también en `network_security_config.xml`).

Docs: http://127.0.0.1:8000/docs

Desde el teléfono en la misma WiFi: `http://<IP_PC>:8000`.

## Endpoints

- `POST /identify-book` — ISBN o `ocr_text` vía Open Library (query normalizada; candidatos si ambigua)
- `POST /resolve-goodreads` — búsqueda Goodreads por ISBN preferente
- `GET /health`

## Fuentes

- Identify: Open Library (sin API key)
- Resolve: `search_heuristic` (ISBN → search URL con confidence alta)
