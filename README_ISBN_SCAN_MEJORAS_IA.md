# README — Mejoras de detección ISBN (instrucciones para IA)

Documento **ejecutable paso a paso** para implementar cambios en el frontend PWA y mejorar la lectura de códigos EAN-13 / ISBN cuando la imagen llega con poca calidad al decodificador.

**Reglas para la IA que ejecute esto**

1. Seguir los pasos **en orden**; no saltar pasos salvo que un paso indique explícitamente que es opcional.
2. No cambiar el stack (seguir Vite + React + TS, `@zxing/browser`, `@zxing/library`).
3. No leer ni modificar carpetas `vendor` salvo estricta necesidad.
4. Tras cada paso, verificar que `npm run build` en `frontend/` termina sin errores.
5. Cambios mínimos y localizados: no refactorizar archivos no mencionados.

**Contexto técnico (estado actual)**

- Cámara: `frontend/src/hooks/useCamera.ts` — `getUserMedia` con `facingMode: 'environment'` y resolución ideal ~1280×720.
- Captura y ROI: `frontend/src/hooks/useScanLoop.ts` — recorte central cuadrado ~60% del lado corto del vídeo, dibujo a canvas oculto.
- Decodificación: `frontend/src/hooks/useISBNReader.ts` — `BrowserMultiFormatReader`, `decodeFromCanvas` sobre el `ImageData` del ROI.
- UI / tap: `frontend/src/components/CameraView.tsx` — overlay ROI, tap en vídeo con intentos de enfoque poco portables.

**Objetivo global**

Aumentar la probabilidad de decodificación en condiciones difíciles mediante: más resolución de stream cuando el navegador lo permita, más píxeles efectivos en el bitmap que consume ZXing, hints de decodificación adecuados, y ajustes configurables sin romper el flujo actual.

---

## Paso 1 — Resolución del stream de vídeo

**Archivo:** `frontend/src/hooks/useCamera.ts`

**Acciones**

1. En `getOptimalConstraints()`, subir los valores `ideal` de `width` y `height` del track de vídeo (objetivo orientativo: **1920×1080** o el máximo razonable que ya uses en el proyecto; mantener `facingMode: 'environment'` y `audio: false`).
2. Añadir, si encaja con el estilo del archivo, límites `min` modestos en ancho/alto para evitar streams demasiado pequeños (p. ej. mínimo 640×480 o equivalente) **sin** hacer fallar `getUserMedia` en dispositivos flojos: si hace falta, usar un segundo intento con constraints más relajadas (patrón: intento “alto” → catch → intento “medio” con solo `facingMode` o ideales menores).
3. No eliminar el manejo de errores ni los logs útiles existentes salvo que dupliquen información; preferir añadir un log breve con **`videoWidth` / `videoHeight` reales** del elemento vídeo tras `play()` (o donde ya se logueen dimensiones) para comprobar que el navegador no está entregando resolución menor de la esperada.

**DoD**

- `getUserMedia` sigue funcionando en desktop y, en la medida de lo posible, en móvil.
- El código compila y `npm run build` pasa.
- Queda trazabilidad (log o comentario mínimo) de la resolución efectiva del vídeo.

---

## Paso 2 — Preparar imagen para ZXing (escala y nitidez)

**Archivos:** `frontend/src/hooks/useISBNReader.ts` y, si la IA lo considera más limpio, un util nuevo p. ej. `frontend/src/utils/barcodeFrame.ts` (opcional pero recomendado).

**Acciones**

1. Antes de llamar a `decodeFromCanvas`, **escalar** el contenido del ROI a un tamaño mínimo en píxeles en el lado largo (valor orientativo: **mínimo 960–1280 px** en el mayor de ancho/alto del recorte; implementar como constante o `import.meta.env.VITE_*` si ya existe convención de env en el proyecto).
2. Al dibujar en canvas intermedio, configurar el contexto 2D con **`imageSmoothingEnabled = false`** para no suavizar las barras.
3. Mantener el flujo actual: seguir partiendo del `ImageData` que ya entrega el scan loop; la ampliación ocurre **solo** en la ruta hacia ZXing (no hace falta cambiar la resolución del vídeo en pantalla).
4. Opcional (marcado como tal en código con comentario breve): función de **gris + contraste** sobre píxeles; debe poder **desactivarse** con una constante booleana para comparar comportamiento.

**DoD**

- ZXing recibe un canvas con más píxeles que el ROI crudo cuando el ROI es pequeño.
- Build OK.
- No se bloquea el hilo de forma obvia (evitar bucles enormes; el ROI ya está acotado).

---

## Paso 3 — Hints ZXing (EAN-13 + TRY_HARDER)

**Archivo:** `frontend/src/hooks/useISBNReader.ts`

**Acciones**

