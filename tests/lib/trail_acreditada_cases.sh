#!/usr/bin/env bash
# 21.4 — rastro y blast ligados a la raiz acreditada de la task.
# Consumen test_trail_gate.sh (via CASOS_G8), test_gate_behavior.sh y
# test_gate_mutations.sh. La raiz citada es la unidad (raiz absoluta + sha
# del commit/arbol revisado); sin sha no hay acreditacion.

# 21.4r2: la acreditacion exige el veredicto sellado <sha>.json bajo la raiz
# (anclaje al juicio de la sesion); $2=1 lo siembra, $2=0 arma el repo ajeno
# autoconsistente SIN juicio.
_repo_semillar() {
  rm -rf "$LAB/$1"
  mkdir -p "$LAB/$1/.saikit/decisiones" "$LAB/$1/.saikit/findings"
  printf 'cuando|etapa|decision|por_que|evidencia|resultado\n2026-09-13T00:00:00Z|tarea|hecho|porque|evidencia|ok %s %s %s\n' "$1" "$$" "$(date +%s%N)" > "$LAB/$1/.saikit/decisiones/21.4.tsv"
  printf '{"task":"21.4","wt":"%s"}\n' "$1" > "$LAB/$1/.saikit/findings/blast-21.4.json"
  git -C "$LAB/$1" init -q -b main 2>/dev/null || git -C "$LAB/$1" init -q
  git -C "$LAB/$1" config user.email t21@invalid
  git -C "$LAB/$1" config user.name t21
  git -C "$LAB/$1" add -A
  git -C "$LAB/$1" commit -qm semilla
  _h="$(git -C "$LAB/$1" rev-parse HEAD)"
  if [ "$2" = "1" ]; then
    mkdir -p "$LAB/$1/.saikit/veredictos"
    printf '{"sha":"%s"}\n' "$_h" > "$LAB/$1/.saikit/veredictos/$_h.json"
  fi
  printf '%s\n' "$_h"
}

_wt_nuevo() { _repo_semillar "$1" 1; }
_repo_sin_veredicto() { _repo_semillar "$1" 0; }

_recibo_raiz() {
  _recibo_close "trail at .saikit/decisiones/21.4.tsv ; blast at .saikit/findings/blast-21.4.json ; raiz: $1 ; sha: $2 ; code after reviewer: no."
}

caso_g8_full_raiz_acreditada_otro_cwd_cierra() {
  limpiar_saikit
  _sembrar_turno_completo
  _sha="$(_wt_nuevo wt-tarea)"
  lab_run stop claude "$(lab_payload_stop "$(_recibo_raiz "$LAB/wt-tarea" "$_sha")")"
  _afirma_cierre "raiz acreditada con cwd de otra sesion"
}

caso_g8_full_raiz_untracked_bloquea() {
  limpiar_saikit
  _sembrar_turno_completo
  rm -rf "$LAB/wt-tarea"
  mkdir -p "$LAB/wt-tarea/.saikit/decisiones" "$LAB/wt-tarea/.saikit/findings"
  : > "$LAB/wt-tarea/.saikit/decisiones/21.4.tsv"
  : > "$LAB/wt-tarea/.saikit/findings/blast-21.4.json"
  git -C "$LAB/wt-tarea" init -q -b main 2>/dev/null || git -C "$LAB/wt-tarea" init -q
  git -C "$LAB/wt-tarea" config user.email t21@invalid
  git -C "$LAB/wt-tarea" config user.name t21
  git -C "$LAB/wt-tarea" commit -qm vacio --allow-empty >/dev/null
  _sha="$(git -C "$LAB/wt-tarea" rev-parse HEAD)"
  lab_run stop claude "$(lab_payload_stop "$(_recibo_raiz "$LAB/wt-tarea" "$_sha")")"
  _afirma_bloqueo_trail "artefactos sin versionar"
}

caso_g8_full_raiz_dirty_bloquea() {
  limpiar_saikit
  _sembrar_turno_completo
  _sha="$(_wt_nuevo wt-tarea)"
  printf 'cambio sucio\n' >> "$LAB/wt-tarea/.saikit/decisiones/21.4.tsv"
  lab_run stop claude "$(lab_payload_stop "$(_recibo_raiz "$LAB/wt-tarea" "$_sha")")"
  _afirma_bloqueo_trail "artefacto modificado tras el commit"
}

