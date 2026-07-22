# README - Especificacion ejecutable para IA (cliente Android APK con Flutter: escaner de libros -> Goodreads)

> **Nota de nomenclatura:** "Android nativo" aqui significa **APK instalable en el dispositivo** (no PWA). La UI y la logica son **Flutter/Dart**, no Kotlin/Jetpack Compose puro.

## 1) Objetivo del proyecto

Construir una **aplicacion Android con Flutter** (compilada a APK nativo; **no** Kotlin/Jetpack Compose puro) de **uso personal**, instalable en el propio telefono mediante **APK** (sideload o `adb install`), **sin** publicacion en Google Play Store, que permita:

1. Abrir camara en vivo (sin boton de "hacer foto" obligatorio para el flujo principal).
2. **Dos formas validas de identificar el libro** (no basta con el ISBN):
   - **A — Codigo de barras:** detectar **ISBN / EAN-13** (y normalizar otros EAN/UPC si el lector los devuelve) en tiempo real con **ML Kit Barcode Scanning** sobre el stream unico de camara (seccion **2.1**).
   - **B — Texto visible (titulo / portada):** con la **misma** sesion de camara en vivo, el usuario puede **encuadrar el titulo, autor u otro texto legible** de la portada o lomo; la app debe **extraer texto con OCR** y enviarlo al backend para **buscar / clasificar el libro** (`POST /identify-book` con `ocr_text`, sin `isbn`). No es un extra opcional: es parte del producto descrito en este README.
3. Prioridad practica: si hay **ISBN valido y estable**, usarlo primero (mas fiable) y **pausar OCR** hasta que expire el cooldown o el usuario pulse "Reintentar escaneo"; cuando no haya ISBN estable, ejecutar OCR segun seccion 3 y 2.1.
4. Resolver el libro contra el **backend** y abrir la pagina en **Goodreads** (navegador o app si el sistema lo permite).
5. Evitar falsos positivos y aperturas duplicadas (confirmacion, cooldown, deduplicacion por ISBN o por texto estable segun el flujo).

**Alcance de plataforma (cerrado):** **solo Android**. No iOS, no PWA, no Mac requerido.

**Diferencia respecto a la PWA (`README_BOOK_SCANNER_GOODREADS.md`):** en la PWA el OCR es *fallback* si no hay ISBN; en este cliente Android el OCR por titulo/portada es un **flujo de producto de primera clase** (no opcional), con mas peticiones al backend. El backend compartido debe soportar identificacion frecuente solo por `ocr_text`.

---

## 2) Decisiones cerradas (no debatibles para la IA)

- **Arquitectura cliente**: app **Flutter** compilada solo para **Android** (un solo codigo Dart).
- **Lenguaje UI y logica cliente**: **Dart** (Flutter).
- **Camara en vivo (stream unico)**: paquete **`camera`** (CameraX) como unico consumidor de camara. Barcode y OCR comparten el mismo stream segun seccion **2.1**.
- **Escaneo de codigos en vivo**: **`google_mlkit_barcode_scanning`** sobre frames del stream (priorizar formatos EAN / producto). *Alternativa descartada salvo bloqueo tecnico documentado en codigo:* plugin **`mobile_scanner`** (no sirve para OCR periodico sin barcode; ver seccion 2.1) o Kotlin puro.
- **OCR en imagen**: paquete **`google_mlkit_text_recognition`** sobre frames del mismo stream (seccion **2.1**). No usar otro OCR salvo bloqueo documentado.
- **HTTP cliente**: paquete **`dio`** o **`http`** (elegir uno y usarlo de forma consistente en todo el proyecto).
- **Abrir URLs**: **`url_launcher`** (modo externo / aplicacion predeterminada).
- **Configuracion por entorno**: **`flutter_dotenv`** o `--dart-define` (elegir uno; documentar en `.env.example`). El toggle de UI "Abrir automaticamente" **persiste en `SharedPreferences`** y **sobreescribe** el valor por defecto de `AUTO_OPEN_GOODREADS` del entorno.
- **Backend**: **FastAPI** (mismo contrato que el README PWA; reutilizar `backend/` del monorepo o desplegar aparte).
- **Cache / colas**: **Redis** opcional en backend (MVP puede omitirse).
- **Distribucion cliente**: **solo uso personal** — APK en dispositivos propios (firma debug o release local). **No** Play Store, ficha de tienda, politica de privacidad publica ni cuenta de desarrollador Google Play.

### 2.1) Pipeline de camara unica (critico — no omitir)

Android **no permite** dos consumidores simultaneos de la misma camara. Barcode + OCR deben compartir **un unico stream**.

**Enfoque obligatorio (primario):**

Usar el paquete **`camera`** como unico plugin de camara. En `book_identification.dart`:

1. Iniciar **`CameraController`** (camara trasera, resolucion media — evitar 4K) con **`FocusMode.auto`** / enfoque continuo activo desde el inicio (`setFocusMode(FocusMode.auto)` o equivalente segun version de `camera`). **Critico y no opcional:** sin autofocus continuo, tanto el barcode como el OCR fallaran de forma sistematica en cuanto la distancia al lomo/portada varie — es el factor practico #1 de exito del escaneo, mas incluso que los intervalos de throttling.
2. Suscribirse al stream de imagenes (`startImageStream` o equivalente documentado en la version fijada en `pubspec.yaml`). Los `planes[].bytes` que expone `CameraImage` ya son copias en el heap de Dart (no punteros a buffers nativos que requieran `close()` como en `ImageProxy` de CameraX puro), pero retener/copiar frames completos en cada tick (para "el ultimo frame disponible") genera presion de GC en gama baja: evaluar en dispositivo real y, si hay jank, reducir resolucion del stream antes de tocar los intervalos.
3. Cada **`BARCODE_FRAME_SKIP`** frames del stream (valor por defecto **3** — p. ej. ~10 fps efectivos a 30 fps):
   - Pasar el frame a **`google_mlkit_barcode_scanning`** (deteccion continua de ISBN/EAN).
   - Si el procesamiento anterior de barcode **aun no termino**, **saltar** el frame (no encolar).
4. Cada **`OCR_INTERVAL_MS`** (timer independiente del barcode):
   - Tomar el **ultimo frame disponible** del stream.
   - Recortar la **ROI central** (~60–70 % ancho/alto; alineada con overlay UX).
   - Construir `InputImage` con **formato, bytes y rotacion** correctos (`InputImageMetadata` / `InputImageRotation` segun orientacion del dispositivo).
   - Pasar la ROI a **`google_mlkit_text_recognition`**.

