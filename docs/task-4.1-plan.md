# Task 4.1 — Retirar `.claude` como target del heal de quality-kit (plan revisado tras cross-review)

`[Config]` `[lane:gate]` `[tdd:required]`. Cierra la consolidación de la Phase 4.
**DoD íntegra en `Plans.md:76`:** los 3 perfiles restantes se siguen parcheando; la
batería de `quality-kit` sigue verde con la cobertura de `.codex` verificada por
separado; `.claude` ya no aparece como target.

## Cross-review del PLAN con codex (1 ronda, 2026-08-12) — 4 hallazgos, los 4 aceptados

Tope del quality-kit: máx 1 ronda, 2da sólo con severidad alta. Esta ronda **no halló
alta** (2 medias + 2 bajas) → **no hay segunda ronda**; los residuales se declaran acá.

1. **[media] ACEPTADO+verificado** — Mi claim "3o/3p sin cambio" es **falso para 3p**.
   `run-tests.ps1:1810` asserta `($rRegI.Stdout -notmatch 'saltado, lo maneja')` para
   probar que `-Quiet` silencia el skip. Pero `$regHomeI` se arma con
   `New-HealHomeWithSettings` → crea `.claude\hooks` **sin marcador**, y tras 4.1 `.claude`
   ni se itera y ningún target restante porta marcador → la línea `saltado, lo maneja`
   **jamás aparece** → el `-notmatch` pasa **vacuo**. **Fix:** meter un `.codex` marcado
   en el fake home de `$regHomeI` (el skip se detecta de verdad y el `-notmatch` prueba
   que `-Quiet` lo silencia). Verificado leyendo `run-tests.ps1:1807-1810`.
2. **[media] ACEPTADO** — Orden TDD vs orden de commit en B1. El rojo de B1
   ("`.claude` ∉ `$targets`") debe medirse contra el quality-kit **actual** (rojo), no
   tras modificarlo. El "quality-kit primero" aplica al **commit** (el e2e lee el heal
   real), no a la medición TDD.
3. **[baja] ACEPTADO** — Plans.md: la columna Status lleva el commit de
   **summonaikit-claude** (convención, ej. 3.8 `[87247a0]`); el SHA de quality-kit va
   **en la nota**. No al revés.
4. **[baja] ACEPTADO** — "no se area" → "no se stagea a git" (claridad).

## Por qué ahora (premisa verificada, no supuesta)

El hook `.claude` **vivo** ya es propiedad de este repo: la línea 2 del archivo
instalado en `~/.claude/hooks/summonaikit-harness.sh` lleva
`# SAIKIT-CLAUDE-OWNED summonaikit-claude 1.0.0` (verificado leyendo el archivo), y
`summonaikit-claude` lo instala **entero** desde su propia fuente con los dos parches
adentro (Task 2.1 byte-a-byte + Task 2.4 install). Hoy el heal de `quality-kit`
(`saikit-gate-heal.ps1`) todavía **itera** `.claude` como target y lo **saltea** por el
marcador de propiedad (costura Task 2.3, "días en verde" saltándolo).

Retirar `.claude` del vector `$targets` vuelve **explícita** la no-escritura y elimina
la superficie de doble escritor en cada `SessionStart`. Es **consolidación, no cambio de
comportamiento**: el `.claude` vivo queda exactamente igual (no se toca), sólo que deja
de aparecer como target y de reportar `saltado-propiedad` en cada arranque sano.

## Qué cambia y qué NO

**NO se borra código del parche** (lo exige el renglón de la DoD y el diseño):
- `.codex` tiene rama propia (`-harness-lite`, ancla RN-G) → el código del parche queda.
- `.cursor`/`.agents` siguen necesitando los dos parches (sentinel + review-notice) → quedan.
- El **skip por marcador** queda como **red de seguridad**, cubierto por tests aunque en
  producción ningún target restante porte el marcador.
- `Invoke-RegistrationCheck` (Task 0.3/2.3) **no se toca**: verifica el **registro** del
  hook en `.claude\settings.json`, que es independiente de si el heal **parchea** el
  archivo del hook.

