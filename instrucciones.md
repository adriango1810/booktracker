# Instrucciones para IA basica (modo estricto)

Usa estas instrucciones para pedirle a una IA basica que implemente el proyecto del archivo `README_BOOK_SCANNER_GOODREADS.md` sin desviarse.

---

## Prompt inicial (copiar y pegar)

```text
Quiero que implementes este proyecto siguiendo EXACTAMENTE el archivo README_BOOK_SCANNER_GOODREADS.md.

Reglas obligatorias:
1) Empieza por el Paso 1.
2) No avances al siguiente paso sin cumplir el DoD del paso actual.
3) En cada paso debes:
   - implementar codigo,
   - ejecutar validaciones/comandos necesarios,
   - reportar checklist DoD con estado OK/NO.
4) No cambies stack ni arquitectura.
5) Si algo no esta claro, elige la opcion mas conservadora y explicala en 2-3 lineas.
6) No simplifiques requisitos obligatorios.
7) No marques un paso como completado sin evidencia.

Formato de respuesta obligatorio en cada paso:
- Plan breve (maximo 5 bullets)
- Cambios realizados
- Comandos ejecutados
- Resultado de validaciones
- Checklist DoD (OK/NO)
- Siguiente accion recomendada

Empieza ahora por el Paso 1.
```

---

## Prompt de control para cada paso

Cuando termine un paso, usar:

```text
Continua con el siguiente paso del README.
Mantiene las mismas reglas estrictas:
- No avanzar sin DoD completo
- Mostrar evidencia tecnica
- Reportar checklist DoD OK/NO
```

---

## Prompt de bloqueo (si la IA se salta algo)

Usar cuando la IA quiera avanzar sin cumplir DoD:

```text
Alto. No avances de paso.
Primero corrige todo lo pendiente del DoD actual.
Necesito evidencia concreta (comandos y resultados) antes de continuar.
```

---

## Prompt anti-invencion (si empieza a improvisar)

```text
No inventes requisitos ni cambies arquitectura.
Sigue literalmente README_BOOK_SCANNER_GOODREADS.md.
Si detectas ambiguedad, aplica decision conservadora y documentala.
```

---

## Prompt para pedir solo verificaciones

```text
No hagas cambios nuevos.
Dame solo:
1) comandos de validacion del paso actual,
2) resultado esperado por comando,
3) criterio objetivo para marcar cada punto del DoD como OK.
```

---

## Prompt para reintentar un paso fallido

```text
Repite el paso actual desde cero, sin avanzar.
Objetivo: cumplir el DoD al 100%.
Primero lista que fallo, luego aplica correcciones minimas, valida y reporta checklist final OK/NO.
```

---

## Prompt final (cierre de proyecto)

```text
Antes de cerrar:
1) Revisa que todos los pasos del README esten completos.
2) Entrega checklist final por paso (OK/NO).
3) Lista riesgos abiertos y mitigaciones.
4) Dame comandos finales para probar en iPhone y Android.
```

---

## Recomendacion de uso

- Trabaja en iteraciones cortas (un paso por mensaje).
- No permitas respuestas largas sin evidencias.
- Si la IA no muestra comandos ni validaciones, considera el paso incompleto.