**Por que NO usar `mobile_scanner` como base:** su callback `onDetect` **no dispara en cada frame** (solo cuando hay actividad de barcode). Con portada apuntada al titulo **sin codigo visible**, no hay frames periodicos para OCR. `returnImage: true` ademas degrada rendimiento y puede devolver `image.bytes == null`. **`mobile_scanner` queda descartado** salvo bloqueo tecnico documentado con `camera` + ML Kit; en ese caso el flujo OCR-only queda fuera de alcance hasta resolverlo.

**Reglas de ejecucion en el stream unico:**

- **Un solo** `CameraController`; **nunca** mezclar `camera` con `mobile_scanner`.
- **`isProcessing` es un lock global unico que cubre ambos detectores, no solo OCR.** Barcode: cada **`BARCODE_FRAME_SKIP`** frames (ML Kit barcode); saltar el frame si el ciclo anterior de barcode no termino **o si `isProcessing == true`** (hay una peticion `/identify-book` o `/resolve-goodreads` en vuelo). Sin esta condicion explicita en barcode, una peticion HTTP en curso no bloquea nuevas lecturas de ISBN estable y puede disparar llamadas duplicadas antes de que la deduplicacion post-exito (seccion 8) entre en juego — la dedup por "ya enviado con exito" no cubre peticiones aun en vuelo.
- OCR: cada **`OCR_INTERVAL_MS`**, solo si **`!isProcessing`**, **no** hay ISBN estable en ventana reciente, pantalla de escaneo activa y **no** se supero **`SCAN_TIMEOUT_MS`** sin reset (seccion 8).
- ROI OCR: recorte central; no procesar frame completo en alta resolucion.
- **Hilos / isolates (critico):** los plugins **`google_mlkit_*` usan platform channels** y deben invocarse desde el **isolate principal** de Flutter (`async`/`await`). **No** usar `compute()` ni isolates secundarios para barcode ni OCR — fallara en runtime. Reservar isolates solo para trabajo Dart puro (normalizacion de texto, similitud Levenshtein/Jaro-Winkler). Las peticiones HTTP (`dio`/`http`) van en async sobre el isolate principal; el throttling evita saturar la UI.
- Throttling OCR: si un ciclo OCR tarda mas que **`OCR_INTERVAL_MS`**, **saltar** el siguiente tick (no encolar frames intermedios).
- **Condicion de carrera ISBN/OCR:** al detectar ISBN estable, **cancelar o descartar** cualquier resultado OCR en vuelo antes de llamar a `/identify-book`; no mezclar flujos.
- **Ciclo de vida:** al salir de la pantalla de escaneo, ir a segundo plano o perder permiso de camara: parar `imageStream`, cancelar timers OCR/barcode, liberar instancias ML Kit y llamar `CameraController.dispose()`. Al volver, reiniciar sesion limpia.

### 2.2) Conversion `CameraImage` -> `InputImage` (critico)

Implementar en **`utils/camera_input_image.dart`** y validar en dispositivo real antes de dar por buenos Paso 3 y Paso 5:

- Mapear formato del frame (`ImageFormatGroup` / YUV_420_888 / NV21 segun dispositivo) a `InputImageFormat` de ML Kit.
- Aplicar **`InputImageRotation`** segun `sensorOrientation` + orientacion del dispositivo (no asumir rotation 0).
- Probar que barcode y OCR leen datos coherentes (texto legible, ISBN detectado); si el OCR devuelve basura, revisar esta capa antes de tocar intervalos.

---

## 3) Requisitos funcionales obligatorios

1. No existe boton obligatorio de "hacer foto" para detectar el codigo; el flujo principal es **preview continuo + deteccion en stream**.
2. Escaneo en tiempo real sobre la **vista previa de camara**.
3. Pipeline de deteccion (debe cubrir **codigo de barras y texto de portada**):
   1) **ISBN / EAN-13** por codigo de barras con throttling **`BARCODE_FRAME_SKIP`** (prioridad cuando aparece lectura valida estable).
   2) **OCR sobre la ROI central** (misma sesion de camara, seccion 2.1): cada **`OCR_INTERVAL_MS`**, normalizar texto (`trim`, colapsar espacios multiples a uno) y, si la longitud es **>= `OCR_MIN_TEXT_LENGTH`** (constante en codigo, valor por defecto **10**), evaluar estabilidad (seccion 8) antes de llamar al backend. **Pausar OCR** mientras haya ISBN estable pendiente de procesar o durante **`isProcessing`** / cooldown activo.
   3) Tras identificar libro (`POST /identify-book`), seguir el **flujo post-identify** (seccion 8): candidatos, auto-resolve o confirmacion → `POST /resolve-goodreads` → decidir UX segun **`confidence` de `/resolve-goodreads`**.
4. Comportamiento UX: mensajes que indiquen que se puede **apuntar al codigo de barras o al titulo/autor** ("Buscando codigo ISBN...", "Leyendo titulo / texto...").
5. Si **confianza alta** en `/resolve-goodreads`: abrir Goodreads automaticamente si el toggle "Abrir automaticamente" esta activo.
6. Si **confianza media** en `/identify-book` (candidatos) o `/resolve-goodreads`: mostrar **2–3 candidatos** y permitir elegir.
7. Si **confianza baja** o fallo de red/resolucion: mensaje de reencuadre y boton **"Buscar en Goodreads"** (URL de busqueda generada en cliente o devuelta por backend — seccion 9).
8. La app debe instalarse como **aplicacion Android** (no como PWA).

---

## 4) Requisitos no funcionales

