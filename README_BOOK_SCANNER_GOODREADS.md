# README - Especificacion ejecutable para IA (PWA escaner de libros -> Goodreads)

## 1) Objetivo del proyecto

Construir una **PWA instalable** en iPhone y Android (opcion "Anadir a inicio") que permita:

1. Abrir camara en vivo (sin hacer foto manual).
2. Detectar ISBN (barcode EAN-13) en tiempo real.
3. Si no hay ISBN, usar OCR como fallback.
4. Resolver el libro y redirigir a su pagina de Goodreads.
5. Evitar falsos positivos y aperturas duplicadas.

---

## 2) Decisiones cerradas (no debatibles para la IA)

- **Arquitectura**: PWA (no app nativa).
- **Frontend**: `Vite + React + TypeScript`.
- **PWA**: `vite-plugin-pwa`.
- **Barcode/ISBN**: `@zxing/browser`.
- **OCR fallback**: `tesseract.js`.
- **Backend recomendado**: `FastAPI` (alternativa valida: Node/Express).
- **Cache recomendada**: Redis (opcional en MVP).
- **Plataformas objetivo**:
  - iPhone (Safari + anadir a inicio).
  - Android (Chrome + instalar app).

---

## 3) Requisitos funcionales obligatorios

1. No existe boton de "hacer foto".
2. Escaneo sobre preview de video en tiempo real.
3. Pipeline de deteccion:
   1) ISBN por barcode.
   2) OCR solo si ISBN no aparece.
4. Si confianza alta: abrir Goodreads automaticamente.
5. Si confianza media: mostrar 2-3 candidatos.
6. Si confianza baja: pedir reencuadre y seguir escaneando.
7. La app debe poder instalarse desde navegador como PWA.

---

## 4) Requisitos no funcionales

- Rendimiento:
  - iPhone: 1-3 FPS de analisis.
  - Android: 2-5 FPS de analisis.
- Debe funcionar en HTTPS.
- Debe evitar aperturas duplicadas con cooldown.
- UX clara con estados de deteccion.

---

## 5) Estructura de carpetas objetivo

```text
book-scanner-pwa/
  frontend/
    src/
      app/
      components/
      hooks/
      services/
      utils/
    public/
      icons/
      manifest.webmanifest
    index.html
    vite.config.ts
    package.json
  backend/
    app/
      main.py
      api/
      services/
      models/
      utils/
    requirements.txt
    .env.example
  README.md
```

---

## 6) Variables de entorno minimas

### Frontend (`frontend/.env`)

```env
VITE_API_BASE_URL=https://tu-backend.example.com
VITE_AUTO_OPEN=true
VITE_SCAN_FPS_IOS=2
VITE_SCAN_FPS_ANDROID=4
```

### Backend (`backend/.env`)

```env
APP_ENV=development
REDIS_URL=redis://localhost:6379/0
REQUEST_TIMEOUT_SECONDS=8
```

---

## 7) Contratos API cerrados

### `POST /identify-book`

Request:

```json
{
  "isbn": "978XXXXXXXXXX",
  "ocr_text": "optional raw text",
  "locale": "es-ES",
  "device": "ios|android|desktop"
}
```

Response:

```json
{
  "status": "ok",
  "confidence": 0.92,
  "book": {
    "title": "Example Book",
    "author": "Example Author",
    "isbn13": "978XXXXXXXXXX"
  },
  "candidates": [],
  "reason": "isbn_exact_match"
}
```

### `POST /resolve-goodreads`

Request:

```json
{
  "title": "Example Book",
  "author": "Example Author",
  "isbn13": "978XXXXXXXXXX"
}
```

Response:

```json
{
  "status": "ok",
  "confidence": 0.9,
  "goodreads_url": "https://www.goodreads.com/book/show/ID",
  "candidates": []
}
```

---

## 8) Logica de decision obligatoria

- `confidence >= 0.85`: abrir Goodreads directo.
- `0.60 <= confidence < 0.85`: mostrar top 3 candidatos.
- `confidence < 0.60`: no abrir, pedir reencuadre.

Controles obligatorios:

- Confirmar deteccion igual en 2-3 ciclos.
- Cooldown de 2-3 segundos tras abrir enlace.
- Evitar relanzar apertura si ISBN repetido.
- Un solo proceso de deteccion activo a la vez (`isProcessing`).

---

## 9) UX minima obligatoria

- Overlay central de enfoque.
- Estados visibles:
  - "Buscando ISBN..."
  - "Intentando OCR..."
  - "Libro detectado"
  - "No se pudo identificar"
- Toggle: "Abrir automaticamente al detectar".
- Boton manual: "Abrir resultado".
- Boton manual: "Reintentar escaneo".

---

## 10) Plan por pasos para ejecutar con IA (secuencial)

Regla global: **la IA no puede pasar al siguiente paso sin cumplir el DoD del paso actual**.

### Paso 1 - Bootstrap del frontend PWA

Objetivo:
- Crear proyecto React+TS con soporte PWA instalable.

Acciones:
1. Crear `frontend` con Vite React TS.
2. Instalar y configurar `vite-plugin-pwa`.
3. Crear `manifest.webmanifest` + iconos 192/512.
4. Registrar service worker.
5. Crear pagina inicial con estado "Inicializando camara...".

DoD (Definition of Done):
- `npm run dev` funciona.
- `npm run build` funciona sin errores.
- En Chrome DevTools aparece installable PWA.

### Paso 2 - Camara en vivo y ciclo de escaneo

Objetivo:
- Mostrar preview en vivo y ciclo de analisis con throttling.

Acciones:
1. Implementar `getUserMedia`.
2. Mostrar stream en `video`.
3. Crear loop de analisis con control FPS por dispositivo.
4. Definir ROI central y captura parcial para analisis.