**Cambio de código mínimo:** una sola línea en `saikit-gate-heal.ps1`.

---

## A) Repo `C:\Users\ehven\quality-kit\` — el cambio de verdad

### A1. `saikit-gate-heal.ps1`
- **Línea 808** — `$targets = @('.claude', '.codex', '.cursor', '.agents')` →
  `$targets = @('.codex', '.cursor', '.agents')`. (Más el comentario que la rodea.)
- **Header "CONVIVENCIA CON summonaikit-claude (su Task 2.3)" (lín. 52-76)** — reescribir:
  `.claude` **ya no es target** (lo owné este repo, que instala el archivo entero con los
  dos parches adentro); el skip por marcador queda como safety-net para los otros 3
  perfiles (si alguno, por copia manual, llegara a portar el marcador).
- **Bloque "el salto es el estado NORMAL de cada arranque" (lín. 898-906)** — corregir:
  tras la 4.1 el skip **no** es el estado normal (`.claude` ni se itera; ningún target
  restante porta el marcador). El mensaje `$skippedOwned` (lín. 909) se conserva: sigue
  siendo correcto si algún día se dispara.

### A2. `tests/run-tests.ps1` — migrar fixtures `.claude` → targets restantes
La shape **genérica** (`.claude`/`.cursor`/`.agents`) migra a **`.cursor`** (byte-idéntica
a `.agents` — ambos 40333 bytes verificados; es el "otro host" natural). `.codex` conserva
su cobertura dedicada (shape distinta + `-harness-lite`). Los grupos **3o/3p (registro) NO
cambian**: leen `.claude\settings.json` por diseño y no assertan parche sobre `.claude`.

| Grupo | refs `.claude` | Migración |
|-------|----------------|-----------|
| **3k** (maquinaria genérica) | 7 | path `.claude`→`.cursor` + comment lín. 934 |
| **3l** (independencia de los 2 parches) | 6 | path `.claude`→`.cursor` |
| **3m** (e2e real-shape) | ~21 (muchos comments) | half genérica `.claude`→`.cursor` (`$FrozenClaudeHook` puesto en `.cursor\hooks`); pasada **live** `~/.claude`→`~/.cursor`; half `.codex` intacta |
| **3n** (skip por marcador) | 6 + comments | marcador sobre **`.codex`** (target restante); "otro perfil sin marcador" = `.cursor`; asserta skip reportado sobre `.codex` y `.cursor` parcheado |
| **3o** (registro: cableado a-f) | — | **sin cambio** (registration = `.claude`-profile por diseño) |
| **3p** (registro: silence/timeout) | 1 (lín. 1810) | **cambio chico** (hallazgo 1): `$regHomeI` suma un `.codex\hooks` marcado, así el `-notmatch 'saltado, lo maneja'` bajo `-Quiet` deja de ser vacuo y prueba de verdad que `-Quiet` silencia el skip |

### A3. NUEVO test rojo (DoD #3: "`.claude` ya no aparece como target")
Grupo nuevo (o anexo a 3n): un home con hooks parcheables en los **4** perfiles; asserta
que `.claude` queda **byte-igual** (no parcheado) y `.codex`/`.cursor`/`.agents` **sí**
parcheados en la misma corrida. **Hoy falla** (`.claude` sigue siendo target). Es la prueba
que "habría atrapado" el arreglo.

### TDD rojo/verde (quality-kit)
- **ROJO:** A3 falla hoy (`.claude` es target, se parchea).
- **VERDE:** A1 (sacar `.claude` de `$targets`) + A2 (migrar fixtures). El driver de la
  batería no hace mutación (es PowerShell, no el hook bash); aquí `[tdd:required]`
  significa "el cambio trae la prueba que lo habría atrapado" = A3.
