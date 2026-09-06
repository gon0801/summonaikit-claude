#!/usr/bin/env python3
"""Lint the verify-summonaikit feature map (catalog, descriptors, cards).

Exit 0 when the map is coherent; 1 on contract violations; 2 on usage/IO.
Discovery walks the declared roots and compares them to catalog entries —
it does not trust a static list alone.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any

SCHEMA_VERSION = 1
REQUIRED_H2 = [
    "Sub-features",
    "How to get to it (user POV)",
    "Driving it with control-summonaikit",
    "Gotchas",
]
CASE_RE = re.compile(
    r"Case\s+`([^`]+)`:\s*action\s+([^;]+);\s*command\s+`([^`]+)`;\s*observable\s+(.+)",
    re.IGNORECASE,
)
LEGACY_ALLOWED = {
    "install-guardian",
    "gate-turn",
    "audit-ledger",
    "check-deploy-log",
}


class LintError(Exception):
    pass


def err(msg: str) -> None:
    print(f"feature-map: {msg}", file=sys.stderr)


def load_json(path: Path, *, accept_bad: bool = False) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as e:
        if accept_bad:
            return {"__bad_json__": True, "path": str(path)}
        raise LintError(f"JSON mal formado en {path}: {e}") from e
    except OSError as e:
        raise LintError(f"no se pudo leer {path}: {e}") from e


def skill_rel_allowed(
    rel: str,
    *,
    features_meta: dict[str, Any],
    helpers: dict[str, Any],
) -> bool:
    """Files that may exist under the versioned skill tree.

    Prefijos abiertos (lib/**, features/*.json) no bastan: cada archivo debe
    estar inventariado en helpers / features del catálogo.
    """
    if rel.startswith("artifacts/") or rel.startswith(".run/"):
        return False
    if "__pycache__" in rel.split("/") or rel.endswith(".pyc"):
        return False
    if rel == "SKILL.md":
        return True
    if rel == "scripts/control-summonaikit":
        return True
    if rel == "scripts/lint-feature-map.py":
        return True
    if rel in helpers:
        return True
    if rel.startswith("scripts/lib/"):
        # solo helpers clasificados (arriba); basura bajo lib/ no pasa
        return False
    if rel.startswith("scripts/drivers/") and rel.endswith(".sh"):
        # presencia permitida; huérfanos se juzgan aparte contra executors
        return True
    if rel == "features/README.md" or rel == "features/catalog.json":
        return True
    if rel.startswith("features/") and rel.endswith(".md"):
        stem = Path(rel).stem
        meta = features_meta.get(stem)
        if not meta:
            return False
        card = meta.get("card")
        if not card:
            return False
        return Path(card).name == Path(rel).name or card == rel
    if rel.startswith("features/") and rel.endswith(".json"):
        stem = Path(rel).stem
        meta = features_meta.get(stem)
        if not meta:
            return False
        # pending no finge descriptor versionado
        return meta.get("status", "active") in {"active", "blocked"}
    return False


def skill_dir_from_args(repo: Path, skill: Path | None) -> Path:
    if skill is not None:
        return skill
    return repo / ".cursor" / "skills" / "verify-summonaikit"


def discover_from_roots(repo: Path, roots: list[dict[str, Any]] | None) -> set[str]:
    """Discover public surfaces from catalog.roots (fallback to built-in)."""
    if not roots:
        return discover_tools_and_trees(repo)
    found: set[str] = set()
    for root in roots:
        rel = root.get("path", "")
        kind = root.get("kind", "dir")
        base = repo / rel
        if not base.exists():
            continue
        if kind == "tools_exec":
            if not base.is_dir():
                continue
            for p in base.iterdir():
                if p.name == "lib" and p.is_dir():
                    for lib in p.iterdir():
                        if lib.is_file():
                            found.add(lib.relative_to(repo).as_posix())
                    continue
                if p.is_file():
                    found.add(p.relative_to(repo).as_posix())
        elif kind == "dir":
            if not base.is_dir():
                continue
            for p in base.rglob("*"):
                if p.is_file() and ".git" not in p.parts:
                    found.add(p.relative_to(repo).as_posix())
        else:
            raise LintError(f"root.kind desconocido: {kind} ({rel})")
    return found


def discover_tools_and_trees(repo: Path) -> set[str]:
    """Fallback discovery matching the Phase 19 root contract."""
    return discover_from_roots(
        repo,
        [
            {"path": "tools", "kind": "tools_exec"},
            {"path": "hooks", "kind": "dir"},
            {"path": "hosts", "kind": "dir"},
            {"path": "skills", "kind": "dir"},
            {"path": "agents", "kind": "dir"},
            {"path": "recetas", "kind": "dir"},
        ],
    )


def parse_card(path: Path) -> dict[str, Any]:
    text = path.read_text(encoding="utf-8")
    lines = text.splitlines()
    if not lines or not lines[0].startswith("# "):
        raise LintError(f"{path}: falta H1")
    h2 = [ln[3:].strip() for ln in lines if ln.startswith("## ")]
    if h2 != REQUIRED_H2:
        raise LintError(
            f"{path}: H2 fuera de orden o incompletos; "
            f"esperado {REQUIRED_H2}, obtenido {h2}"
        )
    if "Preconditions:" not in text and "Preconditions:" not in text.replace(
        "Preconditions:\n", "Preconditions:"
    ):
        # accept "Preconditions:" as its own line after Driving H2
        if not re.search(r"(?m)^Preconditions:\s*$", text) and "Preconditions:" not in text:
            raise LintError(f"{path}: falta Preconditions: en la sección de ejecución")
    cases = []
    for m in CASE_RE.finditer(text):
        cases.append(
            {
                "id": m.group(1).strip(),
                "action": m.group(2).strip(),
                "command": m.group(3).strip(),
                "observable": m.group(4).strip(),
            }
        )
    if not cases:
        raise LintError(f"{path}: ningún Case `id`: action/command/observable (triple incompleto)")
    for c in cases:
        if not c["id"] or not c["action"] or not c["command"] or not c["observable"]:
            raise LintError(f"{path}: triple incompleto en caso {c!r}")
    return {"cases": cases, "h2": h2}


def validate_legacy_executor(
    skill: Path, feature_id: str, executor: dict[str, Any], mutate: str | None
) -> None:
    if executor.get("kind") != "legacy":
        raise LintError(f"{feature_id}: executor.kind debe ser legacy en 19.1")
    if feature_id not in LEGACY_ALLOWED:
        raise LintError(f"{feature_id}: legacy solo permitido para {sorted(LEGACY_ALLOWED)}")
    command = executor.get("command")
    function = executor.get("function")
    if not command or not function:
        raise LintError(f"{feature_id}: legacy exige command y function")
    ctrl = skill / "scripts" / "control-summonaikit"
    if not ctrl.is_file():
        raise LintError("falta scripts/control-summonaikit")
    body = ctrl.read_text(encoding="utf-8")
    if mutate == "skip_legacy_validate":
        return
    if f"{function}()" not in body and not re.search(
        rf"(?m)^{re.escape(function)}\(\)", body
    ):
        raise LintError(
            f"{feature_id}: function legacy {function} no existe en control-summonaikit"
        )
    # command is the CLI verb; must appear in the dispatcher
    if command not in body:
        raise LintError(
            f"{feature_id}: command legacy {command!r} no aparece en control-summonaikit"
        )


def lint(repo: Path, skill: Path, mutate: str | None = None) -> int:
    catalog_path = skill / "features" / "catalog.json"
    if not catalog_path.is_file():
        err(f"falta {catalog_path}")
        return 1
    accept_bad = mutate == "accept_bad_json"
    catalog = load_json(catalog_path, accept_bad=accept_bad)
    if isinstance(catalog, dict) and catalog.get("__bad_json__"):
        # mutation: pretend malformed catalog is acceptable
        print("feature-map: OK (mutate accept_bad_json)")
        return 0
    if catalog.get("schema_version") != SCHEMA_VERSION:
        err(f"catalog schema_version debe ser {SCHEMA_VERSION}")
        return 1

    classifications: dict[str, Any] = catalog.get("surfaces") or {}
    exclusions: dict[str, Any] = catalog.get("exclusions") or {}
    features_meta: dict[str, Any] = catalog.get("features") or {}
    helpers: dict[str, Any] = catalog.get("helpers") or {}

    problems: list[str] = []

    # skill checkout allowlist: only permitted sources (no artifacts/.run/pyc)
    for p in sorted(skill.rglob("*")):
        if not p.is_file():
            continue
        rel = p.relative_to(skill).as_posix()
        if not skill_rel_allowed(
            rel, features_meta=features_meta, helpers=helpers
        ):
            problems.append(f"fuente de skill no permitida: {rel}")

    # exclusions need reasons
    for path, meta in exclusions.items():
        reason = meta.get("reason") if isinstance(meta, dict) else None
        if not reason:
            problems.append(f"exclusión sin razón: {path}")

    discovered = set()
    if mutate != "omit_discovery":
        discovered = discover_from_roots(repo, catalog.get("roots"))

    classified_paths = set(classifications) | set(exclusions)
    for hpath in helpers:
        classified_paths.add(hpath)

    if mutate != "omit_discovery":
        for path in sorted(discovered):
            if path in classified_paths:
                continue
            problems.append(f"superficie sin clasificar: {path}")

    for path, meta in classifications.items():
        p = repo / path
        if not p.exists():
            problems.append(f"superficie clasificada ausente: {path}")
        if isinstance(meta, dict) and meta.get("feature") is None and not meta.get("kind"):
            problems.append(f"clasificación incompleta: {path}")

    feature_ids = list(features_meta.keys())
    if len(feature_ids) != len(set(feature_ids)):
        problems.append("ID de feature duplicado en catálogo")

    seen_catalog_ids: set[str] = set()
    seen_descriptor_ids: dict[str, str] = {}
    for fid, meta in features_meta.items():
        if fid in seen_catalog_ids:
            problems.append(f"ID duplicado: {fid}")
        seen_catalog_ids.add(fid)
        status = meta.get("status", "active")
        card = meta.get("card")
        desc_path = skill / "features" / f"{fid}.json"
        if status == "pending":
            owner = meta.get("owner_task")
            if not owner:
                problems.append(f"{fid}: pending sin owner_task")
            if card:
                problems.append(
                    f"{fid}: pending no debe fingir card hasta su tarea dueña ({owner})"
                )
            if desc_path.exists():
                desc = load_json(desc_path, accept_bad=accept_bad)
                if isinstance(desc, dict) and desc.get("__bad_json__"):
                    continue
                did = desc.get("id")
                if did != fid:
                    problems.append(f"{fid}: descriptor id mismatch")
                if did:
                    if did in seen_descriptor_ids:
                        problems.append(
                            f"ID duplicado entre descriptores: {did} "
                            f"({seen_descriptor_ids[did]} y {fid})"
                        )
                    seen_descriptor_ids[did] = fid
            continue
        if not card:
            problems.append(f"{fid}: falta card en catálogo")
            continue
        card_path = skill / card

        if not card_path.is_file():
            problems.append(f"{fid}: ficha ausente ({card})")
            continue
        if not desc_path.is_file():
            problems.append(f"{fid}: descriptor ausente features/{fid}.json")
            continue
        try:
            card_info = parse_card(card_path)
        except LintError as e:
            problems.append(str(e))
            continue
        desc = load_json(desc_path, accept_bad=accept_bad)
        if isinstance(desc, dict) and desc.get("__bad_json__"):
            continue
        if desc.get("schema_version") != SCHEMA_VERSION:
            problems.append(f"{fid}: descriptor schema_version inválido")
        did = desc.get("id")
        if did != fid:
            problems.append(f"{fid}: descriptor.id debe coincidir")
        if did:
            if did in seen_descriptor_ids:
                problems.append(
                    f"ID duplicado entre descriptores: {did} "
                    f"({seen_descriptor_ids[did]} y {fid})"
                )
            seen_descriptor_ids[did] = fid
        if desc.get("card") != Path(card).name and desc.get("card") != card:
            if Path(desc.get("card", "")).name != Path(card).name:
                problems.append(f"{fid}: descriptor.card no coincide con catálogo")

        cases = desc.get("cases") or []
        case_ids = [c.get("id") for c in cases]
        if len(case_ids) != len(set(case_ids)):
            problems.append(f"{fid}: case id duplicado en descriptor")
        card_ids = {c["id"] for c in card_info["cases"]}
        desc_ids = set(case_ids)
        if card_ids != desc_ids:
            problems.append(
                f"{fid}: cases de ficha {sorted(card_ids)} != descriptor {sorted(desc_ids)}"
            )
        for c in cases:
            req = c.get("required_assertions") or []
            if not req:
                problems.append(f"{fid}: caso {c.get('id')} sin required_assertions")

        executor = desc.get("executor")
        if not executor:
            problems.append(f"{fid}: ficha/descriptor sin ejecutor")
        else:
            try:
                validate_legacy_executor(skill, fid, executor, mutate)
            except LintError as e:
                problems.append(str(e))

    # orphan public drivers under skill scripts/drivers
    drivers_dir = skill / "scripts" / "drivers"
    if drivers_dir.is_dir() and mutate != "accept_orphan":
        known = set()
        for fid, meta in features_meta.items():
            if meta.get("status") == "pending":
                continue
            desc_path = skill / "features" / f"{fid}.json"
            if not desc_path.exists():
                continue
            desc = load_json(desc_path, accept_bad=accept_bad)
            if isinstance(desc, dict) and desc.get("__bad_json__"):
                continue
            ex = desc.get("executor") or {}
            if ex.get("kind") == "driver":
                known.add(ex.get("path") or f"scripts/drivers/{fid}.sh")
        for p in drivers_dir.glob("*.sh"):
            rel = f"scripts/drivers/{p.name}"
            if rel not in known and f"scripts/drivers/{p.stem}.sh" not in known:
                problems.append(f"ejecutor huérfano: {rel}")

    for md in sorted((skill / "features").glob("*.md")):
        if md.name == "README.md":
            continue
        fid = md.stem
        if fid not in features_meta:
            problems.append(f"ficha sin feature en catálogo: {md.name}")

    for hpath, meta in helpers.items():
        cand = skill / hpath
        if not cand.exists() and not (repo / hpath).exists():
            problems.append(f"helper clasificado ausente: {hpath}")
        if isinstance(meta, dict) and meta.get("kind") != "internal":
            problems.append(f"helper {hpath} debe kind=internal")

    ctrl = skill / "scripts" / "control-summonaikit"
    if not ctrl.is_file():
        problems.append("falta scripts/control-summonaikit")

    if mutate == "skip_h2_order":
        problems = [p for p in problems if "H2 fuera de orden" not in p]
    if mutate == "skip_triples":
        problems = [
            p
            for p in problems
            if "triple" not in p and "cases de ficha" not in p and "Case `" not in p
        ]

    if problems:
        for p in problems:
            err(p)
        return 1
    print("feature-map: OK")
    return 0


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--repo", type=Path, default=None, help="repo root (default: cwd)")
    ap.add_argument("--skill", type=Path, default=None, help="skill directory")
    ap.add_argument(
        "--mutate",
        default=None,
        choices=[
            "omit_discovery",
            "accept_orphan",
            "skip_h2_order",
            "skip_triples",
            "accept_bad_json",
            "skip_legacy_validate",
        ],
        help="test-only mutation hooks (discriminant)",
    )
    args = ap.parse_args(argv)
    repo = (args.repo or Path.cwd()).resolve()
    skill = skill_dir_from_args(repo, args.skill.resolve() if args.skill else None)
    if not skill.is_dir():
        err(f"skill dir ausente: {skill}")
        return 2
    try:
        return lint(repo, skill, mutate=args.mutate)
    except LintError as e:
        err(str(e))
        return 1


if __name__ == "__main__":
    sys.exit(main())