- **Rendimiento**: throttling via **`BARCODE_FRAME_SKIP`** + **`OCR_INTERVAL_MS`**; ML Kit en **`async` sobre isolate principal** (seccion 2.1); no encolar otro OCR ni otra peticion HTTP mientras **`isProcessing == true`**; backoff implicito + pausa con ISBN activo.
- **Bateria / termica**: no bajar `OCR_INTERVAL_MS` por debajo de **600 ms** ni `BARCODE_FRAME_SKIP` por debajo de **2** en dispositivos gama baja sin prueba; valores por defecto recomendados **800 ms** y **3** respectivamente.
- **Pantalla activa**: mantener pantalla encendida en la pantalla de escaneo con **`FLAG_KEEP_SCREEN_ON`** (recomendado: `wakelock_plus`, que aplica el flag nativo al activarse). **No** usar solo `SystemChrome.setEnabledSystemUIMode` — oculta barras del sistema pero **no** evita que la pantalla se apague.
- **Abrir URLs externas**: en `AndroidManifest.xml`, anadir bloque **`<queries>`** para intents HTTP/HTTPS (requerido Android 11+ para `url_launcher` fiable).
- **Red**: preferir **HTTPS** si el backend esta en internet. En LAN local puede usarse HTTP en entorno personal **solo** con configuracion cleartext explicita (seccion 12).
- **Cooldown** tras abrir Goodreads (**2–3 s**) y **deduplicacion**: mismo **ISBN**, mismo **texto OCR normalizado** enviado con exito, o mismo **`goodreads_url`** resuelto.
- **Un solo flujo activo** de procesamiento (`isProcessing`).
- **Permisos**: **CAMERA** en runtime con mensaje claro. **INTERNET** en manifest (Flutter suele anadirlo; verificar). Si se usa **`wakelock_plus`**, anadir **`WAKE_LOCK`** en manifest (segun documentacion de la version fijada en `pubspec.yaml`).
- **Release APK**: reglas **ProGuard/R8** para ML Kit si el build release falla o crashea en runtime (plantilla en seccion 11).

---

## 5) Estructura de carpetas objetivo

```text
bookscanner/                       # Raiz del monorepo (nombre libre; coherente con org com.example.bookscanner)
  mobile/                          # App Flutter (solo Android en scope)
    lib/
      main.dart
      app.dart
      screens/
      widgets/
      services/
        api_client.dart
        book_identification.dart   # orquesta barcode + OCR (seccion 2.1)
      models/
      utils/
        isbn_validation.dart
        text_normalization.dart    # trim, espacios, similitud OCR
        camera_input_image.dart    # CameraImage -> InputImage (formato + rotacion)
    android/
      app/
        src/
          main/
            AndroidManifest.xml
            res/
              xml/
                network_security_config.xml   # cleartext LAN (seccion 12)
        proguard-rules.pro                      # ML Kit en release (seccion 11)
    assets/
      .env                         # Solo si se usa flutter_dotenv (copiar desde .env.example; NO commitear secretos)
    pubspec.yaml
    .env.example                   # Plantilla versionada; copiar a assets/.env
  backend/
    app/
    requirements.txt
    .env.example
  README.md
```

Crear `mobile/` con `flutter create --platforms=android` (seccion 11).

---

## 6) Variables de entorno minimas

### Cliente Flutter (`mobile/assets/.env` con `flutter_dotenv`, o `--dart-define`)

```env
API_BASE_URL=https://tu-backend.example.com
AUTO_OPEN_GOODREADS=true
SCAN_TIMEOUT_MS=12000
OCR_INTERVAL_MS=800
BARCODE_FRAME_SKIP=3
OCR_MIN_TEXT_LENGTH=10
DEVICE=android
```

- **`AUTO_OPEN_GOODREADS`**: valor inicial al instalar; el usuario puede cambiarlo con el toggle (persistido en `SharedPreferences`; el toggle manda en runtime).
- **`BARCODE_FRAME_SKIP`**: procesar 1 de cada N frames del stream para barcode (reduce CPU/termica). Valor por defecto **3**.
- **`OCR_MIN_TEXT_LENGTH`**: minimo de caracteres tras normalizar antes de evaluar estabilidad OCR.
- **`SCAN_TIMEOUT_MS`**: tiempo maximo (ms) en pantalla de escaneo **sin identificar libro** antes de mostrar estado "No se pudo identificar" y detener OCR/barcode hasta que el usuario pulse **"Reintentar escaneo"**. Valor por defecto **12000**. El timer se reinicia al entrar en escaneo o al pulsar reintentar.
- **`locale` en peticiones API**: derivar del dispositivo (`Platform.localeName` o `WidgetsBinding.instance.platformDispatcher.locale`), no hardcodear `es-ES`.
- **Config entorno**: con **`flutter_dotenv`**, el archivo activo es **`mobile/assets/.env`** (declarado en `pubspec.yaml`); requiere **recompilar** para cambiar `API_BASE_URL`. Versionar solo **`mobile/.env.example`** como plantilla.

### Backend (`backend/.env`)

```env
APP_ENV=development
REDIS_URL=redis://localhost:6379/0
REQUEST_TIMEOUT_SECONDS=8
GOOGLE_BOOKS_API_KEY=           # Obligatorio si se usa Google Books API
OPEN_LIBRARY_ENABLED=true       # Open Library no requiere key; respetar rate limits
GOODREADS_RESOLVE_STRATEGY=search_heuristic   # Documentar estrategia elegida (scraping/heuristica/API)
```

- Si una fuente externa falla o no tiene credenciales, el backend debe devolver **`status != "ok"`** o **`confidence` baja**; el cliente activa fallback "Buscar en Goodreads".

---

## 7) Contratos API cerrados

Mismos endpoints que `README_BOOK_SCANNER_GOODREADS.md`. El cliente debe identificar un libro **solo con texto de portada** cuando no hay codigo de barras en encuadre.

### Convencion de campos

- **`isbn`**: si no hay codigo, **omitir el campo** o enviar `null`. **No** enviar string vacio `""` (alinear tipos FastAPI `Optional[str] = None`).
- **`ocr_text`**: texto crudo normalizado en cliente (trim + espacios colapsados); obligatorio en flujo solo-OCR.
- **Mutua exclusion en cliente:** si hay **ISBN estable**, enviar **solo `isbn`** (omitir `ocr_text`). Si el flujo es OCR, enviar **solo `ocr_text`** (omitir `isbn`). **No** enviar ambos en la misma peticion.

### `POST /identify-book`

Request (ISBN — flujo barcode; **sin** `ocr_text`):

```json
{
  "isbn": "978XXXXXXXXXX",
  "locale": "<locale del dispositivo, p. ej. es-ES>",
  "device": "android"
}
```

Request (solo titulo / texto OCR):

