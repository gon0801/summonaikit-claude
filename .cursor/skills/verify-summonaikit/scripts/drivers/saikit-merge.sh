#!/usr/bin/env bash
# saikit-merge driver — real tools/saikit-merge.sh on local Git + strict fake gh.
# Mode is always simulated. Unexpected gh forms fail closed.
set -euo pipefail
driver_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
skill_root="$(cd "$driver_dir/../.." && pwd)"
# shellcheck source=../lib/runtime.sh
. "$skill_root/scripts/lib/runtime.sh"
# shellcheck source=../lib/driver.sh
. "$skill_root/scripts/lib/driver.sh"

: "${VERIFY_HOME:?}" "${VERIFY_REPO:?}" "${VERIFY_TMPDIR:?}"
: "${SAIKIT_FM_ATTEMPT_DIR:?}"

MERGE="$VERIFY_REPO/tools/saikit-merge.sh"
SB="$VERIFY_TMPDIR/saikit-merge-sb"
SHA=""
MC=""
RHEAD=""
WORK=""

gitr() {
  git -C "$WORK" \
    -c user.email='op@example.com' -c user.name='op' \
    -c commit.gpgsign=false \
    "$@"
}

install_fake_gh() {
  mkdir -p "$SB/bin" "$SB/ghfix"
  cat > "$SB/bin/gh" <<'GHEOF'
#!/usr/bin/env bash
# gh falso estricto: solo las formas que usa tools/saikit-merge.sh.
# Cualquier otra forma falla y se nombra. Argv queda en SAIKIT_GH_LOG.
set -u
[ -n "${SAIKIT_GH_LOG:-}" ] && printf 'gh %s\n' "$*" >> "$SAIKIT_GH_LOG"
fix="${SAIKIT_GH_FIX:?}"
case "$1 $2" in
  "repo view") cat "$fix/repo.json"; exit 0 ;;
  "api user")  cat "$fix/user.json"; exit 0 ;;
  "run list")  cat "$fix/runs.json"; exit 0 ;;
  "pr view")
    case "$*" in
      *mergeCommit*) cat "$fix/pr-merge.json" ;;
      *) cat "$fix/pr.json" ;;
    esac
    exit 0 ;;
  "pr merge")
    if [ -f "$fix/merge-fail" ]; then cat "$fix/merge-fail"; exit 1; fi
    expected_pr="$(cat "$fix/expected-pr" 2>/dev/null)" || exit 1
    expected_sha="$(cat "$fix/expected-sha" 2>/dev/null)" || exit 1
    if [ "$#" -eq 8 ] \
      && [ "$1" = pr ] && [ "$2" = merge ] \
      && [ "$3" = "$expected_pr" ] \
      && [ "$4" = --squash ] \
      && [ "$5" = --match-head-commit ] \
      && [ "$6" = "$expected_sha" ] \
      && [ "$7" = --body ] \
      && [ "$8" = "Saikit-Merge: $expected_sha" ]; then
      exit 0
    fi
    printf 'gh-falso: forma no soportada: %s\n' "$*" >&2
    exit 1 ;;
esac
printf 'gh-falso: forma no soportada: %s\n' "$*" >&2
exit 1
GHEOF
  chmod +x "$SB/bin/gh"
}

