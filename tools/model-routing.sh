#!/usr/bin/env bash
# Task 12.4 — resolver modelo y effort desde el contrato rol -> tier.
#
# Los IDs de modelo viven SOLO en este archivo. Ni el instalador ni las
# plantillas de agents/ los nombran: un ID repetido en dos lugares es un ID
# que se actualiza en uno solo. `tests/test_model_routing.sh` lo candea.
#
# La forma sale de `scripts/model-routing.sh` de claude-code-harness 5.6.0,
# cuya politica (docs/model-routing-policy.md, adoptada 2026-06-11) decide
# rutear por ROL y declara Non-Goal inferir el tier del texto del turno. Este
# repo llego a la misma regla por su cuenta en la Task 10.1: el carril fast se
# pide explicito, no se infiere de una regex de trivialidad.
#
# DIFERENCIA DELIBERADA con el router del harness: alla las funciones de
# resolucion hacen `exit 2` adentro de una sustitucion `$( )`, lo que funciona
# porque el script corre con `set -euo pipefail`. Los scripts de ESTE repo
# corren con `set -u` y SIN `-e` (los 7 de tools/), donde ese mismo patron deja
# la variable vacia y sigue de largo -- un fallback silencioso, justo lo que
# Core Rule 2 prohibe. Aca las funciones imprimen por stdout y DEVUELVEN un
# codigo; el llamador lo chequea.
set -u

HOST=''
ROLE=''
TIER=''
FIELD=''
FORMAT='json'

decir() { printf '%s\n' "$*" >&2; }

uso() {
  cat <<'EOF'
Uso:
  tools/model-routing.sh --host claude|zcode|grok|kimi
                         (--role implementer|verifier|reviewer | --tier standard|verify|review)
                         [--field model|effort|effort-key|tier]
                         [--format json|frontmatter]

Una fila de host sin medir devuelve VACIO con exit 0: la clave se omite del
perfil y el agente hereda del padre. Host, rol o tier desconocido => exit 2.
EOF
}

# `shift 2` con el valor AUSENTE no shiftea nada y devuelve != 0. Bajo `set -u`
# sin `-e` eso no aborta: el while vuelve a procesar la misma bandera, para
# siempre. Reproducido: `--host` como ultimo argumento => bucle infinito. El
# valor se exige ANTES de shiftear.
requiere_valor() {  # $1=bandera  $2=args restantes ($#)
  if [ "$2" -lt 2 ]; then
    decir "[summonaikit] model-routing: $1 necesita un valor"
    exit 2
  fi
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --host)   requiere_valor --host "$#";   HOST="$2";   shift 2 ;;
    --host=*) HOST="${1#*=}"; shift ;;
    --role)   requiere_valor --role "$#";   ROLE="$2";   shift 2 ;;
    --role=*) ROLE="${1#*=}"; shift ;;
    --tier)   requiere_valor --tier "$#";   TIER="$2";   shift 2 ;;
    --tier=*) TIER="${1#*=}"; shift ;;
    --field)   requiere_valor --field "$#";  FIELD="$2";  shift 2 ;;
    --field=*) FIELD="${1#*=}"; shift ;;
    --format)   requiere_valor --format "$#"; FORMAT="$2"; shift 2 ;;
    --format=*) FORMAT="${1#*=}"; shift ;;
    -h|--help) uso; exit 0 ;;
    *) decir "[summonaikit] model-routing: argumento desconocido: $1"; uso >&2; exit 2 ;;
  esac
done

# Imprime el tier por stdout, devuelve 0. Rol desconocido: 1, sin imprimir.
rol_a_tier() {
  case "$1" in
    implementer) printf 'standard' ;;
    verifier)    printf 'verify' ;;
    reviewer)    printf 'review' ;;
    *) return 1 ;;
  esac
  return 0
}

# El rol se valida SIEMPRE que venga, aunque tambien venga --tier. Si la
# validacion viviera solo adentro del `if [ -z "$TIER" ]`, entonces
# `--role astronauta --tier review` saldria 0 y ademas imprimiria
# `"role":"astronauta"` en el JSON: un rol inventado acreditado por el router.
if [ -n "$ROLE" ]; then
  ROLE_TIER="$(rol_a_tier "$ROLE")" || {
    decir "[summonaikit] model-routing: rol desconocido: $ROLE"
    exit 2
  }
  [ -z "$TIER" ] && TIER="$ROLE_TIER"
fi

if [ -z "$TIER" ]; then
  decir "[summonaikit] model-routing: hace falta --role o --tier"
  exit 2
fi

# Un tier que ningun rol mapea no existe: no se define "por las dudas".
case "$TIER" in
  standard|verify|review) ;;
  *) decir "[summonaikit] model-routing: tier desconocido: $TIER"; exit 2 ;;
esac

MODEL=''
EFFORT=''
# Nombre de CLAVE de frontmatter para el effort, por host. Default 'effort'
# (claude, grok, kimi). Medido en la Task 12.1 (docs/task-12.1-medicion.md):
# el parser de zcode NUNCA destructura `effort:` -- la clave real que lee es
# `thoughtLevel:`. Escribir `effort:` en zcode seria texto muerto, aunque el
# valor en si sea correcto. Esto se fija ACA, en el emisor, y no en el
# instalador: si zcode llegara a llenar su fila algun dia, el ID de modelo y
# el nombre de clave viven en el mismo lugar (Core Rule: los IDs de modelo
# viven SOLO en este archivo -- lo mismo aplica al nombre de la clave que los
# porta). Se fija SIEMPRE por host, sin importar si la fila esta vacia hoy:
# asi `--field effort-key` es candeable aunque EFFORT todavia sea ''.
EFFORT_KEY='effort'