```json
{
  "ocr_text": "El nombre del viento Patrick Rothfuss",
  "locale": "<locale del dispositivo, p. ej. es-ES>",
  "device": "android"
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

- Usar **`confidence` y `candidates` de este endpoint** para mostrar lista de candidatos cuando el matching del libro es ambiguo.
- **No** usar esta `confidence` para abrir Goodreads directamente sin pasar por `/resolve-goodreads` (salvo que el backend documente explicitamente `goodreads_url` aqui — no es el caso en este contrato).
- **Esquema cerrado de cada item de `candidates` en este endpoint** (evita ambiguedad de implementacion): `{ "title": string, "author": string, "isbn13": string | null }`. **No** incluye `goodreads_url` — ese campo solo existe en los `candidates` de `/resolve-goodreads` (ver mas abajo). Por tanto, al elegir un candidato de `/identify-book` **siempre** hay que llamar a `/resolve-goodreads` con su `title`/`author`/`isbn13`; nunca se abre una URL directamente desde un candidato de `/identify-book`.

### `POST /resolve-goodreads`

Request:

```json
{
  "title": "Example Book",
  "author": "Example Author",
  "isbn13": "978XXXXXXXXXX"
}
```

Response (match unico):

```json
{
  "status": "ok",
  "confidence": 0.9,
  "goodreads_url": "https://www.goodreads.com/book/show/ID",
  "candidates": []
}
```

Response (ambiguo — varias URLs posibles):

```json
{
  "status": "ok",
  "confidence": 0.72,
  "goodreads_url": null,
  "candidates": [
    {
      "title": "Example Book",
      "author": "Example Author",
      "goodreads_url": "https://www.goodreads.com/book/show/111",
      "confidence": 0.72
    },
    {
      "title": "Example Book (ed. 2010)",
      "author": "Example Author",
      "goodreads_url": "https://www.goodreads.com/book/show/222",
      "confidence": 0.68
    }
  ]
}
```

- Usar **`confidence` de este endpoint** para decidir apertura automatica, boton manual o reencuadre (seccion 8).
- Si `status != "ok"` o sin `goodreads_url` **y** `candidates` vacio: activar fallback de busqueda (seccion 9).
- El backend debe rellenar **`candidates`** cuando haya varias URLs Goodreads plausibles para el mismo titulo/autor/isbn.

### Mock minimo para Pasos 4–5 (hasta backend real)

Implementar mock local (servicio Dart inyectable o FastAPI minimo) que cumpla:

| Entrada | Respuesta mock |
|---------|----------------|
| `isbn` valido conocido (p. ej. `9780000000000`) | `identify-book`: `confidence` 0.95, `book` coherente |
| `ocr_text` contiene `"nombre del viento"` (case insensitive) | `identify-book`: `confidence` 0.75, `candidates` con 2 libros |
| `/resolve-goodreads` con titulo/isbn del mock | `goodreads_url` HTTPS valida (puede ser URL de prueba) + `confidence` 0.9 |

El DoD de Pasos 4–5 se valida contra este mock aunque el Paso 6 no este terminado.

---

## 8) Logica de decision obligatoria

### Que `confidence` usar

| Accion | Fuente de `confidence` |
|--------|-------------------------|
| Mostrar candidatos de **libro** (titulo/autor) | `POST /identify-book` → campo `candidates` (y su `confidence` por item si existe) |
| Abrir Goodreads / boton "Abrir resultado" / reencuadre tras resolver URL | `POST /resolve-goodreads` → campo **`confidence`** |
| Fallback "Buscar en Goodreads" | Cuando `/resolve-goodreads` falla, `confidence < 0.60`, o sin `goodreads_url` |

### Flujo tras `/identify-book` (obligatorio)

| Resultado de `/identify-book` | Accion del cliente |
|-------------------------------|-------------------|
| `candidates` no vacio (confianza media / ambigua) | Mostrar **2–3 candidatos**; al elegir uno → **siempre** `POST /resolve-goodreads` con su `title`/`author`/`isbn13` (los candidatos de `/identify-book` **no** traen `goodreads_url`; ver esquema cerrado en seccion 7) → aplicar umbrales de resolve |
| `candidates` vacio, `book` presente y **`confidence >= 0.85`** | Llamar **`/resolve-goodreads` automaticamente** con datos de `book` (sin pantalla intermedia de confirmacion) |
| `candidates` vacio, `book` presente y **`0.60 <= confidence < 0.85`** | Mostrar resumen del libro detectado + boton **"Confirmar y buscar en Goodreads"** → `/resolve-goodreads` |
| `confidence < 0.60` o `status != "ok"` | Mensaje reencuadre + boton **"Buscar en Goodreads"** (fallback seccion 9) |

En todos los casos, la **apertura automatica de URL** depende exclusivamente de **`confidence` de `/resolve-goodreads`** (no de identify-book).

### Umbrales (sobre `/resolve-goodreads`)

- `confidence >= 0.85`: si toggle "Abrir automaticamente" activo → abrir `goodreads_url`; si no → boton "Abrir en Goodreads".
- `0.60 <= confidence < 0.85`: mostrar **top 3** `candidates` de `/resolve-goodreads`; si vacio, usar candidatos ya mostrados de `/identify-book`. Al elegir candidato: si el item ya trae **`goodreads_url`**, abrirla directamente (aplicar umbrales de apertura); solo llamar de nuevo a `/resolve-goodreads` si el candidato **no** incluye URL.
- `confidence < 0.60`: no abrir automaticamente; mensaje reencuadre + boton **"Buscar en Goodreads"**.

### Estabilidad antes de llamar al backend

- **Codigo de barras:** **2–3 lecturas consecutivas** del mismo ISBN valido → entonces `identify-book` (+ `resolve-goodreads` si aplica).
- **OCR:** **2 lecturas OCR consecutivas** (separadas por al menos un intervalo) cuyo texto normalizado cumple **ambas**:
  - longitud >= `OCR_MIN_TEXT_LENGTH`
  - **similitud >= 0.85** entre ellas (ratio `Levenshtein` o `Jaro-Winkler` — implementar en `text_normalization.dart` y documentar funcion elegida)
- **`0.85` es un punto de partida, no un valor cerrado:** con textos cerca del minimo (`OCR_MIN_TEXT_LENGTH` = 10), un solo caracter mal leido por el OCR puede bajar la similitud muy por debajo de 0.85 (falso negativo de estabilidad) o, al reves, textos cortos distintos pueden superarlo por coincidencia (falso positivo). Validar el umbral con lecturas reales en dispositivo antes de cerrarlo en produccion; si hay muchos falsos negativos con textos cortos, considerar un umbral variable (mas permisivo cuanto mas corto el texto) en vez de una constante fija.
- Solo tras estabilidad OCR → `POST /identify-book` con `ocr_text` (sin `isbn`). **No** llamar al backend en cada frame OCR inestable.

### Otros controles

- **Timeout de escaneo:** si transcurre **`SCAN_TIMEOUT_MS`** sin identificar libro (ni ISBN estable ni OCR estable procesado con exito), mostrar **"No se pudo identificar"**, pausar barcode/OCR y esperar **"Reintentar escaneo"**.
- **Cooldown** 2–3 s tras abrir enlace Goodreads.
- No relanzar si mismo **ISBN**, mismo **`ocr_text` normalizado** ya enviado con exito, o mismo **`goodreads_url`** que el ultimo exito.
- Un solo **`isProcessing`** global.

---

## 9) UX minima obligatoria

- Marco / overlay central de encuadre (ROI alineada con recorte OCR).
- Texto de ayuda: apuntar al **codigo de barras o titulo/autor** en portada/lomo.
- Estados visibles:
  - "Buscando codigo ISBN..."
  - "Leyendo titulo / texto..."
  - "Buscando libro..."
  - "Libro detectado"
  - "No se pudo identificar"
- Toggle: **"Abrir automaticamente al detectar"** (persistido; override de `AUTO_OPEN_GOODREADS`).
- Boton: **"Abrir resultado"** (ultima `goodreads_url` valida).
- Boton: **"Reintentar escaneo"** (resetea cooldown, deduplicacion y estabilidad pendiente).
- Boton fallback obligatorio: **"Buscar en Goodreads"** — abre `https://www.goodreads.com/search?q=<titulo o ocr_text codificado>` cuando no hay URL fiable.