refix() {
  SHA="$(gitr rev-parse HEAD)"
  printf '{"nameWithOwner":"op/sandbox"}' > "$SB/ghfix/repo.json"
  printf '{"login":"op"}' > "$SB/ghfix/user.json"
  printf '{"number":7,"baseRefName":"master","headRefOid":"%s","author":{"login":"op"},"mergeable":"MERGEABLE"}' \
    "$SHA" > "$SB/ghfix/pr.json"
  printf '7\n' > "$SB/ghfix/expected-pr"
  printf '%s\n' "$SHA" > "$SB/ghfix/expected-sha"
  printf '{"mergeCommit":{"oid":"f000000000000000000000000000000000000000"}}' \
    > "$SB/ghfix/pr-merge.json"
  printf '[{"event":"pull_request","status":"completed","conclusion":"success","workflow":"ci"}]' \
    > "$SB/ghfix/runs.json"

  mkdir -p "$WORK/.saikit/veredictos"
  printf '{"sha":"%s","pr":7,"verifier":"PASS","verify_app":{"resultado":"PASS","comando":"bash verify/app.sh"},"blast":{"nivel":4,"hecho":"el drive de la app corre","comando":"bash tests/run.sh"},"adversary":"n/a","reviewer":"clean","decisiones":".saikit/decisiones/18.4.tsv"}' \
    "$SHA" > "$WORK/.saikit/veredictos/$SHA.json"

  local key sd
  rm -rf "$SB/estado"
  key="$(printf '%s' "$(cd "$WORK" && pwd -P)" | cksum | cut -d' ' -f 1)"
  sd="$SB/estado/claude/$key/sess1"
  mkdir -p "$sd"
  {
    printf 'task_hash=h196\n'
    printf 'agents_seen=implementer,verifier,reviewer\n'
    printf 'lane=full\n'
    printf 'veredicto_sha256=%s\n' "$(sha256sum "$WORK/.saikit/veredictos/$SHA.json" | cut -d' ' -f 1)"
  } > "$sd/harness-state.env"
  printf 'prompt task started: h196\nverified: bash tests/run.sh\nagent: reviewer\n' \
    > "$sd/harness-evidence.log"
}

sb_reset() {
  rm -rf "$SB"
  mkdir -p "$SB"
  git init --bare -q "$SB/origin.git"
  git clone -q "$SB/origin.git" "$SB/work" 2>/dev/null || true
  WORK="$SB/work"
  gitr symbolic-ref HEAD refs/heads/master
  gitr config user.email op@example.com
  gitr config user.name op
  gitr config "url.$SB/origin.git.insteadOf" "https://github.com/op/sandbox.git"
  gitr remote set-url origin "https://github.com/op/sandbox.git"

  mkdir -p "$WORK/.saikit"
  printf '{"merge":true,"merge_despliega":"no","salud_url":null,"revert_si_rojo":true,"rama":"master","sin_verify_app":false,"telegram":false}\n' \
    > "$WORK/.saikit/autopilot.json"
  gitr add .saikit/autopilot.json
  printf 'app v1\n' > "$WORK/app.sh"
  gitr add app.sh
  gitr commit -qm "chore: base"
  gitr push -q origin master

  gitr checkout -qb feat/task
  printf 'app v2\n' >> "$WORK/app.sh"
  gitr commit -qam "feat: task"
  gitr push -q origin feat/task

  install_fake_gh
  : > "$SB/gh.log"
  refix
}

avanzar_base() {
  gitr checkout -q master
  printf 'app base nueva\n' >> "$WORK/app.sh"
  gitr commit -qam "chore: base avanza"
  gitr push -q origin master
  gitr checkout -q feat/task
}

# $1 = sin-trailer | (vacío = con trailer)
monta_revert() {
  sb_reset
  rm -rf "$SB/estado"
  gitr checkout -q master
  printf 'app v2\n' > "$WORK/app.sh"
  if [ "${1:-}" = "sin-trailer" ]; then
    gitr commit -qam "feat: task (#7)"
  else
    gitr commit -qam "feat: task (#7)

Saikit-Merge: $SHA"
  fi
  gitr push -q origin master
  MC="$(gitr rev-parse HEAD)"
  gitr checkout -qb revert/task
  gitr revert --no-edit "$MC" >/dev/null 2>&1
  gitr push -q origin revert/task
  RHEAD="$(gitr rev-parse HEAD)"
  printf '{"number":8,"baseRefName":"master","headRefOid":"%s","author":{"login":"op"},"mergeable":"MERGEABLE"}' \
    "$RHEAD" > "$SB/ghfix/pr.json"
  printf '8\n' > "$SB/ghfix/expected-pr"
  printf '%s\n' "$RHEAD" > "$SB/ghfix/expected-sha"
}

run_merge() {
  runtime_exec "$WORK" \
    env \
      PATH="$SB/bin:$PATH" \
      SAIKIT_GH_FIX="$SB/ghfix" \
      SAIKIT_GH_LOG="$SB/gh.log" \
      SAIKIT_ESTADO_ROOT="$SB/estado" \
      SAIKIT_MERGE_RETRY_SEG=0 \
    bash "$MERGE" "$@"
}

