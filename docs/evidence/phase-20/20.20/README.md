# 20.20 — evidencia (corepack/pnpm sin packageManager)

Identidad: `run-identity.txt`. Drift declarado: el runbook cita hook 37e55640 (4345 lineas)
y pin e0f7a25; el checkout real de esta rama es 703f276 y el hook real el shim de
pre-commit.com (20 lineas, sha256 en identidad). La medicion corre contra los reales.

## Defecto y fix, medidos (Node 20.19.5 + corepack 0.33.0 bajo $TMPDIR)

Fixture hermetico sin campo packageManager (package.json + pnpm-lock.yaml v9),
HOME/COREPACK_HOME aislados por corrida.

| Par | Log | Salida |
|---|---|---|
| Rojo: corepack enable + pnpm install --frozen-lockfile | rojo-defecto.log | rc=1, `Cannot find module .../v1/pnpm/12.3.4/bin/pnpm.cjs` |
| Verde: corepack prepare pnpm@10.34.5 --activate antes de install+test | verde-pin.log | install rc=0 y pnpm test rc=0 |
| Frontera pnpm 11.0.0 | frontera-11.log | rc=1 (corepack 0.33.0 no lo corre) |
| Frontera pnpm 9.15.9 | frontera-9.log | rc=0 |
| Sin red (proxy muerto) | sin-red.log | `Error when performing the request to https://registry.npmjs.org/...` |

## Distinciones (DoD de la fila)

- Defecto: la descarga de pnpm 12.3.4 FUNCIONA (red ok); falla el paquete (sin bin/pnpm.cjs).
- Falta de red: el error nombra la URL del registro — firma distinta del defecto.
- Interaccion necesaria: ninguna. Sin TTY el shim de corepack fuerza
  COREPACK_ENABLE_DOWNLOAD_PROMPT=0; estas corridas fueron no interactivas y sin prompt.

## Bateria (test_ci_minimo.sh, log completo a archivo, jamas por pipe)

| Par | Log | Salida |
|---|---|---|
| Rojo: generador sin pin (pre-fix) | bateria-rojo-sin-pin.log | 4 casos ROJO: pnpm_lock_emite_pnpm, pnpm_pin_concreto_en_rango_corepack20, pnpm_quitar_pin_muta_a_rojo, pnpm_toolchain_hermetica_sin_packagemanager (este reproduce el defecto vivo DENTRO del sandbox del test). Ademas 1 rojo ambiental preexistente ajeno a la fila: `timeout` ausente en PATH restringido de macOS (caso flag_ci_minimo_exige_valor; en CI ubuntu y con PATH de homebrew pasa) |
| Verde: generador con pin | bateria-verde.log | exit 0, 40 casos ok, 21 mutaciones atrapadas, 0 skips (PATH con /opt/homebrew/bin) |
| Mutacion discriminante | bateria-verde.log | caso pnpm_quitar_pin_muta_a_rojo: sed quita el pin del generador; la asercion de pin lo atrapa. La guarda de rango (version concreta, major <= 10) sigue discriminando aunque el corepack local corra pnpm 12 |

Comandos viejos no declarados actuales por analogia: toda la medicion de esta fila
se corrio hoy contra v20.19.5/corepack 0.33.0 descargado; nada se infiere de corridas previas.