Material Design 3 recomendado (tema claro/oscuro opcional).

---

## 10) Plan por pasos para ejecutar con IA (secuencial)

Regla global: **la IA no puede pasar al siguiente paso sin cumplir el DoD del paso actual**.

### Paso 1 - Entorno y proyecto Flutter (solo Android)

Objetivo:
- Proyecto Flutter compilable solo para Android.

Acciones:
1. Instalar Flutter SDK estable y Android Studio; `flutter doctor` OK en Android.
2. `flutter create --platforms=android mobile --org com.example.bookscanner` (no crear targets iOS/web).
3. Fijar **`minSdkVersion`** al **maximo** exigido por **`camera`**, **`google_mlkit_barcode_scanning`** y **`google_mlkit_text_recognition`** segun pub.dev en el momento de implementacion (consultar los tres; no asumir solo 21).
4. Anadir dependencias base: `camera`, `google_mlkit_barcode_scanning`, `google_mlkit_text_recognition`, cliente HTTP, `url_launcher`, config entorno (`flutter_dotenv` o equivalente).

DoD:
- `flutter run -d android` despliega la app.
- `flutter build apk` finaliza sin errores.

### Paso 2 - Pipeline de camara unica, permisos y preview

Objetivo:
- Stream unico de camara operativo, esqueleto de `book_identification.dart`, permisos, red LAN y pantalla encendida.

Acciones:
1. Permiso **CAMERA** en manifest + runtime; flujo si el usuario deniega.
2. Crear **`services/book_identification.dart`**: iniciar `CameraController`, preview en vivo, suscripcion al stream de imagenes (seccion **2.1**). OCR puede estar desactivado (`OCR_INTERVAL_MS` no procesa aun) pero la arquitectura debe ser la definitiva.
3. **Cleartext HTTP (solo dev/LAN):** `network_security_config.xml` limitado al dominio/IP del backend local + referencia en `AndroidManifest.xml`. **No** habilitar cleartext global en builds release expuestos a internet.
4. Mantener pantalla encendida (`FLAG_KEEP_SCREEN_ON` / `wakelock_plus`).
5. Anadir **`<queries>`** en manifest para `url_launcher` (HTTP/HTTPS).
6. Implementar esqueleto de **`utils/camera_input_image.dart`** (conversion frame → `InputImage`; seccion **2.2**).
7. Gestion de **ciclo de vida** en `book_identification.dart`: `dispose()` de camara y cancelacion de timers al salir de la pantalla (seccion **2.1**).

DoD:
- Camara trasera con preview continuo; sin crash si se deniega permiso.
- `book_identification.dart` existe y usa **un solo** `CameraController`, con **autofocus continuo activo** desde el arranque (seccion 2.1, paso 1) — verificar visualmente que la imagen enfoca sola al variar la distancia, sin toque manual en pantalla.
- `network_security_config.xml` y cleartext configurados para IP LAN de desarrollo; manifest referencia el XML (validacion estatica; **sin** peticiones HTTP aun — el cliente API es Paso 4).
- Al navegar fuera de escaneo y volver, la camara se reinicia sin crash ni camara bloqueada.

### Paso 3 - Deteccion EAN-13 / normalizacion ISBN

Objetivo:
- ISBN estable desde barcode sobre el stream unico (Paso 2).

Acciones:
1. Integrar **`google_mlkit_barcode_scanning`** en `book_identification.dart` sobre frames del stream; filtrar formatos no producto si el API lo permite.
2. `utils/isbn_validation.dart` (ISBN-13 978/979 + checksum; ISBN-10 si aplica).
3. Confirmacion **2–3 lecturas consecutivas iguales** antes de disparar flujo API.

DoD:
- Libro real detecta ISBN en luz normal.
- Sin multiples navegaciones por el mismo ISBN, **incluyendo mientras una peticion anterior sigue en vuelo** (`isProcessing` bloquea tambien al detector de barcode, no solo al OCR; seccion 2.1).
- Sigue siendo **un solo** stream de camara (sin segundo plugin).
- **`camera_input_image.dart`** produce `InputImage` con rotacion/formato correctos (ISBN detectado coherente en dispositivo real; seccion **2.2**).

### Paso 4 - Cliente API, mock y flujo Goodreads

Objetivo:
- Flujo completo ISBN → identify → resolve → abrir URL, con mock si no hay backend.

Acciones:
1. `ApiClient` con `API_BASE_URL`.
2. Mock segun tabla seccion 7 hasta backend real (Paso 6).
3. Secuencia: `identify-book` → `resolve-goodreads` → `url_launcher`.
4. Logica de confianza (seccion 8), cooldown, **`SCAN_TIMEOUT_MS`**, fallback "Buscar en Goodreads".

DoD:
- Con mock o backend, abre URL Goodreads cuando `/resolve-goodreads` `confidence >= 0.85` y toggle activo.
- Errores de red sin crash; fallback de busqueda visible.
- Con `API_BASE_URL=http://192.168.x.x:8000` (o mock), las peticiones llegan al destino en LAN (dispositivo) o emulador (`10.0.2.2`).