# r1 (cross-review 20.x / 20.5): variante con cwd explicito y el gancho de
# test SOSTENER (duerme con el lock tomado) para orquestar la contencion con
# determinismo. Produccion intacta: sin la variable no duerme nada.
run_merge_en() {
  local cwd="$1" sostener="$2" gh_log_path="$3"
  shift 3
  runtime_exec "$cwd" \
    env \
      PATH="$SB/bin:$PATH" \
      SAIKIT_GH_FIX="$SB/ghfix" \
      SAIKIT_GH_LOG="$gh_log_path" \
      SAIKIT_ESTADO_ROOT="$SB/estado" \
      SAIKIT_MERGE_RETRY_SEG=0 \
      SAIKIT_MERGE_SOSTENER_SEG="$sostener" \
    bash "$MERGE" "$@"
}

esperar_lock() {  # $1=lock dir → 0 cuando aparece (hasta ~5s)
  local i=0
  while [ "$i" -lt 50 ]; do
    [ -d "$1" ] && return 0
    sleep 0.1
    i=$((i + 1))
  done
  return 1
}

gh_log() { cat "$SB/gh.log" 2>/dev/null || true; }

merge_called() { grep -q '^gh pr merge' "$SB/gh.log" 2>/dev/null; }

assert_no_merge() {
  local case_id="$1" asid="$2"
  if merge_called; then
    fm_fail "$case_id" "$asid" "gh pr merge ausente" "gh pr merge presente: $(gh_log)"
  else
    fm_pass "$case_id" "$asid" "gh pr merge ausente" "gh pr merge ausente"
  fi
}

if fm_only merge-listo; then
  sb_reset
  set +e
  out="$(run_merge 2>&1)"
  rc=$?
  set -e
  fm_action merge-listo act-listo "$rc" "$out" bash "$MERGE"
  if printf '%s' "$out" | grep -q 'LISTO:'; then
    fm_pass merge-listo listo_line "LISTO:" "LISTO:"
  else
    fm_fail merge-listo listo_line "LISTO:" "$out"
  fi
  # assert:no_merge_on_listo
  assert_no_merge merge-listo no_merge_on_listo
  # assert:no_merge_on_listo_end
fi

if fm_only merge-confirmado; then
  sb_reset
  h_antes="$(sha256sum "$WORK/.saikit/veredictos/$SHA.json" | cut -d' ' -f 1)"
  set +e
  out="$(run_merge --confirmado 2>&1)"
  rc=$?
  set -e
  log="$(gh_log)"
  fm_action merge-confirmado act-confirmado "$rc" "$out" bash "$MERGE" --confirmado
  if printf '%s' "$out" | grep -q 'MERGE-OK:'; then
    fm_pass merge-confirmado merge_ok "MERGE-OK:" "MERGE-OK:"
  else
    fm_fail merge-confirmado merge_ok "MERGE-OK:" "$out"
  fi
  # assert:match_head
  if printf '%s' "$log" | grep -Fq -- "--match-head-commit $SHA"; then
    fm_pass merge-confirmado match_head "--match-head-commit $SHA" \
      "--match-head-commit $SHA"
  else
    fm_fail merge-confirmado match_head "--match-head-commit $SHA" "$log"
  fi
  # assert:match_head_end
  # assert:no_admin
  if printf '%s' "$log" | grep -Fq -- '--admin'; then
    fm_fail merge-confirmado no_admin "sin --admin" "--admin presente: $log"
  else
    fm_pass merge-confirmado no_admin "sin --admin" "sin --admin"
  fi
  # assert:no_admin_end
  # assert:no_delete_branch
  if printf '%s' "$log" | grep -Fq -- '--delete-branch'; then
    fm_fail merge-confirmado no_delete_branch "sin --delete-branch" \
      "--delete-branch presente: $log"
  else
    fm_pass merge-confirmado no_delete_branch "sin --delete-branch" \
      "sin --delete-branch"
  fi
  # assert:no_delete_branch_end
  # assert:ci_revalidated
  if printf '%s' "$log" | grep -q 'gh run list'; then
    fm_pass merge-confirmado ci_revalidated "gh run list" "gh run list"
  else
    fm_fail merge-confirmado ci_revalidated "gh run list" "$log"
  fi
  # assert:ci_revalidated_end
  h_despues="$(sha256sum "$WORK/.saikit/veredictos/$SHA.json" | cut -d' ' -f 1)"
  # assert:sello_intact
  if [ "$h_antes" = "$h_despues" ]; then
    fm_pass merge-confirmado sello_intact "sello intacto (byte-identical)" \
      "sello intacto (byte-identical)"
  else
    fm_fail merge-confirmado sello_intact "sello intacto (byte-identical)" \
      "hash $h_antes -> $h_despues"
  fi
  # assert:sello_intact_end
