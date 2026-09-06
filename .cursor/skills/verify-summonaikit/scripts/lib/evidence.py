#!/usr/bin/env python3
"""Evidencia v1 por intento exclusivo (feature map, task 19.3).

CLI: create-attempt, append-step, finalize, validate, redact, redact-file.
Mutaciones (SAIKIT_VERIFY_MUTATE): skip_empty_guard, skip_required_assertions,
lie_counts, exit_summary_mismatch, degrade_fail_to_unknown, skip_redact,
reuse_attempt_id.
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
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

SCHEMA_VERSION = 1
RESULTS = ("PASS", "FAIL", "unknown")
STEP_TYPES = ("action", "assertion", "diagnostic")
MODES = ("sandbox", "simulated", "live")
RANK = {"PASS": 0, "unknown": 1, "FAIL": 2}
EXIT_FOR = {"PASS": 0, "FAIL": 1, "unknown": 3}

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


def contains_secret(text: str) -> bool:
    return bool(_SCAN_RE.search(text))


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
    return json.loads(p.read_text(encoding="utf-8"))


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
    run_id = args.run_id
    feature_id = args.feature_id
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
    cases = split_words(args.cases)
    required = split_words(args.required_assertions)
    ident = {
        "schema_version": SCHEMA_VERSION,
        "run_id": run_id,
        "attempt_id": attempt_id,
        "feature_id": feature_id,
        "mode": args.mode,
        "cases": cases,
        "required_assertions": required,
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
    required: list[str],
    reasons: list[str],
    result: str,
    extra_scope: str | None,
    scope_partial: bool,
) -> dict[str, Any]:
    observed = [a.get("assertion_id") for a in assertions_of(steps) if a.get("assertion_id")]
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
        "required_assertions": required,
        "observed_assertions": observed,
        "step_count": step_count,
        "assertion_count": assertion_count,
        "scope": scope,
        "declared_scope": scope,
        "scope_partial": partial,
    }


def decide_result(
    steps: list[dict[str, Any]],
    required: list[str],
) -> tuple[str, list[str]]:
    reasons: list[str] = []
    empty = not steps
    m = mutate()
    if empty and m != "skip_empty_guard":
        reasons.append("pasos vacíos")
        return "FAIL", reasons
    if empty and m == "skip_empty_guard":
        return "PASS", reasons

    observed = {a.get("assertion_id") for a in assertions_of(steps) if a.get("assertion_id")}
    missing = [r for r in required if r not in observed]
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
    required = split_words(args.required_assertions) or list(ident.get("required_assertions") or [])
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

    if not steps and m != "skip_empty_guard":
        if summary.get("result") == "PASS" or summary.get("exit_code") == 0:
            problems.append("pasos vacíos con exit 0")

    required = list(summary.get("required_assertions") or [])
    observed = set(summary.get("observed_assertions") or [])
    if required and m != "skip_required_assertions":
        missing = [r for r in required if r not in observed]
        if missing and summary.get("result") != "FAIL":
            problems.append("aserción omitida")

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