### Paso 5 - OCR por titulo / portada (obligatorio)

Objetivo:
- Activar identificacion por titulo/autor sin barcode visible, reutilizando el pipeline del Paso 2.

Acciones:
1. En `book_identification.dart`, activar timer **`OCR_INTERVAL_MS`** sobre el **mismo** stream (seccion **2.1**): ROI central, `InputImage` con rotacion correcta, **`google_mlkit_text_recognition`**.
2. `text_normalization.dart`: normalizar + similitud >= 0.85 en 2 pasadas consecutivas (separadas por al menos un intervalo).
3. Pausar OCR con ISBN estable / `isProcessing` / cooldown / timeout de escaneo.
4. `POST /identify-book` solo con `ocr_text` (sin campo `isbn`) tras estabilidad; aplicar flujo post-identify (seccion 8).

DoD:
- Libro **sin barcode en encuadre** pero **titulo legible** → tras unos segundos envia `ocr_text` y muestra resultado o candidatos (mock o backend). **Probar en dispositivo fisico** (emulador insuficiente para validar OCR).
- UI no congelada > 500 ms perceptibles de forma repetida.
- **`flutter build apk --release`** probado en dispositivo real desde este paso (ProGuard ML Kit, seccion 11).
- OCR devuelve texto coherente (no basura sistematica) gracias a **`camera_input_image.dart`** validado en hardware real (seccion **2.2**).

### Paso 6 - Backend FastAPI (si no existe en el repo)

Objetivo:
- Endpoints reales compartibles con PWA.

Acciones:
1. `POST /identify-book` y `POST /resolve-goodreads` (seccion 7).
2. `identify-book` solo con `ocr_text`: fuzzy / ranking (Open Library, Google Books u otra fuente documentada). Configurar variables de seccion **6** (`GOOGLE_BOOKS_API_KEY`, etc.).
3. `resolve-goodreads`: resolucion desacoplada; rellenar **`candidates`** con **`goodreads_url` por item** cuando haya varias URLs plausibles; si scraping/heuristica falla → baja `confidence` o `status` de error (cliente usa fallback busqueda).
4. Timeouts, `status`, `confidence`, `candidates`. Documentar en README del backend la fuente elegida y limites de rate.

DoD:
- Pruebas manuales con `curl` local y remoto.
- Caso OCR-only devuelve candidatos o match razonable.

### Paso 7 - Pulido Android e instalacion personal

Objetivo:
- APK estable para uso diario.

Acciones:
1. Application ID y nombre visibles razonables; icono basico opcional.
2. Firma debug o keystore release **fuera del repo**.
3. Verificar **`flutter build apk --release`** con reglas ProGuard ML Kit (seccion 11).
4. Instalar en dispositivo real (`adb install` o sideload).
5. Probar ambos flujos en hardware real.

DoD:
- APK release instalable.
- Flujo **camara → ISBN → Goodreads** verificado en dispositivo real.
- Flujo **camara → OCR → identify (sin isbn) → candidatos/Goodreads** verificado en dispositivo real.

**Fuera de alcance:** Google Play, Data safety, politica de privacidad publica, AAB.

---

## 11) Comandos sugeridos de arranque (referencia)

### Flutter

```bash
flutter create --platforms=android mobile --org com.example.bookscanner
cd mobile
flutter pub add camera google_mlkit_barcode_scanning google_mlkit_text_recognition dio url_launcher flutter_dotenv wakelock_plus
flutter pub get
flutter run -d android
```

### Build APK

```bash
cd mobile
flutter build apk --debug
flutter build apk   # release local
```

APK: `mobile/build/app/outputs/flutter-apk/`.

### ProGuard / R8 (release + ML Kit)

Si el release crashea al abrir camara u OCR, anadir en `android/app/proguard-rules.pro` (ajustar segun versiones):

```proguard
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.mlkit.**
```

### Backend (FastAPI)

```bash
cd backend
python3 -m venv .venv
source .venv/bin/activate
pip install fastapi uvicorn httpx rapidfuzz python-dotenv redis
uvicorn app.main:app --reload --host 0.0.0.0
```

(`--host 0.0.0.0` necesario para alcanzar el backend desde el telefono en LAN.)

---

## 12) Instalacion, red y pruebas (Android, uso personal)

- Instalar APK por USB, nube privada o `adb install`.
- Activar **orígenes desconocidos** solo en entornos de confianza.
- **LAN:** telefono y PC en la misma WiFi; `API_BASE_URL=http://<IP_PC>:8000`.
- **Cleartext obligatorio en Android 9+** para HTTP local — ejemplo `network_security_config.xml`:

```xml
<?xml version="1.0" encoding="utf-8"?>
<network-security-config>
  <domain-config cleartextTrafficPermitted="true">
    <domain includeSubdomains="false">192.168.1.100</domain>
    <!-- Anadir IP real del PC de desarrollo -->
  </domain-config>
</network-security-config>
```

En `AndroidManifest.xml` (application): `android:networkSecurityConfig="@xml/network_security_config"`.

**Nota IP dinamica:** la mayoria de routers domesticos asignan IP por DHCP y puede cambiar entre reinicios del PC/router, rompiendo silenciosamente tanto `network_security_config.xml` (dominio permitido desactualizado) como `API_BASE_URL`. Mitigacion recomendada: reservar IP estatica para el PC de desarrollo en el router (DHCP reservation), o en su defecto documentar que hay que revisar/actualizar ambos valores si el backend deja de responder desde el telefono.

Ejemplo **`<queries>`** para `url_launcher` (dentro de `<manifest>`, hermano de `<application>`):

```xml
<queries>
  <intent>
    <action android:name="android.intent.action.VIEW" />
    <data android:scheme="https" />
  </intent>
  <intent>
    <action android:name="android.intent.action.VIEW" />
    <data android:scheme="http" />
  </intent>
</queries>
```

- **Emulador:** host = `10.0.2.2`.
- **Internet:** usar HTTPS; no commitear secretos.

---

## 13) Checklist QA minima (Android)