fi

if fm_only merge-ci-rojo; then
  sb_reset
  printf '[{"event":"pull_request","status":"completed","conclusion":"failure","workflow":"ci"}]' \
    > "$SB/ghfix/runs.json"
  set +e
  out="$(run_merge --confirmado 2>&1)"
  rc=$?
  set -e
  fm_action merge-ci-rojo act-ci-rojo "$rc" "$out" bash "$MERGE" --confirmado
  # assert:reject_ci_rojo
  if printf '%s' "$out" | grep -q 'NO-MERGE: CI rojo'; then
    fm_pass merge-ci-rojo reject_ci_rojo "NO-MERGE: CI rojo" "NO-MERGE: CI rojo"
  else
    fm_fail merge-ci-rojo reject_ci_rojo "NO-MERGE: CI rojo" "$out"
  fi
  # assert:reject_ci_rojo_end
  assert_no_merge merge-ci-rojo no_merge_on_ci_rojo
fi

if fm_only merge-base-movida; then
  sb_reset
  avanzar_base
  set +e
  out="$(run_merge --confirmado 2>&1)"
  rc=$?
  set -e
  fm_action merge-base-movida act-base "$rc" "$out" bash "$MERGE" --confirmado
  # assert:reject_base_avanzada
  if printf '%s' "$out" | grep -q 'NO-MERGE: base avanzada'; then
    fm_pass merge-base-movida reject_base_avanzada "NO-MERGE: base avanzada" \
      "NO-MERGE: base avanzada"
  else
    fm_fail merge-base-movida reject_base_avanzada "NO-MERGE: base avanzada" "$out"
  fi
  # assert:reject_base_avanzada_end
  assert_no_merge merge-base-movida no_merge_on_base
fi

if fm_only merge-sello-ajeno; then
  sb_reset
  python3 - "$WORK/.saikit/veredictos/$SHA.json" <<'PY'
import json, sys
from pathlib import Path
p = Path(sys.argv[1])
d = json.loads(p.read_text(encoding="utf-8"))
d["sha"] = "otro0000000000000000000000000000000000000"
p.write_text(json.dumps(d, separators=(",", ":")), encoding="utf-8")
PY
  set +e
  out="$(run_merge --confirmado 2>&1)"
  rc=$?
  set -e
  fm_action merge-sello-ajeno act-sello "$rc" "$out" bash "$MERGE" --confirmado
  # assert:reject_sello_ajeno
  if printf '%s' "$out" | grep -q 'NO-MERGE: veredicto de otro sha'; then
    fm_pass merge-sello-ajeno reject_sello_ajeno \
      "NO-MERGE: veredicto de otro sha" "NO-MERGE: veredicto de otro sha"
  else
    fm_fail merge-sello-ajeno reject_sello_ajeno \
      "NO-MERGE: veredicto de otro sha" "$out"
  fi
  # assert:reject_sello_ajeno_end
  assert_no_merge merge-sello-ajeno no_merge_on_sello
fi

if fm_only merge-head-cambiado; then
  sb_reset
  sha_viejo="$SHA"
  printf 'app v3\n' >> "$WORK/app.sh"
  gitr commit -qam "feat: un commit mas"
  gitr push -q origin feat/task
  refix
  rm -f "$WORK/.saikit/veredictos/$SHA.json"
  printf '{"sha":"%s","pr":7,"verifier":"PASS","verify_app":{"resultado":"PASS","comando":"bash verify/app.sh"},"blast":{"nivel":4,"hecho":"h","comando":"bash tests/run.sh"},"adversary":"n/a","reviewer":"clean","decisiones":"d"}' \
    "$sha_viejo" > "$WORK/.saikit/veredictos/$sha_viejo.json"
  set +e
  out="$(run_merge --confirmado 2>&1)"
  rc=$?
  set -e
  fm_action merge-head-cambiado act-head "$rc" "$out" bash "$MERGE" --confirmado
  # assert:reject_head_cambiado
  if printf '%s' "$out" | grep -q 'NO-MERGE: commits despues del veredicto'; then
    fm_pass merge-head-cambiado reject_head_cambiado \
      "NO-MERGE: commits despues del veredicto" \
      "NO-MERGE: commits despues del veredicto"
  else
    fm_fail merge-head-cambiado reject_head_cambiado \
      "NO-MERGE: commits despues del veredicto" "$out"
  fi
  # assert:reject_head_cambiado_end
  assert_no_merge merge-head-cambiado no_merge_on_head