caso_g8_full_raiz_post_review_bloquea() {
  limpiar_saikit
  _sembrar_turno_completo
  _sha="$(_wt_nuevo wt-tarea)"
  printf 'escrito despues\n' >> "$LAB/wt-tarea/.saikit/decisiones/21.4.tsv"
  git -C "$LAB/wt-tarea" commit -qam despues >/dev/null
  lab_run stop claude "$(lab_payload_stop "$(_recibo_raiz "$LAB/wt-tarea" "$_sha")")"
  _afirma_bloqueo_trail "HEAD avanzo sobre el sha revisado"
}

caso_g8_full_raiz_ajena_bloquea() {
  limpiar_saikit
  _sembrar_turno_completo
  _sha_tarea="$(_wt_nuevo wt-tarea)"
  _sha_alien="$(_wt_nuevo wt-ajeno)"
  lab_run stop claude "$(lab_payload_stop "$(_recibo_raiz "$LAB/wt-ajeno" "$_sha_tarea")")"
  _afirma_bloqueo_trail "checkout ajeno con otro HEAD"
}

caso_g8_full_raiz_otro_head_bloquea() {
  limpiar_saikit
  _sembrar_turno_completo
  _sha_tarea="$(_wt_nuevo wt-tarea)"
  _sha_otra="$(_wt_nuevo wt-otra)"
  lab_run stop claude "$(lab_payload_stop "$(_recibo_raiz "$LAB/wt-otra" "$_sha_tarea")")"
  _afirma_bloqueo_trail "otro worktree en otro HEAD"
}

caso_g8_full_raiz_prefijo_bloquea() {
  limpiar_saikit
  _sembrar_turno_completo
  _sha="$(_wt_nuevo wt-tarea)"
  rm -rf "$LAB/wt-tarea-evil"
  mkdir -p "$LAB/wt-tarea-evil/.saikit/decisiones" "$LAB/wt-tarea-evil/.saikit/findings"
  : > "$LAB/wt-tarea-evil/.saikit/decisiones/21.4.tsv"
  : > "$LAB/wt-tarea-evil/.saikit/findings/blast-21.4.json"
  lab_run stop claude "$(lab_payload_stop "$(_recibo_raiz "$LAB/wt-tarea-evil" "$_sha")")"
  _afirma_bloqueo_trail "prefijo parecido sin repo"
}

caso_g8_full_raiz_puntos_cierra() {
  limpiar_saikit
  _sembrar_turno_completo
  _sha="$(_wt_nuevo wt-tarea)"
  lab_run stop claude "$(lab_payload_stop "$(_recibo_raiz "$LAB/proyecto/../wt-tarea" "$_sha")")"
  _afirma_cierre "raiz con .. que canoniza a la acreditada"
}

caso_g8_full_raiz_symlink_bloquea() {
  limpiar_saikit
  _sembrar_turno_completo
  _sha="$(_wt_nuevo wt-tarea)"
  mkdir -p "$LAB/fuera"
  cp "$LAB/wt-tarea/.saikit/decisiones/21.4.tsv" "$LAB/fuera/x.tsv"
  rm "$LAB/wt-tarea/.saikit/decisiones/21.4.tsv"
  ln -s "$LAB/fuera/x.tsv" "$LAB/wt-tarea/.saikit/decisiones/21.4.tsv"
  git -C "$LAB/wt-tarea" commit -qam enlace >/dev/null
  _sha2="$(git -C "$LAB/wt-tarea" rev-parse HEAD)"
  lab_run stop claude "$(lab_payload_stop "$(_recibo_raiz "$LAB/wt-tarea" "$_sha2")")"
  _afirma_bloqueo_trail "artefacto versionado como enlace afuera"
}

caso_g8_full_raiz_sin_sha_bloquea() {
  limpiar_saikit
  _sembrar_turno_completo
  _sha="$(_wt_nuevo wt-tarea)"
  lab_run stop claude "$(lab_payload_stop "$(_recibo_close 'trail at .saikit/decisiones/21.4.tsv ; blast at .saikit/findings/blast-21.4.json ; raiz: '"$LAB/wt-tarea"' ; code after reviewer: no.')")"
  _afirma_bloqueo_trail "raiz sin sha no acredita"
}

caso_g8_full_sha_sin_raiz_legacy_cierra() {
  limpiar_saikit
  _sembrar_turno_completo
  plantar_trail x
  lab_run stop claude "$(lab_payload_stop "$(_recibo_close 'trail at .saikit/decisiones/x.tsv ; blast at .saikit/findings/blast-x.json ; sha: 0000000000000000000000000000000000000000 ; code after reviewer: no.')")"
  _afirma_cierre "sha sin raiz se ignora (legacy intacto)"
}

