#!/usr/bin/env bash
# redactar.sh — fuente unica de la redaccion de secretos de las HERRAMIENTAS del
# repo (Task 17.3 / D12, "rastro de decisiones").
#
# QUE ES. Una lib que se SOURCEA (`. tools/lib/redactar.sh`) desde los tools que
# escriben a disco en forma legible para el lead — el rastro de decisiones
# (`tools/saikit-decision.sh`) y el blast. Define:
#
#   redactar()            $1 = texto de entrada; lo imprime por stdout con las
#                         formas de credencial reemplazadas por `[REDACTED]`.
#   saikit_secret_re      imprime (stdout) la familia de regex para ESCANEAR.
#   SAIKIT_SECRET_SCAN_RE variable de solo lectura con la MISMA regex.
#
# POR QUE UNA LIB Y NO INLINE. El hook (`hooks/summonaikit-harness.sh`) ya
# aislaba su `redact_secrets` porque corre INSTALADO, solo, en el repo consumer,
# donde `tools/` no existe. Eso funcionaba mientras la redaccion era de una
# sola superficie; con el rastro (y el blast) la redaccion pasa a ser de DOS.
# Este archivo es la fuente unica: si un tool la necesita, la SOURCEA y no
# vuelve a duplicar patrones. El hook mantiene su copia INLINE (no puede
# sourcear una lib que no lo acompaña instalado) y DEBE MATCH: quien toque la
# familia aca tiene que reflejar el mismo cambio en `redact_secrets`, y al
# reves. La maquinaria del repo lo canda: el test `tests/test_saikit_decision.sh`
# comprueba que el hook conoce las mismas formas.
#
# LAS FORMAS NUEVAS. `redact_secrets` (Task 3.5 / A5) cubria par `clave=valor`,
# credenciales de URL y los patrones originales del port. Las formas de token
# conocidas de los proveedores quedaban FUERA (medido): un token pegado en una
# explicacion del rastro viajaba en claro. Estas son las que se suman (las
# mismas que las herramientas de deteccion de secretos del repo ya reconocen):
#   ghp_       GitHub personal access token (la forma moderna de ghp_).
#   github_pat_ GitHub fine-grained personal access token.
#   gho_       GitHub OAuth access token.
#   sk-        OpenAI / Anthropic API key (sk-, sk-proj-...). Se ancla a una
#              frontera de LETRA (`(^|[^A-Za-z0-9])sk-...`): un sk- precedido
#              por una letra no se redacta (para no manglear prefijos de tarea
#              como `task-17`), pero uno precedido por guion, guion bajo, signo
#              igual o espacio SI se redacta: esas son posiciones donde arranca
#              una clave de verdad. (Sin ejemplos literales aca a proposito: la
#              regla generic-api-key de gitleaks salta con palabra-clave + algo
#              con forma de asignacion, incluso dentro de un comentario —
#              medido en este PR.)
#   AKIA      AWS access key id (AKIA + 16 chars [0-9A-Z]).
#   xox[bp]-  Slack token (xoxb- bot, xoxp- de usuario).
#
# El `sed -E` es la MISMA tecnica que ya usa el hook: POSIX Issue 8, portable
# entre GNU/BSD/busybox. La ultima regla no lleva `\` de continuacion final.

# SAIKIT_SECRET_SCAN_RE: la familia para ESCANEAR, no para reemplazar. Detecta
# el INICIO de una forma (word-prefix) sin exigir el cuerpo completo — un
# escaneo quiere ENCONTRAR la posicion, no censurar el valor. ERE con `|` de
# alternancia a proposito: grep -E y sed -E lo entienden igual en las tres
# familias de sed/grep que el repo presupone.
readonly SAIKIT_SECRET_SCAN_RE='([Tt][Oo][Kk][Ee][Nn]|[Pp][Aa][Ss][Ss][Ww][Oo][Rr][Dd])=[^[:space:]]|://[^[:space:]@/?#]*@|ghp_[A-Za-z0-9]|github_pat_[A-Za-z0-9]|gho_[A-Za-z0-9]|(^|[^A-Za-z0-9])sk-[A-Za-z0-9]|AKIA[0-9A-Z]|xox[bp]-[A-Za-z0-9]'

# Imprime la misma familia por stdout, para quien prefiera la forma funcional
# (p.ej. `grep -En "$(saikit_secret_re)"`).
saikit_secret_re() {
  printf '%s\n' "$SAIKIT_SECRET_SCAN_RE"
}

# Redacta $1 reemplazando las formas de credencial por `[REDACTED]`. Las reglas
# en el MISMO orden que el hook: primero par clave=valor (con valor
# entrecomillado o pelado), luego credenciales en URI, luego las formas de token
# conocidas. El ultimo `-e` no lleva `\` de continuacion.
redactar() {
  printf '%s\n' "$1" | LC_ALL=C sed -E \
    -e "s/([Tt][Oo][Kk][Ee][Nn]|[Pp][Aa][Ss][Ss][Ww][Oo][Rr][Dd])=('[^']*'|\"[^\"]*\"|[^[:space:]]*)/\1=[REDACTED]/g" \
    -e 's,://[^[:space:]@/?#]*@,://[REDACTED]@,g' \
    -e 's/ghp_[A-Za-z0-9_-]*/[REDACTED]/g' \
    -e 's/github_pat_[A-Za-z0-9_-]*/[REDACTED]/g' \
    -e 's/gho_[A-Za-z0-9_-]*/[REDACTED]/g' \
    -e 's/(^|[^A-Za-z0-9])(sk-[A-Za-z0-9_-]*)/\1[REDACTED]/g' \
    -e 's/AKIA[0-9A-Z]{16}/[REDACTED]/g' \
    -e 's/xox[bp]-[A-Za-z0-9_-]*/[REDACTED]/g'
}