fi

if fm_only revert-ok; then
  monta_revert
  set +e
  out="$(run_merge --revert-de "$MC" --confirmado 2>&1)"
  rc=$?
  set -e
  log="$(gh_log)"
  fm_action revert-ok act-revert "$rc" "$out" bash "$MERGE" --revert-de "$MC" --confirmado
  if printf '%s' "$out" | grep -q 'MERGE-OK:'; then
    fm_pass revert-ok revert_merge_ok "MERGE-OK:" "MERGE-OK:"
  else
    fm_fail revert-ok revert_merge_ok "MERGE-OK:" "$out"
  fi
  if printf '%s' "$log" | grep -Fq -- "--match-head-commit $RHEAD"; then
    fm_pass revert-ok revert_match_head "--match-head-commit $RHEAD" \
      "--match-head-commit $RHEAD"
  else
    fm_fail revert-ok revert_match_head "--match-head-commit $RHEAD" "$log"
  fi
fi

if fm_only revert-sin-trailer; then
  monta_revert sin-trailer
  set +e
  out="$(run_merge --revert-de "$MC" --confirmado 2>&1)"
  rc=$?
  set -e
  fm_action revert-sin-trailer act-trailer "$rc" "$out" \
    bash "$MERGE" --revert-de "$MC" --confirmado
  # assert:reject_sin_trailer
  if printf '%s' "$out" | grep -q 'NO-MERGE: sin trailer'; then
    fm_pass revert-sin-trailer reject_sin_trailer "NO-MERGE: sin trailer" \
      "NO-MERGE: sin trailer"
  else
    fm_fail revert-sin-trailer reject_sin_trailer "NO-MERGE: sin trailer" "$out"
  fi
  # assert:reject_sin_trailer_end
  assert_no_merge revert-sin-trailer no_merge_on_trailer
fi

if fm_only revert-no-punta; then
  monta_revert
  gitr checkout -q master
  printf 'post\n' > "$WORK/post.sh"
  gitr add post.sh
  gitr commit -qm "chore: algo mas aterrizo"
  gitr push -q origin master
  gitr checkout -q revert/task
  set +e
  out="$(run_merge --revert-de "$MC" --confirmado 2>&1)"
  rc=$?
  set -e
  fm_action revert-no-punta act-punta "$rc" "$out" \
    bash "$MERGE" --revert-de "$MC" --confirmado
  # assert:reject_no_punta
  if printf '%s' "$out" | grep -q 'NO-MERGE: no es la punta'; then
    fm_pass revert-no-punta reject_no_punta "NO-MERGE: no es la punta" \
      "NO-MERGE: no es la punta"
  else
    fm_fail revert-no-punta reject_no_punta "NO-MERGE: no es la punta" "$out"
  fi
  # assert:reject_no_punta_end
  assert_no_merge revert-no-punta no_merge_on_punta
fi