1. ISBN en 2–5 s con buena luz en dispositivo real.
2. Titulo legible sin barcode → OCR → busqueda → candidatos o resultado.
3. No doble apertura Goodreads (cooldown + deduplicacion).
4. OCR no congela UI de forma prolongada.
5. Confianza media → candidatos elegibles.
6. `/resolve-goodreads` falla → boton "Buscar en Goodreads" funciona.
7. Permisos camara OK; recuperacion tras denegar.
8. HTTP LAN funciona con `network_security_config`.
9. `flutter analyze` sin errores bloqueantes acordados.
10. Tras **`SCAN_TIMEOUT_MS`** sin match → estado timeout + reintentar funciona.
11. Identify alta confianza sin candidatos → `/resolve-goodreads` automatico (seccion 8).
12. Salir de escaneo y volver: camara se reinicia sin crash ni bloqueo del hardware.
13. Con ISBN estable, `/identify-book` se envia **solo con `isbn`** (sin `ocr_text`).
14. Autofocus continuo activo desde el arranque de la camara (sin necesidad de tocar la pantalla) en distintas distancias al libro.
15. Primera ejecucion en el dispositivo con internet real (no solo LAN): los modelos ML Kit se descargan y el escaneo funciona sin reinstalar la app.
16. Con una peticion `/identify-book` o `/resolve-goodreads` en vuelo, una nueva lectura de ISBN estable **no** dispara una segunda peticion en paralelo.

---

## 14) Riesgos y mitigaciones

- **Goodreads sin API publica estable:** resolucion en backend desacoplada; **fallback obligatorio** de busqueda en cliente; no bloquear UX si scraping falla.
- **Camara unica barcode + OCR:** enfoque primario **`camera` + ML Kit** (seccion 2.1). No usar `mobile_scanner` como base: no proporciona frames periodicos para OCR sin barcode.
- **Rotacion / formato de imagen OCR:** si el OCR lee basura o nada, revisar `InputImageMetadata` (rotacion y formato del frame) antes de subir `OCR_INTERVAL_MS`.
- **Variedad de camaras Android:** probar gama baja; ROI reducida; subir `OCR_INTERVAL_MS` si hay thermal throttling.
- **Cambios en plugins:** versiones fijadas en `pubspec.yaml`; regresion en dispositivo real al actualizar.
- **OCR costoso:** pausar con ISBN activo; ROI pequena; no parallelizar OCR con peticiones HTTP.
- **Isolates con ML Kit:** no usar `compute()` para plugins ML Kit (seccion **2.1**).
- **Camara bloqueada / leak:** implementar dispose y ciclo de vida (seccion **2.1**); probar salir y volver a escaneo.
- **Autofocus:** sin enfoque continuo activo (seccion 2.1, paso 1), tanto barcode como OCR fallan de forma sistematica al variar la distancia al libro; verificar en el Paso 2/3 que el `CameraController` fuerza `FocusMode.auto` desde el arranque, no solo al pulsar la pantalla.
- **Modelos ML Kit y Google Play Services:** `google_mlkit_barcode_scanning` y `google_mlkit_text_recognition` (variante *unbundled*, la que instalan estos paquetes por defecto) dependen de Google Play Services y **descargan el modelo on-device la primera vez que se usan**, lo cual requiere conexion a internet inicial y puede tardar unos segundos/minutos segun red. En un dispositivo personal con Play Services actualizado no deberia ser bloqueante, pero conviene probar la primera ejecucion con el telefono conectado a internet (no solo LAN local) antes de asumir que el escaneo funciona "en frio".
- **Lock `isProcessing` incompleto:** si no se aplica tambien al detector de barcode (seccion 2.1), pueden dispararse peticiones `/identify-book` duplicadas mientras una peticion anterior sigue en vuelo, antes de que la deduplicacion post-exito de la seccion 8 pueda actuar.

---

## 15) Prompt maestro para ejecutar con otra IA

> Eres un ingeniero senior Flutter/Android y backend Python.
> Quiero una aplicacion **solo Android** con Flutter, de **uso personal**, que escanee libros en tiempo real con la camara, sin foto manual obligatoria, y abra Goodreads usando un backend FastAPI. **No** publiques en Play Store; basta APK instalable en mi dispositivo.
>
> Sigue estrictamente `README_BOOK_SCANNER_ANDROID_NATIVO.md` del repositorio.
> Reglas obligatorias:
> 1) Empieza por el Paso 1 y NO avances al siguiente paso hasta cumplir su DoD.
> 2) En cada paso, implementa, valida con `flutter analyze` / builds indicados y resume evidencias de DoD.
> 3) Implementa el **pipeline de camara unica** con **`camera` + ML Kit barcode + ML Kit OCR** (seccion 2.1); nunca abras dos consumidores de camara ni uses `mobile_scanner` salvo bloqueo documentado.
> 4) Usa **`confidence` de `/resolve-goodreads`** para abrir URLs; **`/identify-book`** para candidatos de libro y flujo post-identify (seccion 8).
> 5) No cambies el stack cerrado salvo bloqueo tecnico documentado en codigo.
> 6) Incluye cleartext LAN, `<queries>` para url_launcher, mock de seccion 7, estabilidad OCR (similitud >= 0.85), `SCAN_TIMEOUT_MS`, `BARCODE_FRAME_SKIP`, fallback "Buscar en Goodreads".
> 7) **No** uses `compute()` ni isolates secundarios para ML Kit; solo async en isolate principal (seccion 2.1).
> 8) Implementa ciclo de vida de camara (dispose, cancelar timers) y `camera_input_image.dart` (seccion 2.2).
>
> Empieza ahora por el Paso 1.

---

## 16) Notas finales

- Cliente Android Flutter; backend y contratos API compartibles con la PWA.
- OCR por titulo es flujo principal en Android (no solo fallback como en PWA).
- Uso personal; no Google Play Store.
- Prioridad: robustez en dispositivos reales > estetica.
- No se requiere Mac ni cuenta Apple.

---

## 17) Prerrequisitos humanos (checklist antes de codificar)

| Requisito | Para que |
|-----------|----------|
| PC con Windows o Linux (o Mac) | Desarrollo Flutter + Android SDK |
| Android Studio | SDK, emulador, build tools |
| Dispositivo Android fisico (recomendado) | Camara, OCR, APK real |
| Cable USB o red local | `adb install` / LAN al backend |
| Backend accesible desde el telefono | WiFi (`IP:8000`), tunel o HTTPS |
| Keystore propio (opcional) | APK release; guardar fuera del repo |
| Google Play Services actualizado en el dispositivo + conexion a internet en la primera ejecucion | Descarga de modelos on-device de ML Kit (barcode + OCR); sin esto el escaneo no funciona en frio (seccion 14) |
| IP LAN estatica o reservada para el PC de desarrollo (recomendado) | Evitar que cambie el DHCP y rompa `network_security_config.xml` / `API_BASE_URL` (seccion 12) |