caso_g8_full_raiz_ignorada_bloquea() {
  limpiar_saikit
  _sembrar_turno_completo
  _sha="$(_wt_nuevo wt-tarea)"
  printf '.saikit/decisiones/21.4.tsv\n.saikit/findings/blast-21.4.json\n' > "$LAB/wt-tarea/.gitignore"
  git -C "$LAB/wt-tarea" rm -q --cached .saikit/decisiones/21.4.tsv .saikit/findings/blast-21.4.json
  git -C "$LAB/wt-tarea" add .gitignore
  git -C "$LAB/wt-tarea" commit -qm ignora >/dev/null
  _sha2="$(git -C "$LAB/wt-tarea" rev-parse HEAD)"
  lab_run stop claude "$(lab_payload_stop "$(_recibo_raiz "$LAB/wt-tarea" "$_sha2")")"
  _afirma_bloqueo_trail "artefactos ignorados no estan en el arbol"
}

# 21.4r2 (review externa r1 #1): assume-unchanged esconde el cambio a status,
# pero el archivo en disco ya no es el blob del arbol citado.
caso_g8_full_raiz_assume_unchanged_bloquea() {
  limpiar_saikit
  _sembrar_turno_completo
  _sha="$(_wt_nuevo wt-tarea)"
  git -C "$LAB/wt-tarea" update-index --assume-unchanged .saikit/decisiones/21.4.tsv
  printf 'contenido fabricado %s %s\n' "$$" "$(date +%s%N)" > "$LAB/wt-tarea/.saikit/decisiones/21.4.tsv"
  lab_run stop claude "$(lab_payload_stop "$(_recibo_raiz "$LAB/wt-tarea" "$_sha")")"
  _afirma_bloqueo_trail "assume-unchanged esconde el cambio pero el disco no es el arbol"
}

# 21.4r2 (review externa r1 #1): `git replace` del blob fabrica el contenido
# y deja status/HEAD limpios; solo la comparacion fisica lo ve.
caso_g8_full_raiz_replace_blob_bloquea() {
  limpiar_saikit
  _sembrar_turno_completo
  _sha="$(_wt_nuevo wt-tarea)"
  _tsv="$LAB/wt-tarea/.saikit/decisiones/21.4.tsv"
  _real="$(git -C "$LAB/wt-tarea" rev-parse "$_sha:.saikit/decisiones/21.4.tsv")"
  printf 'fabricado para replace %s %s\n' "$$" "$(date +%s%N)" > "$_tsv"
  _falso="$(git -C "$LAB/wt-tarea" hash-object -w -- "$_tsv")"
  git -C "$LAB/wt-tarea" replace --force -- "$_real" "$_falso"
  lab_run stop claude "$(lab_payload_stop "$(_recibo_raiz "$LAB/wt-tarea" "$_sha")")"
  _afirma_bloqueo_trail "git replace fabrica el contenido con status limpio"
}

# 21.4r2 (review externa r1 #2): repo ajeno autoconsistente — raiz y su propio
# HEAD correctos, artefactos versionados — pero sin veredicto sellado: no hay
# juicio de sesion que ancle el sha.
caso_g8_full_raiz_autoconsistente_sin_veredicto_bloquea() {
  limpiar_saikit
  _sembrar_turno_completo
  _sha="$(_repo_sin_veredicto wt-ajeno-auto)"
  lab_run stop claude "$(lab_payload_stop "$(_recibo_raiz "$LAB/wt-ajeno-auto" "$_sha")")"
  _afirma_bloqueo_trail "repo ajeno autoconsistente sin veredicto sellado"
}

CASOS_G8="$CASOS_G8 caso_g8_full_raiz_acreditada_otro_cwd_cierra caso_g8_full_raiz_untracked_bloquea caso_g8_full_raiz_dirty_bloquea caso_g8_full_raiz_post_review_bloquea caso_g8_full_raiz_ajena_bloquea caso_g8_full_raiz_otro_head_bloquea caso_g8_full_raiz_prefijo_bloquea caso_g8_full_raiz_puntos_cierra caso_g8_full_raiz_symlink_bloquea caso_g8_full_raiz_ignorada_bloquea caso_g8_full_raiz_sin_sha_bloquea caso_g8_full_sha_sin_raiz_legacy_cierra caso_g8_full_raiz_assume_unchanged_bloquea caso_g8_full_raiz_replace_blob_bloquea caso_g8_full_raiz_autoconsistente_sin_veredicto_bloquea"