# ---------------------------------------------------------------------------
# Lock de integracion (20.5): contencion dos procesos.
# ---------------------------------------------------------------------------
if fm_only merge-lock-contencion; then
  sb_reset
  lock="$WORK/.git/saikit-merge.lock"
  ( run_merge_en "$WORK" 8 "$SB/gh-owner.log" --confirmado >"$SB/lock-a.out" 2>&1; echo $? >"$SB/lock-a.rc" ) &
  a_pid=$!
  if esperar_lock "$lock"; then
    set +e
    out="$(run_merge --confirmado 2>&1)"
    rc=$?
    set -e
    # El contender conserva su propio log: ninguna llamada valida del owner
    # puede contaminar esta atribucion aunque termine antes de la foto.
    gh_foto="$(gh_log)"
    fm_action merge-lock-contencion act-lock "$rc" "$out" \
      bash "$MERGE" --confirmado
    # assert:lock_exit_3
    if [ "$rc" -eq 3 ]; then
      fm_pass merge-lock-contencion lock_exit_3 "exit 3" "exit 3 (lock ajeno)"
    else
      fm_fail merge-lock-contencion lock_exit_3 "exit 3" "rc=$rc $out"
    fi
    # assert:lock_reporta_hint
    if printf '%s' "$out" | grep -q 'LOCK de integracion ocupado' \
      && printf '%s' "$out" | grep -q -- '--liberar-lock'; then
      fm_pass merge-lock-contencion lock_reporta_hint \
        "LOCK ocupado + --liberar-lock" "reporta lock y via de recuperacion"
    else
      fm_fail merge-lock-contencion lock_reporta_hint \
        "LOCK ocupado + --liberar-lock" "$out"
    fi
    # assert:no_merge_on_lock
    if printf '%s' "$gh_foto" | grep -q '^gh pr merge'; then
      fm_fail merge-lock-contencion no_merge_on_lock "gh pr merge ausente" \
        "mergeo con lock ajeno: $gh_foto"
    else
      fm_pass merge-lock-contencion no_merge_on_lock "gh pr merge ausente" \
        "el rechazado no llamo merge"
    fi
  else
    fm_action merge-lock-contencion act-lock "" "" bash "$MERGE" --confirmado
    fm_fail merge-lock-contencion lock_exit_3 "exit 3" \
      "el proceso A no tomo el lock (timeout esperando $lock)"
  fi
  wait "$a_pid" 2>/dev/null || true
fi

# ---------------------------------------------------------------------------
# Lock: el dueno libera SOLO el propio; el ajeno sobrevive al rechazo.
# ---------------------------------------------------------------------------
if fm_only merge-lock-propio; then
  sb_reset
  lock="$WORK/.git/saikit-merge.lock"
  ( run_merge_en "$WORK" 4 "$SB/gh-owner.log" --confirmado >"$SB/lock-a.out" 2>&1; echo $? >"$SB/lock-a.rc" ) &
  a_pid=$!
  if esperar_lock "$lock"; then
    set +e
    out="$(run_merge --confirmado 2>&1)"
    rc=$?
    set -e
    fm_action merge-lock-propio act-propio "$rc" "$out" bash "$MERGE" --confirmado
    # assert:lock_ajeno_sobrevive
    if [ -d "$lock" ]; then
      fm_pass merge-lock-propio lock_ajeno_sobrevive "lock ajeno presente" \
        "exit $rc del rechazado no borro el lock del dueno"
    else
      fm_fail merge-lock-propio lock_ajeno_sobrevive "lock ajeno presente" \
        "el rechazado (rc=$rc) borro un lock ajeno"
    fi
    wait "$a_pid" 2>/dev/null || true
    # assert:lock_propio_liberado
    if [ ! -d "$lock" ]; then
      fm_pass merge-lock-propio lock_propio_liberado "lock retirado" \
        "el dueno libero su lock al salir (rc A: $(cat "$SB/lock-a.rc" 2>/dev/null || echo '?'))"
    else
      fm_fail merge-lock-propio lock_propio_liberado "lock retirado" \
        "el dueno salio y su lock sobrevive: $(cat "$SB/lock-a.out" 2>/dev/null)"
    fi
  else
    fm_action merge-lock-propio act-propio "" "" bash "$MERGE" --confirmado
    fm_fail merge-lock-propio lock_ajeno_sobrevive "lock ajeno presente" \
      "el proceso A no tomo el lock (timeout esperando $lock)"
    fm_fail merge-lock-propio lock_propio_liberado "lock retirado" "sin dueno que liberar"
    wait "$a_pid" 2>/dev/null || true
  fi
fi