# --- Tablas por host ---------------------------------------------------------
# Una fila vacia NO es un error: es "todavia no medido" (Task 12.1/12.2/12.3).
# Se traduce a clave omitida, que es como zcode se comporta hoy (Task 5.6:
# "sin model:; heredan GLM del padre").
case "$HOST" in
  claude)
    # Catalogo y precios: skill claude-api, cacheado 2026-06-24.
    # review usa Opus 5 y NO Fable 5, a diferencia del harness (decision de
    # operador 2026-07-25). Fable son $10/$50 por millon contra $5/$25 de Opus
    # -- el doble en salida -- y xhigh ya es el mejor setting para trabajo de
    # codigo y agentico. Fable queda como escalada MANUAL, fuera del ruteo
    # automatico: una ruta automatica al tier mas caro es como se llega a una
    # factura que nadie decidio.
    case "$TIER" in
      standard) MODEL='claude-sonnet-5'; EFFORT='medium' ;;
      # verify: mismo modelo que standard, effort bajo. El verifier corre
      # comandos y lee salida (orquestacion) pero tambien inspecciona el diff
      # (juicio). Bajar el effort ahorra sin bajar de modelo, y evita el techo
      # de 200K de contexto del tier mas barato.
      verify)   MODEL='claude-sonnet-5'; EFFORT='low' ;;
      review)   MODEL='claude-opus-5';   EFFORT='xhigh' ;;
    esac
    ;;
  zcode)
    # Fila VACIA A PROPOSITO (medido en la Task 12.1, docs/task-12.1-medicion.md):
    # el parser SI lee model: (clave oficial), pero el catalogo real de la
    # cuenta quedo NO OBSERVADO -- los IDs glm-5.x salieron de un grep debil
    # contra el bundle, no del entitlement confirmado de la cuenta. Ademas,
    # "effort" en frontmatter no existe como tal: el parser destructura
    # thoughtLevel:, no effort: (escribir effort: seria texto muerto). Sin
    # catalogo confirmado no hay valor que poner en la celda -- Core Rule del
    # diseno ("un host cuya medicion no cierre queda con su fila vacia y
    # hereda del padre", docs/phase-12-model-routing-design.md §D3/§Medicion
    # primero). Hereda GLM del padre, igual que hoy.
    #
    # EFFORT_KEY SI se fija aunque la fila este vacia: es el nombre de clave
    # que el emisor --format frontmatter usaria si algun dia EFFORT dejara de
    # estar vacio, y el que agente_traducido() usa para descartar una linea
    # preexistente con ese nombre en la fuente (Task 12.5).
    EFFORT_KEY='thoughtLevel'
    ;;
  grok)
    # Medido en la Task 12.2 (docs/task-12.2-medicion.md, 2026-08-24): grok SI
    # honra model: y effort: por agente -- evidencia de registro interno
    # (subagents/<id>/meta.json: effective_model_id; chat_history.jsonl:
    # model_id/reasoning_effort del subagente, distintos del padre e iguales
    # al frontmatter declarado). Catalogo real de ESTA cuenta (models_cache.json,
    # 2026-08-24): grok-4.6 (default de config.toml) y grok-4.5. La medicion no
    # comparo capacidad entre los dos IDs -- solo confirmo que ambos se aplican
    # literalmente -- asi que no hay evidencia para preferir uno sobre otro por
    # tier. Se usa el mismo grok-4.6 (el default confirmado de la cuenta) en
    # los tres tiers y se varia solo el effort, mismo criterio que claude entre
    # standard/verify (D2 del diseno: mismo modelo, effort mas bajo evita
    # inventar una jerarquia de modelos no medida).
    case "$TIER" in
      standard) MODEL='grok-4.6'; EFFORT='medium' ;;
      verify)   MODEL='grok-4.6'; EFFORT='low' ;;
      review)   MODEL='grok-4.6'; EFFORT='xhigh' ;;
    esac
    ;;
  kimi)
    # Fila VACIA DEFINITIVA, no pendiente (medido en la Task 12.3): el host
    # no acepta model: ni effort: por agente. Ver tests/test_model_routing.sh.
    : ;;
  '')
    decir "[summonaikit] model-routing: hace falta --host"
    exit 2
    ;;
  *)
    decir "[summonaikit] model-routing: host desconocido: $HOST"
    exit 2
    ;;
esac

case "$FIELD" in
  '') ;;
  model)       printf '%s\n' "$MODEL";      exit 0 ;;
  effort)      printf '%s\n' "$EFFORT";     exit 0 ;;
  effort-key)  printf '%s\n' "$EFFORT_KEY"; exit 0 ;;
  tier)        printf '%s\n' "$TIER";       exit 0 ;;
  *) decir "[summonaikit] model-routing: --field desconocido: $FIELD"; exit 2 ;;
esac

case "$FORMAT" in
  json)
    printf '{"host":"%s","role":"%s","tier":"%s","model":"%s","effort":"%s"}\n' \
           "$HOST" "$ROLE" "$TIER" "$MODEL" "$EFFORT"
    ;;
  frontmatter)
    # Cero, una o dos lineas. Nunca `model:`/EFFORT_KEY: con valor vacio: eso
    # seria escribir una clave que miente en vez de omitirla. La clave del
    # effort NO es literal 'effort:' para todos los hosts: EFFORT_KEY la fija
    # por host (Task 12.1/12.5: zcode lee thoughtLevel:, nunca effort:).
    [ -n "$MODEL" ]  && printf 'model: %s\n' "$MODEL"
    [ -n "$EFFORT" ] && printf '%s: %s\n' "$EFFORT_KEY" "$EFFORT"
    ;;
  *) decir "[summonaikit] model-routing: --format desconocido: $FORMAT"; exit 2 ;;
esac
exit 0