**No necesario:** cuenta Google Play Developer, AAB, politica de privacidad publica para tienda.

---

## 18) Checklist de instalacion en Windows (antes de probar)

Checklist paso a paso para dejar un PC con **Windows 10/11** listo para compilar, instalar y probar la app. Marca cada punto al completarlo.

### A) Software en el PC (obligatorio)

- [ ] **Git for Windows** instalado ([https://git-scm.com/download/win](https://git-scm.com/download/win)). Flutter lo usa internamente.
- [ ] **Flutter SDK estable** descargado y descomprimido en una ruta **sin espacios** (p. ej. `C:\src\flutter`). Descarga: [https://docs.flutter.dev/get-started/install/windows](https://docs.flutter.dev/get-started/install/windows).
- [ ] Variable de entorno **`Path`** incluye `C:\src\flutter\bin` (Panel de control → Sistema → Configuracion avanzada → Variables de entorno). Abrir **PowerShell nueva** tras cambiar `Path`.
- [ ] **Android Studio** instalado ([https://developer.android.com/studio](https://developer.android.com/studio)) con:
  - [ ] Android SDK (API reciente)
  - [ ] Android SDK Platform-Tools (`adb`)
  - [ ] Android SDK Build-Tools
- [ ] En Android Studio → **SDK Manager**: instalar al menos una **Android SDK Platform** compatible con el `minSdkVersion` del proyecto.
- [ ] Licencias Android aceptadas:

```powershell
flutter doctor --android-licenses
```

- [ ] **`flutter doctor`** sin errores bloqueantes en la linea **Android toolchain** (avisos menores pueden quedar; errores de Android SDK/licencias no).

### B) Software en el PC (recomendado / segun escenario)

- [ ] **Python 3.10+** instalado ([https://www.python.org/downloads/windows/](https://www.python.org/downloads/windows/)) con opcion **"Add python.exe to PATH"** marcada — solo si vas a levantar el backend FastAPI en el PC (seccion 11).
- [ ] **Redis** en Windows (opcional; el MVP del backend puede omitirlo segun seccion 6).
- [ ] **Visual Studio Build Tools** o **Visual Studio** con workload **"Desktop development with C++"** — solo si `flutter doctor` lo pide para plugins nativos (habitual en Windows).

### C) Dispositivo Android (muy recomendado)

- [ ] Telefono con **depuracion USB** activada (Opciones de desarrollador).
- [ ] Cable USB de datos (no solo carga).
- [ ] Driver USB del fabricante instalado en Windows si `adb devices` no lista el telefono (Samsung, Xiaomi, etc. suelen requerir driver propio).
- [ ] En el telefono, al conectar: elegir modo **Transferencia de archivos (MTP)** si el fabricante lo pide para que aparezca en ADB.
- [ ] **Google Play Services** actualizado en el dispositivo.
- [ ] **Internet en el movil** la primera vez que abras la app (descarga modelos ML Kit; seccion 14).
- [ ] **Origenes desconocidos** / instalar apps desconocidas permitido para sideload del APK (uso personal).

Comprobar conexion ADB en **PowerShell**:

```powershell
adb devices
```

Debe aparecer el dispositivo como `device` (no `unauthorized`; si sale `unauthorized`, acepta el dialogo RSA en el telefono).

### D) Red local (si el backend corre en el PC)

- [ ] PC y telefono en la **misma WiFi**.
- [ ] Conocer la **IP LAN del PC** (PowerShell):

```powershell
ipconfig
```

Buscar `Direccion IPv4` de la interfaz WiFi (p. ej. `192.168.1.100`).

- [ ] (Recomendado) **IP reservada** para el PC en el router (DHCP reservation) para que no cambie entre reinicios (seccion 12).
- [ ] Firewall de Windows: permitir **Python/uvicorn** en red privada (puerto **8000**) o desactivar temporalmente el firewall solo para la prueba en LAN de confianza.
- [ ] En `mobile/assets/.env` (o `--dart-define`): `API_BASE_URL=http://<IP_PC>:8000`.
- [ ] En `network_security_config.xml`: mismo `<domain>` con la IP del PC (seccion 12).

### E) Proyecto y primera ejecucion

- [ ] Repositorio clonado o carpeta del monorepo con `mobile/` y opcionalmente `backend/`.
- [ ] Dependencias Flutter instaladas (seccion 11):

```powershell
cd mobile
flutter pub get
```

- [ ] Dispositivo conectado o emulador Android abierto desde Android Studio.
- [ ] Primera ejecucion en dispositivo:

```powershell
flutter run -d android
```

- [ ] Build APK debug (instalable):

```powershell
flutter build apk --debug
```

APK generado en: `mobile\build\app\outputs\flutter-apk\`.

- [ ] Instalar APK por USB:

```powershell
adb install -r build\app\outputs\flutter-apk\app-debug.apk
```

### F) Backend en el PC (opcional hasta Paso 6; mock cubre Pasos 4-5)

- [ ] Entorno virtual y dependencias (PowerShell, desde `backend/`):

```powershell
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install fastapi uvicorn httpx rapidfuzz python-dotenv redis
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

- [ ] `--host 0.0.0.0` obligatorio para que el telefono en WiFi alcance el PC.
- [ ] Probar desde el PC:

```powershell
curl http://127.0.0.1:8000/docs
```

- [ ] Probar desde el telefono (navegador): `http://<IP_PC>:8000/docs` — si no carga, revisar firewall e IP.

### G) Verificacion minima antes de dar por bueno el entorno

- [ ] `flutter doctor` → Android OK.
- [ ] `adb devices` → telefono listado.
- [ ] `flutter run -d android` → app abre preview de camara sin crash.
- [ ] (Dispositivo real) Autofocus activo al acercar/alejar un libro.
- [ ] (Dispositivo real + internet primera vez) Barcode u OCR responden tras unos segundos.
- [ ] (Con backend o mock) Peticion a `/identify-book` llega al destino configurado en `API_BASE_URL`.

### H) Lo que NO hace falta en Windows

- [ ] Mac / Xcode
- [ ] Cuenta Google Play Developer
- [ ] Keystore (solo para APK release firmado; debug basta para probar)

Fin del documento.