DoD:
- Preview funciona en desktop y movil.
- No hay bloqueos de UI.
- FPS configurables por entorno.

### Paso 3 - Deteccion ISBN con ZXing

Objetivo:
- Detectar ISBN/EAN-13 desde el stream.

Acciones:
1. Integrar `@zxing/browser`.
2. Procesar frames del ROI.
3. Validar formato ISBN-10/13.
4. Agregar deduplicacion de lecturas consecutivas.

DoD:
- Detecta un ISBN real en pruebas.
- No dispara multiples eventos por el mismo ISBN.

### Paso 4 - Flujo Goodreads por ISBN

Objetivo:
- Al detectar ISBN, resolver URL y abrir Goodreads.

Acciones:
1. Llamar backend `/identify-book`.
2. Resolver URL en `/resolve-goodreads`.
3. Abrir URL en nueva pestaña.
4. Aplicar cooldown tras apertura.

DoD:
- Con ISBN valido abre Goodreads.
- Cooldown evita reapertura inmediata.

### Paso 5 - OCR fallback y candidatos

Objetivo:
- Si no hay ISBN, usar OCR y ranking de candidatos.

Acciones:
1. Integrar `tesseract.js` bajo demanda.
2. Ejecutar OCR cada N ciclos, no en cada frame.
3. Normalizar texto y enviar a backend.
4. Mostrar top 3 candidatos cuando confianza media.

DoD:
- Sin ISBN visible, OCR genera resultados.
- Se muestran candidatos y permite confirmacion manual.

### Paso 6 - Backend API minimo

Objetivo:
- Implementar endpoints y estructura de matching.

Acciones:
1. Crear FastAPI con rutas definidas.
2. Implementar respuesta estandar (`status`, `confidence`, `candidates`).
3. Agregar capa de servicio desacoplada para resolver Goodreads.
4. Agregar timeouts y manejo de errores.

DoD:
- Endpoints responden con contrato correcto.
- Manejo de errores consistente.

### Paso 7 - Hardening para iPhone/Android

Objetivo:
- Estabilizar PWA en moviles reales.

Acciones:
1. Ajustar FPS para iPhone.
2. Reducir resolucion de analisis en dispositivos lentos.
3. Mejorar mensajes de permisos de camara.
4. Test en iPhone Safari y Android Chrome.

DoD:
- Instalable en ambos.
- Flujo principal usable sin bloqueos.

---

## 11) Comandos sugeridos de arranque (referencia)

### Frontend

```bash
npm create vite@latest frontend -- --template react-ts
cd frontend
npm install
npm install @zxing/browser tesseract.js vite-plugin-pwa
npm run dev
```

### Backend (FastAPI)

```bash
mkdir backend && cd backend
python3 -m venv .venv
source .venv/bin/activate
pip install fastapi uvicorn httpx rapidfuzz python-dotenv redis
uvicorn app.main:app --reload
```

---

## 12) Publicacion en URL publica (para instalar en movil)

Se requiere una URL HTTPS publica.

### Opcion recomendada: Vercel (frontend)

1. Subir proyecto a GitHub:

```bash
git init
git add .
git commit -m "init pwa"
git branch -M main
git remote add origin https://github.com/TU_USUARIO/TU_REPO.git
git push -u origin main
```

2. En Vercel:
   - Login con GitHub.
   - `Add New Project`.
   - Seleccionar repo.
   - Deploy.

3. URL resultado:
   - `https://tu-proyecto.vercel.app`

### Instalacion en movil

- iPhone (Safari): Compartir -> "Anadir a pantalla de inicio".
- Android (Chrome): Menu -> "Instalar app" / "Anadir a pantalla de inicio".

Checklist:
- `manifest.webmanifest` valido.
- Service worker activo.
- Iconos 192/512.
- HTTPS.

---

## 13) Checklist QA minima

1. Detecta ISBN en menos de 2-3 segundos con buena luz.
2. No abre Goodreads dos veces seguidas por el mismo ISBN.
3. Sin ISBN, OCR intenta detectar sin congelar la UI.
4. Con confianza media muestra candidatos.
5. Permisos de camara con mensajes claros.
6. Instalable en iPhone y Android.

---

## 14) Riesgos y mitigaciones

- Goodreads sin API publica robusta:
  - Mantener capa de resolucion desacoplada.
- OCR inestable por iluminacion:
  - OCR espaciado, normalizacion y confirmacion manual.
- Diferencias por navegador:
  - Ajustes de FPS/ROI por plataforma.

---

## 15) Prompt maestro para ejecutar con otra IA

Usa este prompt tal cual:

> Eres un ingeniero senior frontend/backend.
> Quiero crear una PWA instalable para iPhone y Android que escanee libros en tiempo real con camara, sin hacer foto manual, y redirija a Goodreads.
>
> Sigue estrictamente el README de especificacion del proyecto.
> Reglas obligatorias:
> 1) Empieza por el Paso 1 y NO avances al siguiente paso hasta cumplir su DoD.
> 2) En cada paso, primero implementa, despues ejecuta validaciones y al final resume evidencias de DoD.
> 3) Si un requisito no esta claro, toma la decision mas conservadora y documentala.
> 4) No cambies stack ni arquitectura: Vite+React+TS, PWA, ZXing, tesseract.js, backend FastAPI.
> 5) No elimines funcionalidades ya cerradas (escaneo en vivo, ISBN primero, OCR fallback, redireccion Goodreads).
>
> Empieza ahora por el Paso 1.

---

## 16) Notas finales

- Esta especificacion esta preparada para ejecucion por IA con minima ambiguedad.
- Prioridad: robustez de deteccion en moviles reales antes de optimizaciones esteticas.