- **Baseline:** correr `tests/run-tests.ps1` **antes** (verde, anotar #asertos) y
  **después** (verde, asertos ≥ baseline). La batería tarda varios minutos (levanta
  powershell+bash+python por caso); se corre 2 veces.

---

## B) Repo `C:\dev\summonaikit-claude\` — tracking + costura

### B1. `tests/test_quality_kit_skip.sh` (Task 2.3 — mirar la costura desde este lado)
- **Parte 1** (lín. 52-57, el heal nombra el prefijo del marcador): **se mantiene** — la
  costura del skip sigue vigente para los targets restantes.
- **Parte 2** (e2e, lín. 60-100): tras la 4.1 el heal **no itera** `.claude`, así que
  `'saltado'` ya no aparece para `.claude`. Cambios:
  - **(a)** mantengo el assert byte-identical (sigue cierto, ahora por no-ser-target).
  - **(b)** **NUEVO:** asserto que `.claude` **no** está en `$targets` del heal (grep del
    renglón `targets = @(` → no contiene `.claude`). Es el DoD #3 desde este lado.
  - **(c)** retiro el `grep -qi 'saltado'` para `.claude` (ya no aplica) + comment honesto
    de que `.claude` no se toca **por construcción** (no es target), no por skip.

**TDD de B1 (hallazgo 2):** el **rojo** se mide contra el quality-kit **actual** (sin
modificar): escribo (b) primero y corro → `.claude` SÍ está en `$targets` hoy → falla.
Luego modifico quality-kit (A1) → (b) pasa → **verde**. El "quality-kit primero" aplica al
**commit** (el e2e lee el heal real), no a la medición TDD.

### B2. `docs/task-4.1-plan.md`
Este documento (se completa con los hallazgos de la cross-review tras la review).

### B3. `Plans.md`
Línea 76 → `cc:完了 [<sha-summonaikit-claude>]` (hallazgo 3: la columna Status lleva el
commit de ESTE repo, convención) + nota de cierre con el **SHA de quality-kit** identificado
adentro (qué cambió, qué quedó, baseline `.claude` vivo idéntico, DoD verificada, límites
declarados).

### Validación (summonaikit-claude)
- Rojo/verde de B1 sobre `test_quality_kit_skip.sh` suelto en su sandbox. **Depende de
  quality-kit primero** (el e2e lee el heal real).
- Gate final: `tests/run.sh` una sola vez (≈18 min en Git Bash). Esta task **no toca la
  fuente del hook**, así que la baseline dorada no se mueve.

---

## Límites declarados (no cerrados por esta task)
1. **Skip por marcador dead-in-prod**: tras 4.1, ningún target restante porta el marcador
   → `$skippedOwned` siempre vacío en producción. Se conserva por insurance + cobertura de
   tests (3n migrado). Declarado, no borrado (lo pide el renglón de la DoD).
2. **`.claude` ya no reporta `saltado`**: su no-escritura es silenciosa (no iterada), el
   efecto de consolidación buscado.
3. **`Invoke-RegistrationCheck`** sigue atado a `.claude\settings.json` (Claude-only por
   diseño); no es un target de parche y no se migra.
4. El **gate sigue advisory** (no cambia en esta task).

## Orden de commits (forzado por la dependencia)
1. **quality-kit:** `saikit-gate-heal.ps1` + `tests/run-tests.ps1` (1 commit). **Ojo:** hay
   un `M cross-review.ps1` colgado en el árbol, **no relacionado** (resto de la Task 3.3) —
   **no se stagea a git** (hallazgo 4); agrego sólo los archivos que toco.
2. **summonaikit-claude:** `tests/test_quality_kit_skip.sh` + `docs/task-4.1-plan.md` +
   `Plans.md` (1 commit).
   Orden forzado: el e2e de `test_quality_kit_skip.sh` lee el heal real de quality-kit.

## Candados / validación final
- `pre-commit run --all-files` en cada repo que tenga candados (regla de hierro: jamás
  `--no-verify`).
- quality-kit: `tests/run-tests.ps1` verde (antes y después).
- summonaikit-claude: `tests/run.sh` verde (gate final, una vez).

## Cross-review del CÓDIGO
Regla nueva del repo: **sólo si el operador la pide**. Se ofrece al cerrar; no se auto-corre.