1. Importar desde `@zxing/library` lo necesario para establecer hints (p. ej. `DecodeHintType`, `BarcodeFormat` — usar los nombres exactos de la versión instalada en `package.json`).
2. Al crear `BrowserMultiFormatReader`, pasar un `Map` de hints que incluya:
   - **Formatos posibles** centrados en **EAN-13** (y cualquier otro imprescindible para ISBN-10 en tu flujo, si aplica; si no, solo EAN-13).
   - **`TRY_HARDER`** (o el equivalente en la versión de la librería) activado.
3. Conservar la validación ISBN existente (`validateISBN`); no relajar checksums sin decisión explícita del producto.

**DoD**

- El lector no intenta decodificar formatos irrelevantes de forma prioritaria (menos ruido / más foco en ISBN).
- Build OK.
- Comportamiento previo (callbacks, debounce, historial) intacto salvo mejoras de detección.

---

## Paso 4 — ROI y FPS (ajuste conservador)

**Archivo:** `frontend/src/hooks/useScanLoop.ts` (y opcionalmente lectura de env en el mismo hook o en un pequeño módulo de config).

**Acciones**

1. Parametrizar el factor del ROI actual (~0.6) mediante constante o variable de entorno `VITE_SCAN_ROI_RATIO` (con fallback al valor actual si no está definida).
2. Documentar en un comentario breve que un ROI **demasiado pequeño** puede recortar el código y que **demasiado grande** reduce píxeles por barra; la IA puede proponer un valor por defecto ligeramente distinto **solo** si justifica el cambio en el comentario (cambio pequeño, p. ej. 0.65–0.75).
3. Opcional: exponer `VITE_SCAN_FPS_IOS` y `VITE_SCAN_FPS_ANDROID` si el README del proyecto ya los menciona y aún no se usan; leer con `import.meta.env` y parsear a número con fallback a los FPS actuales del hook.

**DoD**

- ROI y FPS siguen siendo funcionales; valores por defecto no rompen desktop/móvil.
- Build OK.

---

## Paso 5 — Tap-to-focus y honestidad UX

**Archivo:** `frontend/src/components/CameraView.tsx`

**Acciones**

1. Revisar `handleVideoTap`: si se mantienen `pointsOfInterest` o ajustes de brillo, añadir comentario claro de que son **best-effort** y no garantizan AF en todos los navegadores.
2. Opcional: usar `track.getCapabilities?.()` y `track.applyConstraints` **solo** cuando existan claves soportadas (sin depender de APIs inexistentes); si no hay soporte, limitarse al indicador visual.
3. No eliminar el overlay ROI ni el arranque del scan loop salvo que sea necesario para corregir un bug demostrable.

**DoD**

- UX no empeora; no hay errores no capturados en consola por el tap.
- Build OK.

---

## Paso 6 — Verificación manual mínima (checklist para humano o IA con dispositivo)

**No es código obligatorio:** checklist para validar el resultado.

1. Abrir la PWA en **HTTPS** (o `localhost`), conceder cámara.
2. Probar un libro con ISBN **en contraportada** con buena luz; el código debe ocupar buena parte del marco central.
3. Confirmar en consola la **resolución real** del vídeo (logs del Paso 1).
4. Si no lee: acercar/alejar lentamente y reducir reflejos; repetir.

**DoD global del documento**

- Pasos 1–5 implementados y `frontend` compila con `npm run build`.
- Ningún cambio en backend obligatorio para este documento.
- Resumen breve al final del trabajo (lista de archivos tocados y valores por defecto de env nuevos, si los hay).

---

## Anexo — Variables de entorno sugeridas (frontend)

Definir en `frontend/.env.example` (crear o actualizar si el proyecto ya lo usa) sin commitear secretos:

```env
# Opcional: ratio del ROI (0–1), ej. 0.65
# VITE_SCAN_ROI_RATIO=0.65

# Opcional: lado largo mínimo del bitmap enviado a ZXing (px)
# VITE_SCAN_DECODE_MIN_LONG_EDGE=1024

# Si se cablean en useScanLoop (Paso 4)
# VITE_SCAN_FPS_IOS=2
# VITE_SCAN_FPS_ANDROID=4
```

La IA debe **parsear** con fallback seguro cuando falten o sean inválidas.

---

## Referencias de archivos clave

| Área            | Ruta                                      |
|-----------------|-------------------------------------------|
| Cámara          | `frontend/src/hooks/useCamera.ts`         |
| ROI / frames    | `frontend/src/hooks/useScanLoop.ts`       |
| ZXing / ISBN    | `frontend/src/hooks/useISBNReader.ts`     |
| Vista / overlay | `frontend/src/components/CameraView.tsx`  |
| Especificación  | `README_BOOK_SCANNER_GOODREADS.md`        |

Fin del documento.
