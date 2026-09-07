#!/usr/bin/env python3
"""Evidencia v1 por intento exclusivo (feature map, task 19.3).

CLI: create-attempt, append-step, finalize, validate, redact, redact-file.
Mutaciones (SAIKIT_VERIFY_MUTATE): skip_empty_guard, skip_required_assertions,
lie_counts, exit_summary_mismatch, degrade_fail_to_unknown, skip_redact,
reuse_attempt_id, skip_result_recompute, skip_case_keys, skip_required_freeze,
skip_redacted_strip.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import secrets
import shlex
import subprocess
import sys
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

AssertionKey = tuple[str, str]

SCHEMA_VERSION = 1
RESULTS = ("PASS", "FAIL", "unknown")
STEP_TYPES = ("action", "assertion", "diagnostic")
MODES = ("sandbox", "simulated", "live")
RANK = {"PASS": 0, "unknown": 1, "FAIL": 2}
EXIT_FOR = {"PASS": 0, "FAIL": 1, "unknown": 3}
_ID_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]*$")
_IDENTITY_REQUIRED = (
    "schema_version",
    "run_id",
    "attempt_id",
    "feature_id",
    "mode",
    "cases",
    "required_assertions",
    "required_keys",
    "provenance",
)

# Misma familia que tools/lib/redactar.sh (escaneo + reemplazo).
_SCAN_RE = re.compile(
    r"([Tt][Oo][Kk][Ee][Nn]|[Pp][Aa][Ss][Ss][Ww][Oo][Rr][Dd])=\S|"
    r"://[^\s@/?#]*@|"
    r"ghp_[A-Za-z0-9]|"
    r"github_pat_[A-Za-z0-9]|"
    r"gho_[A-Za-z0-9]|"
    r"(^|[^A-Za-z0-9])sk-[A-Za-z0-9]|"
    r"AKIA[0-9A-Z]|"
    r"xox[bp]-[A-Za-z0-9]"
)
# Reemplazos en el mismo orden que redactar().
_SUBS: list[tuple[re.Pattern[str], str]] = [
    (
        re.compile(
            r"([Tt][Oo][Kk][Ee][Nn]|[Pp][Aa][Ss][Ss][Ww][Oo][Rr][Dd])="
            r"('[^']*'|\"[^\"]*\"|[^\s]*)"
        ),
        r"\1=[REDACTED]",
    ),
    (re.compile(r"://[^\s@/?#]*@"), "://[REDACTED]@"),
    (re.compile(r"ghp_[A-Za-z0-9_-]*"), "[REDACTED]"),
    (re.compile(r"github_pat_[A-Za-z0-9_-]*"), "[REDACTED]"),
    (re.compile(r"gho_[A-Za-z0-9_-]*"), "[REDACTED]"),
    (re.compile(r"(^|[^A-Za-z0-9])(sk-[A-Za-z0-9_-]*)"), r"\1[REDACTED]"),
    (re.compile(r"AKIA[0-9A-Z]{16}"), "[REDACTED]"),
    (re.compile(r"xox[bp]-[A-Za-z0-9_-]*"), "[REDACTED]"),
]


class EvidenceError(Exception):
    """Evidencia inválida o I/O (exit 1)."""


def mutate() -> str:
    return os.environ.get("SAIKIT_VERIFY_MUTATE") or ""


def utc_now() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def redact_text(text: str) -> str:
    if mutate() == "skip_redact":
        return text
    out = text
    for pat, repl in _SUBS:
        out = pat.sub(repl, out)
    return out


def redact_value(value: Any) -> Any:
    if mutate() == "skip_redact":
        return value
    if isinstance(value, str):
        return redact_text(value)
    if isinstance(value, list):
        return [redact_value(v) for v in value]
    if isinstance(value, dict):
        return {k: redact_value(v) for k, v in value.items()}
    return value


# Hook SAIKIT_ADV_REDACTED_STRIP: token=[REDACTED] is not a secret.
_REDACTED_STRIP: list[tuple[re.Pattern[str], str]] = [
    (re.compile(r'="\[REDACTED\]"(?=\s|$)'), '= "'),
    (re.compile(r'="\[REDACTED\]"([]"[,}>])(?=[]"[{},;:)>]|\s|$)'), r'= "\1'),
    (re.compile(r'="\[REDACTED\]"([;)])(?=\s|$)'), r'= "\1'),
    (re.compile(r"=\[REDACTED\](?=\s|$)"), "= "),
    (re.compile(r'=\[REDACTED\]([]"[,}>])(?=[]"[{},;:)>]|\s|$)'), r"= \1"),
    (re.compile(r"=\[REDACTED\]([;)])(?=\s|$)"), r"= \1"),
    (re.compile(r"://\[REDACTED\]@"), ":// "),
]


def strip_redacted(text: str) -> str:
    out = text
    for pat, repl in _REDACTED_STRIP:
        out = pat.sub(repl, out)
    return out


def contains_secret(text: str) -> bool:
    scanned = text if mutate() == "skip_redacted_strip" else strip_redacted(text)
    return bool(_SCAN_RE.search(scanned))


def assertion_key(case_id: Any, assertion_id: Any) -> AssertionKey:
    return (str(case_id or "").strip(), str(assertion_id or "").strip())


def format_key(key: AssertionKey) -> str:
    case_id, asid = key
    if case_id:
        return f"{case_id}:{asid}"
    return asid


def validate_id(value: Any, label: str) -> str:
    text = str(value or "")
    if not _ID_RE.fullmatch(text):
        raise EvidenceError(f"{label}: identificador inválido")
    return text


def reject_symlink_components(path: Path, label: str) -> None:
    absolute = path.absolute()
    current = Path(absolute.anchor)
    for part in absolute.parts[1:]:
        current /= part
        if not current.is_symlink():
            continue
        system_alias = (
            current.parent == Path(current.anchor)
            and current.name in {"tmp", "var", "etc"}
            and current.resolve() == Path("/private") / current.name
        )
        if not system_alias:
            raise EvidenceError(f"{label}: symlink escape")


def parse_required_token(token: str, cases: list[str]) -> AssertionKey:
    raw = token.strip()
    if ":" in raw:
        case_id, asid = raw.split(":", 1)
        if not case_id or not asid:
            raise EvidenceError("required-assertions: clave case_id:assertion_id inválida")
        if cases and case_id not in cases:
            raise EvidenceError(
                f"required-assertions: case_id {case_id!r} no está en identity"
            )
        return assertion_key(case_id, asid)
    if len(cases) == 1:
        return assertion_key(cases[0], raw)
    if len(cases) > 1:
        raise EvidenceError(
            "required-assertions ambiguas: use case_id:assertion_id con varios casos"
        )
    return assertion_key("", raw)


def parse_required_list(tokens: list[str], cases: list[str]) -> list[AssertionKey]:
    return [parse_required_token(t, cases) for t in tokens if t]


def keys_equal(left: list[AssertionKey], right: list[AssertionKey]) -> bool:
    return Counter(left) == Counter(right)


def frozen_required(ident: dict[str, Any]) -> list[AssertionKey]:
    cases = [str(c) for c in (ident.get("cases") or []) if c]
    stored = ident.get("required_keys")
    if isinstance(stored, list) and stored:
        out: list[AssertionKey] = []
        for item in stored:
            if isinstance(item, dict):
                out.append(assertion_key(item.get("case_id"), item.get("assertion_id")))
        if out:
            return out
    return parse_required_list([str(t) for t in (ident.get("required_assertions") or [])], cases)


def is_availability_channel(frozen: list[AssertionKey], cli: list[AssertionKey]) -> bool:
    return (not frozen) and cli == [("", "availability")]


def serialize_keys(keys: list[AssertionKey]) -> list[dict[str, str]]:
    return [{"case_id": c, "assertion_id": a} for c, a in keys]


def observed_keys(steps: list[dict[str, Any]]) -> list[AssertionKey]:
    out: list[AssertionKey] = []
    for rec in assertions_of(steps):
        asid = rec.get("assertion_id")
        if asid:
            out.append(assertion_key(rec.get("case_id"), asid))
    return out


def missing_required(
    required: list[AssertionKey],
    observed: list[AssertionKey],
) -> list[str]:
    if mutate() == "skip_case_keys":
        seen = {asid for _, asid in observed if asid}
        return [format_key(k) for k in required if k[1] not in seen]
    missing: list[str] = []
    obs_set = set(observed)
    for key in required:
        if key[0] and key not in obs_set:
            missing.append(format_key(key))
    need = Counter(asid for case, asid in required if not case)
    got = Counter(asid for _, asid in observed if asid in need)
    for asid, count in need.items():
        if got[asid] < count:
            missing.append(asid)
    return missing


def resolve_required(ident: dict[str, Any], raw: str | None) -> list[AssertionKey]:
    cases = [str(c) for c in (ident.get("cases") or []) if c]
    frozen = frozen_required(ident)
    tokens = split_words(raw)
    if not tokens:
        return frozen
    cli = parse_required_list(tokens, cases)
    if keys_equal(cli, frozen):
        return frozen
    if is_availability_channel(frozen, cli):
        return cli
    if mutate() == "skip_required_freeze":
        return cli
    raise EvidenceError("required-assertions no coincide con identity")


def split_words(raw: str | None) -> list[str]:
    if not raw:
        return []
    return [p for p in raw.replace(",", " ").split() if p]


def new_attempt_id() -> str:
    if mutate() == "reuse_attempt_id":
        return "reused"
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
    return f"{stamp}-{os.getpid()}-{secrets.token_hex(8)}"


def provenance(repo: Path) -> dict[str, Any]:
    sha = "unknown"
    dirty = False
    try:
        r = subprocess.run(
            ["git", "-C", str(repo), "rev-parse", "HEAD"],
            capture_output=True,
            text=True,
            check=False,
        )
        if r.returncode == 0 and r.stdout.strip():
            sha = r.stdout.strip()
        d = subprocess.run(
            ["git", "-C", str(repo), "status", "--porcelain"],
            capture_output=True,
            text=True,
            check=False,
        )
        dirty = bool(d.stdout.strip())
    except OSError:
        pass
    hook = repo / "hooks" / "summonaikit-harness.sh"
    target = hook if hook.is_file() else Path(__file__)
    digest = hashlib.sha256(target.read_bytes()).hexdigest() if target.is_file() else ""
    return {"git_sha": sha, "dirty": dirty, "file_hash": digest}


def identity_path(attempt_dir: Path) -> Path:
    return attempt_dir / "identity.json"


def load_identity(attempt_dir: Path) -> dict[str, Any]:
    p = identity_path(attempt_dir)
    if not p.is_file():
        raise EvidenceError(f"falta identity.json en {attempt_dir}")
    data = json.loads(p.read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        raise EvidenceError("identity.json no es un objeto")
    missing = [key for key in _IDENTITY_REQUIRED if key not in data]
    if missing:
        raise EvidenceError(f"identity.json incompleta: {','.join(missing)}")
    if data.get("schema_version") != SCHEMA_VERSION:
        raise EvidenceError("identity.json schema_version inválida")
    for key in ("run_id", "attempt_id", "feature_id"):
        validate_id(data.get(key), f"identity.{key}")
    if data.get("mode") not in MODES:
        raise EvidenceError("identity.mode inválido")
    if not isinstance(data.get("cases"), list):
        raise EvidenceError("identity.cases inválido")
    if not isinstance(data.get("required_assertions"), list):
        raise EvidenceError("identity.required_assertions inválido")
    if not isinstance(data.get("required_keys"), list):
        raise EvidenceError("identity.required_keys inválido")
    if not isinstance(data.get("provenance"), dict):
        raise EvidenceError("identity.provenance inválida")
    return data


def read_steps(attempt_dir: Path) -> list[dict[str, Any]]:
    p = attempt_dir / "steps.jsonl"
    if not p.is_file():
        return []
    rows: list[dict[str, Any]] = []
    for line in p.read_text(encoding="utf-8").splitlines():
        if not line.strip():
            continue
        rows.append(json.loads(line))
    return rows


def write_json(path: Path, data: dict[str, Any]) -> None:
    path.write_text(json.dumps(redact_value(data), ensure_ascii=False) + "\n", encoding="utf-8")


def parse_tool_exit(raw: str | None) -> int | None:
    if raw is None or raw == "":
        return None
    return int(raw)


def cmd_create_attempt(args: argparse.Namespace) -> int:
    artifacts = Path(args.artifacts)
    run_id = validate_id(args.run_id, "run_id")
    feature_id = validate_id(args.feature_id, "feature_id")
    cases = split_words(args.cases)
    required = split_words(args.required_assertions)
    keys = parse_required_list(required, cases)
    reject_symlink_components(artifacts, "artifacts")
    reject_symlink_components(artifacts / run_id / feature_id, "attempt path")
    attempt_id = new_attempt_id()
    dest = artifacts / run_id / feature_id / attempt_id
    if mutate() == "reuse_attempt_id":
        dest.mkdir(parents=True, exist_ok=True)
    else:
        for _ in range(16):
            try:
                dest.mkdir(parents=True)
                break
            except FileExistsError:
                attempt_id = new_attempt_id()
                dest = artifacts / run_id / feature_id / attempt_id
        else:
            raise EvidenceError("no se pudo asignar attempt_id exclusivo")
    # Escribir antes de ejecutar: dir + steps vacíos + identidad.
    (dest / "steps.jsonl").write_text("", encoding="utf-8")
    ident = {
        "schema_version": SCHEMA_VERSION,
        "run_id": run_id,
        "attempt_id": attempt_id,
        "feature_id": feature_id,
        "mode": args.mode,
        "cases": cases,
        "required_assertions": required,
        "required_keys": serialize_keys(keys),
        "started_at": utc_now(),
        "repo": args.repo,
        "scope": args.scope,
        "scope_partial": bool(args.scope_partial) or args.scope == "partial",
        "provenance": provenance(Path(args.repo)) if args.repo else {},
    }
    write_json(identity_path(dest), ident)
    print(f"ATTEMPT_ID={attempt_id}")
    print(f"ATTEMPT_DIR={dest}")
    return 0


def cmd_append_step(args: argparse.Namespace) -> int:
    attempt_dir = Path(args.attempt_dir)
    ident = load_identity(attempt_dir)
    commands = list(args.command or [])
    if len(commands) == 1 and any(ch.isspace() for ch in commands[0]):
        argv = shlex.split(commands[0])
    else:
        argv = commands
    rec: dict[str, Any] = {
        "schema_version": SCHEMA_VERSION,
        "type": args.type,
        "run_id": ident["run_id"],
        "attempt_id": ident["attempt_id"],
        "feature_id": ident["feature_id"],
        "case_id": args.case_id or "",
        "step_id": args.step_id or f"s-{secrets.token_hex(4)}",
        "time": utc_now(),
        "mode": ident.get("mode") or "sandbox",
        "command": redact_value(argv) if argv else None,
        "tool_exit": parse_tool_exit(args.tool_exit),
        "observation": redact_value(args.observation) if args.observation is not None else None,
        "log_ref": args.log_ref,
    }
    if args.type == "assertion":
        rec["assertion_id"] = args.assertion_id or ""
        rec["expected"] = redact_value(args.expected)
        rec["observed"] = redact_value(args.observed)
        rec["result"] = args.result or "unknown"
    rec = redact_value(rec)
    with (attempt_dir / "steps.jsonl").open("a", encoding="utf-8") as fh:
        fh.write(json.dumps(rec, ensure_ascii=False) + "\n")
    if args.observation:
        log = attempt_dir / "log.txt"
        with log.open("a", encoding="utf-8") as fh:
            fh.write(redact_text(args.observation) + "\n")
    return 0


def assertions_of(steps: list[dict[str, Any]]) -> list[dict[str, Any]]:
    return [s for s in steps if s.get("type") == "assertion"]


def aggregate(results: list[str]) -> str:
    worst = "PASS"
    for r in results:
        if r not in RANK:
            continue
        if mutate() == "degrade_fail_to_unknown" and r == "FAIL":
            r = "unknown"
        if RANK[r] > RANK[worst]:
            worst = r
    return worst


def build_summary(
    ident: dict[str, Any],
    steps: list[dict[str, Any]],
    required: list[AssertionKey],
    reasons: list[str],
    result: str,
    extra_scope: str | None,
    scope_partial: bool,
) -> dict[str, Any]:
    observed = [format_key(k) for k in observed_keys(steps)]
    step_count = len(steps)
    assertion_count = len(assertions_of(steps))
    if mutate() == "lie_counts":
        step_count = 999
        assertion_count = 999
    exit_code = EXIT_FOR[result]
    if mutate() == "exit_summary_mismatch":
        if result == "PASS":
            exit_code = 1
        elif exit_code == 1:
            exit_code = 0
        else:
            exit_code = 0
    cases = ident.get("cases") or []
    scope = extra_scope or ident.get("scope") or "full"
    partial = scope_partial or bool(ident.get("scope_partial")) or scope == "partial"
    if partial:
        scope = "partial"
    return {
        "schema_version": SCHEMA_VERSION,
        "version": SCHEMA_VERSION,
        "identity": {
            "run_id": ident.get("run_id"),
            "attempt_id": ident.get("attempt_id"),
            "feature_id": ident.get("feature_id"),
        },
        "run_id": ident.get("run_id"),
        "attempt_id": ident.get("attempt_id"),
        "feature_id": ident.get("feature_id"),
        "cases": cases,
        "cases_requested": cases,
        "mode": ident.get("mode") or "sandbox",
        "provenance": ident.get("provenance") or {},
        "started_at": ident.get("started_at"),
        "finished_at": utc_now(),
        "result": result,
        "exit_code": exit_code,
        "reasons": reasons,
        "required_assertions": [format_key(k) for k in required],
        "observed_assertions": observed,
        "step_count": step_count,
        "assertion_count": assertion_count,
        "scope": scope,
        "declared_scope": scope,
        "scope_partial": partial,
    }


def decide_result(
    steps: list[dict[str, Any]],
    required: list[AssertionKey],
) -> tuple[str, list[str]]:
    reasons: list[str] = []
    empty = not steps
    m = mutate()
    if empty and m != "skip_empty_guard":
        reasons.append("pasos vacíos")
        return "FAIL", reasons
    if empty and m == "skip_empty_guard":
        return "PASS", reasons

    missing = missing_required(required, observed_keys(steps))
    if missing and m != "skip_required_assertions":
        reasons.append("aserción omitida: " + ",".join(missing))
        return "FAIL", reasons

    results = [a.get("result") for a in assertions_of(steps) if a.get("result") in RESULTS]
    if not results and required and m != "skip_required_assertions":
        reasons.append("aserción omitida")
        return "FAIL", reasons
    if not results:
        if m == "skip_required_assertions":
            return "PASS", reasons
        reasons.append("sin aserciones observadas")
        return "FAIL", reasons
    result = aggregate([r for r in results if isinstance(r, str)])
    if result == "unknown":
        reasons.append("unknown")
    if result == "FAIL":
        reasons.append("aserción FAIL")
    return result, reasons


def cmd_finalize(args: argparse.Namespace) -> int:
    attempt_dir = Path(args.attempt_dir)
    ident = load_identity(attempt_dir)
    steps = read_steps(attempt_dir)
    required = resolve_required(ident, args.required_assertions)
    result, reasons = decide_result(steps, required)
    summary = build_summary(
        ident,
        steps,
        required,
        reasons,
        result,
        args.scope,
        bool(args.scope_partial),
    )
    write_json(attempt_dir / "summary.json", summary)
    problems = validate_attempt(attempt_dir, apply_mutate=True)
    if problems:
        # Evidencia inválida al cerrar: no fabricar PASS.
        if mutate() not in {
            "skip_empty_guard",
            "skip_required_assertions",
            "lie_counts",
            "exit_summary_mismatch",
            "degrade_fail_to_unknown",
            "skip_redact",
            "skip_case_keys",
            "skip_required_freeze",
            "skip_result_recompute",
        }:
            summary["result"] = "FAIL"
            summary["exit_code"] = 1
            summary["reasons"] = list(summary.get("reasons") or []) + problems
            write_json(attempt_dir / "summary.json", summary)
    print(f"result={summary['result']}")
    print(f"exit_code={summary['exit_code']}")
    if summary.get("scope") == "partial" or summary.get("scope_partial"):
        print("scope=partial")
    return int(summary["exit_code"])


def validate_step(rec: dict[str, Any]) -> list[str]:
    bad: list[str] = []
    if rec.get("schema_version") != SCHEMA_VERSION:
        bad.append("step schema_version")
    if rec.get("type") not in STEP_TYPES:
        bad.append("step type")
    for key in (
        "run_id",
        "attempt_id",
        "feature_id",
        "case_id",
        "step_id",
        "time",
        "mode",
    ):
        if key not in rec:
            bad.append(f"step falta {key}")
    te = rec.get("tool_exit", None)
    if te is not None and not isinstance(te, int):
        bad.append("tool_exit")
    if rec.get("mode") not in MODES:
        bad.append("step mode")
    if rec.get("type") == "assertion":
        if rec.get("result") not in RESULTS:
            bad.append("assertion result")
        if not rec.get("assertion_id"):
            bad.append("assertion_id")
        if "expected" not in rec or "observed" not in rec:
            bad.append("expected/observed")
    return bad


def validate_summary_shape(summary: dict[str, Any]) -> list[str]:
    bad: list[str] = []
    if summary.get("schema_version") != SCHEMA_VERSION and summary.get("version") != SCHEMA_VERSION:
        bad.append("summary version")
    ident = summary.get("identity") or {}
    if not (ident.get("run_id") or summary.get("run_id")):
        bad.append("identity.run_id")
    if summary.get("mode") not in MODES:
        bad.append("mode")
    if summary.get("result") not in RESULTS:
        bad.append("result")
    if "exit_code" not in summary:
        bad.append("exit_code")
    if "provenance" not in summary:
        bad.append("provenance")
    if "required_assertions" not in summary or "observed_assertions" not in summary:
        bad.append("assertion lists")
    return bad


def _identity_id_problems(
    ident: dict[str, Any],
    summary: dict[str, Any],
    steps: list[dict[str, Any]],
) -> list[str]:
    bad: list[str] = []
    sind = summary.get("identity") or {}
    for field in ("run_id", "attempt_id", "feature_id"):
        want = ident.get(field)
        if summary.get(field) != want:
            bad.append(f"summary.{field} != identity")
        if sind.get(field) not in (None, want):
            bad.append(f"summary.identity.{field} != identity")
        for rec in steps:
            if rec.get(field) != want:
                bad.append(f"step {field} != identity")
                break
    ident_cases = [str(c) for c in (ident.get("cases") or [])]
    sum_cases = [str(c) for c in (summary.get("cases") or summary.get("cases_requested") or [])]
    if ident_cases != sum_cases:
        bad.append("cases != identity")
    for rec in steps:
        case_id = str(rec.get("case_id") or "")
        if case_id and case_id not in ident_cases:
            bad.append("step case_id fuera de identity")
            break
    if summary.get("mode") != ident.get("mode"):
        bad.append("summary.mode != identity")
    if summary.get("provenance") != ident.get("provenance"):
        bad.append("summary.provenance != identity")
    for rec in steps:
        if rec.get("mode") != ident.get("mode"):
            bad.append("step mode != identity")
            break
    return bad


def _log_ref_problems(attempt_dir: Path, steps: list[dict[str, Any]]) -> list[str]:
    bad: list[str] = []
    root = attempt_dir.resolve()
    for rec in steps:
        raw = rec.get("log_ref")
        if raw in (None, ""):
            continue
        if not isinstance(raw, str):
            bad.append("log_ref inválido")
            continue
        ref = Path(raw)
        if ref.is_absolute() or ".." in ref.parts:
            bad.append("log_ref fuera del intento")
            continue
        path = attempt_dir / ref
        try:
            path.resolve().relative_to(root)
        except (OSError, ValueError):
            bad.append("log_ref fuera del intento")
            continue
        if path.is_symlink() or not path.is_file():
            bad.append("log_ref ausente o no regular")
    return bad


def validate_attempt(attempt_dir: Path, *, apply_mutate: bool) -> list[str]:
    problems: list[str] = []
    m = mutate() if apply_mutate else ""
    steps = read_steps(attempt_dir)
    summary_path = attempt_dir / "summary.json"
    if not summary_path.is_file():
        return ["falta summary.json"]
    summary = json.loads(summary_path.read_text(encoding="utf-8"))
    problems.extend(validate_summary_shape(summary))
    for rec in steps:
        problems.extend(validate_step(rec))

    try:
        ident = load_identity(attempt_dir)
    except EvidenceError as exc:
        problems.append(str(exc))
        ident = {}

    if ident:
        problems.extend(_identity_id_problems(ident, summary, steps))
    problems.extend(_log_ref_problems(attempt_dir, steps))

    if not steps and m != "skip_empty_guard":
        if summary.get("result") == "PASS" or summary.get("exit_code") == 0:
            problems.append("pasos vacíos con exit 0")

    cases = [str(c) for c in (ident.get("cases") or [])]
    frozen = frozen_required(ident) if ident else []
    sum_req = parse_required_list(
        [str(x) for x in (summary.get("required_assertions") or [])],
        cases,
    )
    req_for_decide = frozen
    if ident and is_availability_channel(frozen, sum_req):
        req_for_decide = sum_req

    if req_for_decide and m != "skip_required_assertions":
        missing = missing_required(req_for_decide, observed_keys(steps))
        if missing and summary.get("result") != "FAIL":
            problems.append("aserción omitida")

    if ident and m != "skip_required_freeze" and not keys_equal(sum_req, req_for_decide):
        problems.append("required_assertions != identity")

    if m != "skip_result_recompute":
        computed, _ = decide_result(steps, req_for_decide)
        if summary.get("result") != computed:
            problems.append("result no deriva de steps")
        if m != "skip_case_keys":
            obs_sum = parse_required_list(
                [str(x) for x in (summary.get("observed_assertions") or [])],
                cases,
            )
            if Counter(observed_keys(steps)) != Counter(obs_sum):
                problems.append("observed_assertions no deriva de steps")

    real_steps = len(steps)
    real_asrt = len(assertions_of(steps))
    if m != "lie_counts":
        if summary.get("step_count") != real_steps:
            problems.append("conteos falsos (steps)")
        if summary.get("assertion_count") != real_asrt:
            problems.append("conteos falsos (assertions)")

    result = summary.get("result")
    exit_code = summary.get("exit_code")
    if m != "exit_summary_mismatch":
        if result in EXIT_FOR and exit_code != EXIT_FOR[result]:
            problems.append("incoherencia exit/resumen")

    if m != "degrade_fail_to_unknown":
        step_results = [a.get("result") for a in assertions_of(steps)]
        if "FAIL" in step_results and result == "unknown":
            problems.append("FAIL degradado a unknown")

    if m != "skip_redact":
        for p in sorted(attempt_dir.rglob("*")):
            if not p.is_file():
                continue
            try:
                text = p.read_text(encoding="utf-8", errors="replace")
            except OSError:
                continue
            if contains_secret(text):
                problems.append(f"secreto sintético en {p.name}")
    return problems


def cmd_validate(args: argparse.Namespace) -> int:
    attempt_dir = Path(args.attempt_dir)
    problems = validate_attempt(attempt_dir, apply_mutate=True)
    if problems:
        for p in problems:
            print(p, file=sys.stderr)
        return 1
    print("validate: OK")
    return 0


def cmd_redact(args: argparse.Namespace) -> int:
    print(redact_text(args.text), end="" if args.text.endswith("\n") else "\n")
    return 0


def cmd_redact_file(args: argparse.Namespace) -> int:
    path = Path(args.path)
    text = path.read_text(encoding="utf-8", errors="replace")
    path.write_text(redact_text(text), encoding="utf-8")
    return 0


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    sub = ap.add_subparsers(dest="cmd", required=True)

    p = sub.add_parser("create-attempt")
    p.add_argument("--artifacts", required=True)
    p.add_argument("--run-id", required=True)
    p.add_argument("--feature-id", required=True)
    p.add_argument("--repo", default="")
    p.add_argument("--mode", default="sandbox", choices=MODES)
    p.add_argument("--cases", default="")
    p.add_argument("--required-assertions", default="")
    p.add_argument("--scope", default="full")
    p.add_argument("--scope-partial", action="store_true")
    p.set_defaults(func=cmd_create_attempt)

    p = sub.add_parser("append-step")
    p.add_argument("--attempt-dir", required=True)
    p.add_argument("--type", required=True, choices=STEP_TYPES)
    p.add_argument("--case-id", default="")
    p.add_argument("--step-id", default="")
    p.add_argument("--command", action="append", default=[])
    p.add_argument("--tool-exit", default=None)
    p.add_argument("--observation", default=None)
    p.add_argument("--log-ref", default=None)
    p.add_argument("--assertion-id", default="")
    p.add_argument("--expected", default=None)
    p.add_argument("--observed", default=None)
    p.add_argument("--result", default=None, choices=RESULTS)
    p.set_defaults(func=cmd_append_step)

    p = sub.add_parser("finalize")
    p.add_argument("--attempt-dir", required=True)
    p.add_argument("--required-assertions", default="")
    p.add_argument("--scope", default="")
    p.add_argument("--scope-partial", action="store_true")
    p.set_defaults(func=cmd_finalize)

    p = sub.add_parser("validate")
    p.add_argument("--attempt-dir", required=True)
    p.set_defaults(func=cmd_validate)

    p = sub.add_parser("redact")
    p.add_argument("--text", required=True)
    p.set_defaults(func=cmd_redact)

    p = sub.add_parser("redact-file")
    p.add_argument("--path", required=True)
    p.set_defaults(func=cmd_redact_file)

    args = ap.parse_args(argv)
    try:
        return int(args.func(args))
    except EvidenceError as e:
        print(f"evidence: {e}", file=sys.stderr)
        return 1
    except (OSError, json.JSONDecodeError, ValueError) as e:
        print(f"evidence: {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