# ---------------------------------------------------------------------------
# Lock: dos worktrees del MISMO clone comparten el archivo (git-common-dir).
# ---------------------------------------------------------------------------
if fm_only merge-lock-worktrees; then
  sb_reset
  lock="$WORK/.git/saikit-merge.lock"
  ( run_merge_en "$WORK" 8 "$SB/gh-owner.log" --confirmado >"$SB/lock-a.out" 2>&1; echo $? >"$SB/lock-a.rc" ) &
  a_pid=$!
  if esperar_lock "$lock"; then
    gitr worktree add -q "$SB/wt2" -b wt2 2>/dev/null || gitr worktree add "$SB/wt2" -b wt2
    set +e
    out="$(run_merge_en "$SB/wt2" 0 "$SB/gh.log" --confirmado 2>&1)"
    rc=$?
    set -e
    gh_foto="$(gh_log)"
    fm_action merge-lock-worktrees act-wt "$rc" "$out" \
      bash "$MERGE" --confirmado "desde worktree wt2"
    # assert:lock_comun_worktrees
    # El tool canoniza el common-dir con pwd -P (macOS: /private/var/...):
    # comparar contra la ruta canonica del lock del worktree principal.
    lock_canon="$(cd "$WORK/.git" 2>/dev/null && pwd -P)/saikit-merge.lock"
    if [ "$rc" -eq 3 ] && printf '%s' "$out" | grep -Fq "$lock_canon"; then
      fm_pass merge-lock-worktrees lock_comun_worktrees "exit 3 con el lock del clone" \
        "el worktree rechazo por el MISMO $lock"
    else
      fm_fail merge-lock-worktrees lock_comun_worktrees "exit 3 con el lock del clone" \
        "rc=$rc $out"
    fi
    # assert:no_merge_on_lock_wt
    if printf '%s' "$gh_foto" | grep -q '^gh pr merge'; then
      fm_fail merge-lock-worktrees no_merge_on_lock_wt "gh pr merge ausente" \
        "mergeo desde worktree con lock ajeno: $gh_foto"
    else
      fm_pass merge-lock-worktrees no_merge_on_lock_wt "gh pr merge ausente" \
        "el worktree rechazado no llamo merge"
    fi
  else
    fm_action merge-lock-worktrees act-wt "" "" bash "$MERGE" --confirmado
    fm_fail merge-lock-worktrees lock_comun_worktrees "exit 3 con el lock del clone" \
      "el proceso A no tomo el lock (timeout esperando $lock)"
  fi
  wait "$a_pid" 2>/dev/null || true
fi

# ---------------------------------------------------------------------------
# Lock: recuperacion EXPLICITA con --liberar-lock (unica via).
# ---------------------------------------------------------------------------
if fm_only merge-lock-recuperacion; then
  sb_reset
  lock="$WORK/.git/saikit-merge.lock"
  mkdir -p "$lock"
  printf '999999' > "$lock/pid"
  printf 'host-muerto' > "$lock/host"
  printf '2020-01-01T00:00:00Z' > "$lock/started_at"
  printf 'merge' > "$lock/modo"
  set +e
  out="$(run_merge --liberar-lock 2>&1)"
  rc=$?
  set -e
  fm_action merge-lock-recuperacion act-liberar "$rc" "$out" \
    bash "$MERGE" --liberar-lock
  # assert:liberar_quita_y_muestra
  if [ "$rc" -eq 0 ] && [ ! -d "$lock" ] \
    && printf '%s' "$out" | grep -q 'lock de integracion encontrado' \
    && printf '%s' "$out" | grep -q 'pid: 999999' \
    && printf '%s' "$out" | grep -q 'host: host-muerto' \
    && printf '%s' "$out" | grep -q 'inicio: 2020-01-01T00:00:00Z' \
    && printf '%s' "$out" | grep -q 'modo: merge' \
    && printf '%s' "$out" | grep -q 'lock de integracion liberado'; then
    fm_pass merge-lock-recuperacion liberar_quita_y_muestra \
      "muestra contenido y quita" "muestra pid/host/fecha y quita el lock"
  else
    fm_fail merge-lock-recuperacion liberar_quita_y_muestra \
      "muestra contenido y quita" "rc=$rc lock=$([ -d "$lock" ] && echo presente || echo ausente) $out"
  fi
  set +e
  out2="$(run_merge --liberar-lock 2>&1)"
  rc2=$?
  set -e
  fm_action merge-lock-recuperacion act-liberar-sin-lock "$rc2" "$out2" \
    bash "$MERGE" --liberar-lock
  # assert:liberar_sin_lock_verde
  if [ "$rc2" -eq 0 ] && printf '%s' "$out2" | grep -q 'nada que liberar'; then
    fm_pass merge-lock-recuperacion liberar_sin_lock_verde \
      "exit 0 + nada que liberar" "sin lock es no-op en verde"
  else
    fm_fail merge-lock-recuperacion liberar_sin_lock_verde \
      "exit 0 + nada que liberar" "rc=$rc2 $out2"
  fi
fi

exit 0
