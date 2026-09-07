#!/usr/bin/env python3
"""Doctor granular del feature map (19.5).

Aislamiento global; binarios, fixtures, PTY y acceso externo por
dependencia. MISSING/BLOCKED viven bajo unknown. Corrupción observada
es FAIL. Un gh falso no acredita modo live. Doctor no llama APIs ni
lee perfiles vivos del operador.

Mutaciones (SAIKIT_VERIFY_MUTATE / --mutate):
  local_miss_global — una falta local se aplica a todas las features
  blocked_as_pass   — BLOCKED se presenta como PASS
  fake_gh_as_live   — un gh script acredita acceso vivo
  skip_isolation    — omite la guarda de escape
"""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Any

SCHEMA_VERSION = 1
RANK = {"PASS": 0, "unknown": 1, "FAIL": 2}
EXIT_FOR = {"PASS": 0, "FAIL": 1, "unknown": 3}
# Catalog `blocked` is inventoried (listed in `blocked`) but does not fail
# the local doctor aggregate. Live merge stays Optional (19.16).
ACTIVE_STATUSES = frozenset({"active"})

def mutate_of(explicit: str | None) -> str:
    return (explicit or os.environ.get("SAIKIT_VERIFY_MUTATE") or "").strip()


def load_state_mod():
    path = Path(__file__).resolve().with_name("state.py")
    spec = importlib.util.spec_from_file_location("saikit_fm_state", path)
    if spec is None or spec.loader is None:
        raise RuntimeError("no se pudo cargar state.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def is_escape_reason(msg: str) -> bool:
    m = msg.lower()
    return any(
        tok in m
        for tok in (
            "escape",
            "symlink",
            "enlace",
            "..",
            "físic",
            "fisic",
            "metacar",
        )
    )


def which(name: str) -> Path | None:
    for d in os.environ.get("PATH", "").split(os.pathsep):
        if not d:
            continue
        cand = Path(d) / name
        try:
            if cand.is_file() and os.access(cand, os.X_OK):
                return cand
        except OSError:
            continue
    return None


def gh_version(path: Path) -> str:
    env = {
        "PATH": os.environ.get("PATH", ""),
        "HOME": os.environ.get("HOME", ""),
        "LC_ALL": "C",
        "TERM": "dumb",
    }
    try:
        r = subprocess.run(
            [str(path), "--version"],
            capture_output=True,
            text=True,
            timeout=3,
            env=env,
            check=False,
        )
    except (OSError, subprocess.TimeoutExpired):
        return ""
    return ((r.stdout or "") + (r.stderr or "")).strip()


def is_official_gh(path: Path | None, mutate: str) -> bool:
    if path is None:
        return False
    if mutate == "fake_gh_as_live":
        return True
    try:
        head = path.read_bytes()[:80]
    except OSError:
        return False
    if head.startswith(b"#!"):
        return False
    return bool(re.search(r"(?m)^gh version \d+", gh_version(path)))


def pty_available() -> bool:
    if os.environ.get("SAIKIT_VERIFY_PTY") == "missing":
        return False
    try:
        master, slave = os.openpty()
        os.close(master)
        os.close(slave)
        return True
    except (OSError, AttributeError):
        return False


def sha256_file(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def parse_requirement(item: Any) -> dict[str, Any]:
    if isinstance(item, dict):
        return dict(item)
    if not isinstance(item, str):
        return {"kind": "opaque", "raw": str(item)}
    if item == "doctor":
        return {"kind": "instance"}
    if item.startswith("fixtures/") or item == "fixtures/escenarios":
        rel = item if item.startswith("tests/") else f"tests/{item}"
        return {"kind": "fixture", "path": rel}
    if item == "pty":
        return {"kind": "pty"}
    if item in ("gh", "gh:live"):
        return {"kind": "binary", "name": "gh", "access": "live"}
    if item == "gh:simulated":
        return {"kind": "binary", "name": "gh", "access": "simulated"}
    if item == "live_authorization":
        return {"kind": "live_authorization"}
    return {"kind": "local_file", "path": item}


def load_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def collect_requirements(
    fid: str, meta: dict[str, Any], desc: dict[str, Any] | None
) -> list[dict[str, Any]]:
    raw: list[Any] = []
    if desc:
        raw.extend(desc.get("requirements") or [])
        for surf in desc.get("surfaces") or []:
            if isinstance(surf, str) and surf:
                raw.append({"kind": "local_tool", "path": surf})
    raw.extend(meta.get("requirements") or [])
    out: list[dict[str, Any]] = []
    seen: set[tuple[Any, ...]] = set()
    for item in raw:
        req = parse_requirement(item)
        key = (
            req.get("kind"),
            req.get("path"),
            req.get("name"),
            req.get("access"),
            tuple(req.get("affects_cases") or ()),
        )
        if key in seen:
            continue
        seen.add(key)
        out.append(req)
    return out


def collect_cases(
    meta: dict[str, Any], desc: dict[str, Any] | None
) -> list[dict[str, Any]]:
    if desc and desc.get("cases"):
        return [dict(c) for c in desc["cases"] if isinstance(c, dict)]
    return [dict(c) for c in (meta.get("cases") or []) if isinstance(c, dict)]


def feature_mode(fid: str, meta: dict[str, Any], desc: dict[str, Any] | None) -> str:
    if desc and desc.get("execution_mode"):
        return str(desc["execution_mode"])
    if meta.get("execution_mode"):
        return str(meta["execution_mode"])
    if fid == "merge-happy-path":
        return "live"
    if fid in {"saikit-merge", "saikit-postmerge"}:
        return "simulated"
    return "sandbox"


def req_result(
    *,
    result: str,
    availability: str,
    reason: str,
    **extra: Any,
) -> dict[str, Any]:
    row = {
        "result": result,
        "availability": availability,
        "reason": reason,
    }
    row.update(extra)
    return row


def eval_instance(state: dict[str, Any] | None, repo: Path) -> dict[str, Any]:
    if not state:
        return req_result(
            kind="instance",
            result="unknown",
            availability="MISSING",
            reason="sin instancia — launch faltante",
        )
    dest = Path(str(state.get("dest") or ""))
    home = Path(str(state.get("verify_home") or ""))
    if not dest.is_file():
        return req_result(
            kind="instance",
            result="unknown",
            availability="MISSING",
            reason="hook not prepared at DEST; run a hook-dependent drive",
        )
    try:
        head = dest.read_text(encoding="utf-8", errors="replace").splitlines()[:4]
    except OSError as e:
        return req_result(
            kind="instance",
            result="FAIL",
            availability="failed",
            reason=f"DEST ilegible: {e}",
        )
    if not any("SAIKIT-CLAUDE-OWNED" in ln for ln in head):
        return req_result(
            kind="instance",
            result="FAIL",
            availability="failed",
            reason="ownership marker missing",
        )
    n = subprocess.run(
        ["bash", "-n", str(dest)], capture_output=True, text=True, check=False
    )
    if n.returncode != 0:
        return req_result(
            kind="instance",
            result="FAIL",
            availability="failed",
            reason="bash -n failed",
        )
    src = repo / "hooks" / "summonaikit-harness.sh"
    if src.is_file():
        try:
            if sha256_file(src) != sha256_file(dest):
                return req_result(
                    kind="instance",
                    result="FAIL",
                    availability="failed",
                    reason="DEST no coincide con el fuente del repo",
                )
        except OSError as e:
            return req_result(
                kind="instance",
                result="FAIL",
                availability="failed",
                reason=f"no se pudo hashear DEST: {e}",
            )
    try:
        dest.resolve().relative_to(home.resolve())
    except (ValueError, OSError):
        return req_result(
            kind="instance",
            result="FAIL",
            availability="failed",
            reason="DEST is not under VERIFY_HOME",
        )
    return req_result(
        kind="instance", result="PASS", availability="ready", reason="instancia propia"
    )


def eval_fixture(repo: Path, rel: str) -> dict[str, Any]:
    root = repo / rel
    if not root.is_dir():
        return req_result(
            kind="fixture",
            path=rel,
            result="unknown",
            availability="MISSING",
            reason=f"fixture ausente: {rel}",
        )
    for p in sorted(root.rglob("*")):
        if not p.is_file() or p.name == ".DS_Store":
            continue
        if p.suffix != ".json":
            continue
        try:
            json.loads(p.read_text(encoding="utf-8"))
        except json.JSONDecodeError as e:
            return req_result(
                kind="fixture",
                path=rel,
                result="FAIL",
                availability="failed",
                reason=f"fixture corrupto (JSON mal formado): {p.relative_to(repo)}: {e}",
            )
        except OSError as e:
            return req_result(
                kind="fixture",
                path=rel,
                result="FAIL",
                availability="failed",
                reason=f"fixture ilegible: {p}: {e}",
            )
    return req_result(
        kind="fixture", path=rel, result="PASS", availability="ready", reason="fixture ok"
    )


def eval_local_path(repo: Path, rel: str, kind: str) -> dict[str, Any]:
    path = repo / rel
    if not path.exists():
        return req_result(
            kind=kind,
            path=rel,
            result="unknown",
            availability="MISSING",
            reason=f"{rel} ausente",
        )
    if path.suffix == ".json":
        try:
            json.loads(path.read_text(encoding="utf-8"))
        except json.JSONDecodeError as e:
            return req_result(
                kind=kind,
                path=rel,
                result="FAIL",
                availability="failed",
                reason=f"JSON mal formado: {rel}: {e}",
            )
        except OSError as e:
            return req_result(
                kind=kind,
                path=rel,
                result="FAIL",
                availability="failed",
                reason=f"ilegible: {rel}: {e}",
            )
    return req_result(
        kind=kind, path=rel, result="PASS", availability="ready", reason=f"{rel} ok"
    )


def eval_gh(access: str, mutate: str) -> dict[str, Any]:
    path = which("gh")
    if access == "simulated":
        return req_result(
            kind="binary",
            name="gh",
            access="simulated",
            result="PASS",
            availability="ready",
            reason="gh simulado no exige binario vivo",
        )
    if path is None:
        return req_result(
            kind="binary",
            name="gh",
            access="live",
            result="unknown",
            availability="MISSING",
            reason="gh ausente — solo afecta modo live",
        )
    if not is_official_gh(path, mutate):
        return req_result(
            kind="binary",
            name="gh",
            access="live",
            result="unknown",
            availability="MISSING",
            reason="gh falso no acredita acceso vivo",
        )
    return req_result(
        kind="binary",
        name="gh",
        access="live",
        result="PASS",
        availability="ready",
        reason="gh oficial presente (sin sondear cuota)",
    )


def eval_pty() -> dict[str, Any]:
    if pty_available():
        return req_result(
            kind="pty", result="PASS", availability="ready", reason="PTY disponible"
        )
    return req_result(
        kind="pty",
        result="unknown",
        availability="MISSING",
        reason="PTY ausente — solo casos interactivos",
    )


def eval_live_auth() -> dict[str, Any]:
    dest = (os.environ.get("SAIKIT_LIVE_DEST") or "").strip()
    auth = (os.environ.get("SAIKIT_LIVE_AUTH") or "").strip()
    parts: list[str] = []
    if not auth:
        parts.append("sin autorización viva")
    if not dest:
        parts.append("sin destino concreto")
    if auth and dest:
        parts.append("autorización/destino presentes no ejecutan merge vivo")
    return req_result(
        kind="live_authorization",
        result="unknown",
        availability="BLOCKED",
        reason="; ".join(parts) + " (19.16)",
    )


def evaluate_req(
    req: dict[str, Any],
    *,
    repo: Path,
    state: dict[str, Any] | None,
    mutate: str,
) -> dict[str, Any]:
    kind = req.get("kind") or "opaque"
    out = dict(req)
    if kind == "instance":
        got = eval_instance(state, repo)
    elif kind == "fixture":
        got = eval_fixture(repo, str(req.get("path") or "tests/fixtures/escenarios"))
    elif kind == "local_file":
        got = eval_local_path(repo, str(req.get("path") or ""), "local_file")
    elif kind == "local_tool":
        got = eval_local_path(repo, str(req.get("path") or ""), "local_tool")
    elif kind == "binary" and req.get("name") == "gh":
        got = eval_gh(str(req.get("access") or "live"), mutate)
    elif kind == "pty":
        got = eval_pty()
    elif kind == "live_authorization":
        got = eval_live_auth()
    else:
        got = req_result(
            kind=kind,
            result="unknown",
            availability="MISSING",
            reason=f"requisito no evaluable: {kind}",
        )
    out.update(got)
    if mutate == "blocked_as_pass" and out.get("availability") == "BLOCKED":
        out["result"] = "PASS"
        out["availability"] = "ready"
        out["reason"] = (out.get("reason") or "") + " (mutated blocked_as_pass)"
    return out


def worse(a: str, b: str) -> str:
    if RANK.get(a, 0) >= RANK.get(b, 0):
        return a
    return b


def avail_for(result: str, fallback: str) -> str:
    if result == "FAIL":
        return "failed"
    if result == "unknown":
        return fallback if fallback in {"MISSING", "BLOCKED"} else "MISSING"
    return "ready"


def apply_req_to_result(current: str, req: dict[str, Any]) -> str:
    return worse(current, str(req.get("result") or "unknown"))


def evaluate_feature(
    fid: str,
    meta: dict[str, Any],
    desc: dict[str, Any] | None,
    *,
    repo: Path,
    state: dict[str, Any] | None,
    mutate: str,
    isolation_fail: str | None,
) -> dict[str, Any]:
    status = str(meta.get("status") or "active")
    mode = feature_mode(fid, meta, desc)
    reqs = [
        evaluate_req(r, repo=repo, state=state, mutate=mutate)
        for r in collect_requirements(fid, meta, desc)
    ]
    cases_out: dict[str, Any] = {}
    feat_result = "PASS"
    feat_avail = "ready"
    reasons: list[str] = []

    if isolation_fail:
        feat_result = "FAIL"
        feat_avail = "failed"
        reasons.append(isolation_fail)
        for r in reqs:
            r["result"] = "FAIL"
            r["availability"] = "failed"
            r["reason"] = isolation_fail

    for req in reqs:
        if req.get("affects_cases"):
            continue
        feat_result = apply_req_to_result(feat_result, req)
        if req.get("availability") in {"MISSING", "BLOCKED"} and feat_avail == "ready":
            feat_avail = str(req["availability"])
        if req.get("result") != "PASS" and req.get("reason"):
            reasons.append(str(req["reason"]))

    for case in collect_cases(meta, desc):
        cid = str(case.get("id") or "")
        if not cid:
            continue
        c_result = "PASS"
        c_avail = "ready"
        c_reasons: list[str] = []
        for req in reqs:
            affects = list(req.get("affects_cases") or [])
            if isolation_fail:
                applies = True
            elif affects:
                applies = cid in affects
            else:
                applies = True
            if not applies:
                continue
            c_result = apply_req_to_result(c_result, req)
            if req.get("availability") in {"MISSING", "BLOCKED"} and c_avail == "ready":
                c_avail = str(req["availability"])
            if req.get("result") != "PASS" and req.get("reason"):
                c_reasons.append(str(req["reason"]))
        if isolation_fail:
            c_result = "FAIL"
            c_avail = "failed"
        c_avail = avail_for(c_result, c_avail)
        cases_out[cid] = {
            "id": cid,
            "result": c_result,
            "availability": c_avail,
            "reason": "; ".join(c_reasons),
        }
        feat_result = worse(feat_result, c_result)
        if c_avail in {"MISSING", "BLOCKED"} and feat_avail == "ready":
            feat_avail = c_avail

    feat_avail = avail_for(feat_result, feat_avail)
    return {
        "id": fid,
        "status": status,
        "result": feat_result,
        "availability": feat_avail,
        "reason": "; ".join(reasons),
        "mode": mode,
        "requirements": reqs,
        "cases": cases_out,
    }


def apply_local_miss_global(features: dict[str, Any]) -> None:
    misses: list[dict[str, Any]] = []
    for feat in features.values():
        for req in feat.get("requirements") or []:
            if req.get("availability") == "MISSING" and req.get("kind") in {
                "binary",
                "pty",
            }:
                misses.append(dict(req))
    if not misses:
        return
    for feat in features.values():
        existing = feat.setdefault("requirements", [])
        have = {
            (r.get("kind"), r.get("name"), r.get("access"))
            for r in existing
        }
        for miss in misses:
            key = (miss.get("kind"), miss.get("name"), miss.get("access"))
            if key in have:
                continue
            clone = dict(miss)
            clone["reason"] = (clone.get("reason") or "") + " (mutated local_miss_global)"
            existing.append(clone)
            have.add(key)
            feat["result"] = worse(str(feat.get("result") or "PASS"), "unknown")
            if feat.get("availability") == "ready":
                feat["availability"] = "MISSING"
            extra = clone.get("reason") or ""
            if extra and extra not in (feat.get("reason") or ""):
                feat["reason"] = (
                    f"{feat['reason']}; {extra}" if feat.get("reason") else extra
                )


def check_isolation(
    state_mod: Any,
    state_dir: Path,
    artifacts: Path,
    repo: Path,
    mutate: str,
) -> tuple[dict[str, Any], dict[str, Any] | None, bool]:
    skip = mutate == "skip_isolation"
    iso_mutate = "skip_physical_path" if skip else mutate
    try:
        state_mod.reject_legacy(state_dir)
    except state_mod.StateError as e:
        return {"result": "FAIL", "reason": str(e)}, None, False
    try:
        state_mod.assert_assigned(str(state_dir), "STATE", mutate=iso_mutate)
        state_mod.assert_assigned(str(artifacts), "artifacts", mutate=iso_mutate)
    except state_mod.StateError as e:
        if skip:
            return {"result": "PASS", "reason": "skip_isolation"}, None, True
        return {"result": "FAIL", "reason": str(e)}, None, False

    path = state_dir / "state.json"
    if not path.is_file():
        return {"result": "PASS", "reason": ""}, None, True
    artifacts_safe = False
    try:
        data = state_mod.load_json_file(path)
        if isinstance(data, dict):
            state_mod.assert_assignment(
                state_dir,
                artifacts,
                str(data.get("run_id") or ""),
                str(data.get("token") or ""),
                "artifacts_dir",
            )
            artifacts_safe = True
        data = state_mod.validate_payload(
            data,
            state_dir=state_dir,
            artifacts=artifacts,
            repo=repo,
            mutate=iso_mutate,
            mode="doctor",
        )
    except state_mod.StateError as e:
        msg = str(e)
        if skip and is_escape_reason(msg):
            return {"result": "PASS", "reason": "skip_isolation"}, None, True
        return {"result": "FAIL", "reason": msg}, None, artifacts_safe
    return {"result": "PASS", "reason": ""}, data, True


def write_doctor_json(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, raw_tmp = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    tmp = Path(raw_tmp)
    try:
        os.fchmod(fd, 0o600)
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            fd = -1
            fh.write(json.dumps(payload, indent=2, ensure_ascii=False) + "\n")
            fh.flush()
            os.fsync(fh.fileno())
        os.replace(tmp, path)
    finally:
        if fd >= 0:
            os.close(fd)
        try:
            tmp.unlink()
        except FileNotFoundError:
            pass


def human_report(payload: dict[str, Any]) -> None:
    iso = payload.get("isolation") or {}
    print(f"doctor: isolation={iso.get('result', 'unknown')}")
    if iso.get("reason"):
        print(f"doctor: isolation — {iso['reason']}")
    for fid, feat in (payload.get("features") or {}).items():
        avail = feat.get("availability") or feat.get("result")
        reason = feat.get("reason") or ""
        line = f"doctor: {fid} {avail}"
        if reason:
            line += f" — {reason}"
        print(line)
        for cid, case in (feat.get("cases") or {}).items():
            extra = case.get("reason") or ""
            cl = f"doctor:   case {cid} {case.get('availability')}"
            if extra:
                cl += f" — {extra}"
            print(cl)
    print(f"doctor: {payload.get('result', 'unknown')}")


def run(args: argparse.Namespace) -> int:
    mutate = mutate_of(args.mutate)
    skill = Path(args.skill).resolve()
    repo = Path(args.repo).resolve()
    state_dir = Path(args.state_dir)
    artifacts = Path(args.artifacts)
    scope = args.feature_id or ""

    catalog_path = skill / "features" / "catalog.json"
    catalog = load_json(catalog_path)
    features_meta: dict[str, Any] = catalog.get("features") or {}
    if scope and scope not in features_meta:
        print(f"control-summonaikit: feature desconocida: {scope}", file=sys.stderr)
        return 1

    state_mod = load_state_mod()
    isolation, state, artifacts_safe = check_isolation(
        state_mod, state_dir, artifacts, repo, mutate
    )
    isolation_fail = (
        isolation["reason"] if isolation.get("result") == "FAIL" else None
    )
    if isolation_fail:
        print(f"control-summonaikit: {isolation_fail}", file=sys.stderr)

    wanted = [scope] if scope else list(features_meta)
    features: dict[str, Any] = {}
    for fid in wanted:
        meta = features_meta.get(fid) or {}
        desc_path = skill / "features" / f"{fid}.json"
        desc = None
        if desc_path.is_file():
            try:
                desc = load_json(desc_path)
            except (OSError, json.JSONDecodeError) as e:
                features[fid] = {
                    "id": fid,
                    "status": meta.get("status") or "active",
                    "result": "FAIL",
                    "availability": "failed",
                    "reason": f"descriptor corrupto: {e}",
                    "mode": feature_mode(fid, meta, None),
                    "requirements": [],
                    "cases": {},
                }
                continue
        features[fid] = evaluate_feature(
            fid,
            meta,
            desc,
            repo=repo,
            state=state,
            mutate=mutate,
            isolation_fail=isolation_fail,
        )

    if mutate == "local_miss_global" and not isolation_fail:
        apply_local_miss_global(features)

    ready: list[str] = []
    blocked: list[str] = []
    failed: list[str] = []
    for fid, feat in features.items():
        if feat["result"] == "FAIL" or feat["availability"] == "failed":
            failed.append(fid)
        elif feat["availability"] in {"MISSING", "BLOCKED"} or feat["result"] == "unknown":
            blocked.append(fid)
        else:
            ready.append(fid)

    # Agregado de salida: features activas (o el id pedido).
    if scope:
        agg_ids = [scope]
    else:
        agg_ids = [
            fid
            for fid, meta in features_meta.items()
            if (meta.get("status") or "active") in ACTIVE_STATUSES
        ]
    overall = "PASS"
    for fid in agg_ids:
        feat = features.get(fid)
        if not feat:
            continue
        overall = worse(overall, str(feat.get("result") or "unknown"))
    if isolation_fail:
        overall = "FAIL"

    payload = {
        "schema_version": SCHEMA_VERSION,
        "isolation": isolation,
        "features": features,
        "ready": ready,
        "blocked": blocked,
        "failed": failed,
        "result": overall,
        "exit_code": EXIT_FOR[overall],
        "scope": scope or "all",
    }
    if artifacts_safe:
        try:
            write_doctor_json(artifacts / "doctor.json", payload)
        except OSError as e:
            print(f"control-summonaikit: no se pudo escribir doctor.json: {e}", file=sys.stderr)
            return 1
    human_report(payload)
    return int(payload["exit_code"])


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--skill", required=True)
    ap.add_argument("--repo", required=True)
    ap.add_argument("--state-dir", required=True)
    ap.add_argument("--artifacts", required=True)
    ap.add_argument("--feature-id", default="")
    ap.add_argument("--mutate", default="")
    args = ap.parse_args(argv)
    try:
        return run(args)
    except (OSError, json.JSONDecodeError) as e:
        print(f"control-summonaikit: doctor: {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
