#!/usr/bin/env python3
"""Estado declarativo del verify-summonaikit (.run/state.json).

Nunca se ejecuta ni se hace source. Un .run/env legado se rechaza con
instrucción de re-lanzar; su supuesto HOME no se borra desde aquí.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sys
from pathlib import Path
from typing import Any, Sequence

SCHEMA_VERSION = 1
MARKER_NAME = ".saikit-run"
REQUIRED = (
    "schema_version",
    "run_id",
    "launched_at",
    "repo",
    "verify_home",
    "dest",
    "state_dir",
    "artifacts_dir",
    "tmpdir",
    "owned_temps",
    "host_dests",
    "token",
)
WRITE_TOOLS = frozenset(
    {
        "tools/saikit-merge.sh",
        "tools/saikit-postmerge.sh",
        "tools/saikit-setup-autopilot.sh",
    }
)
INSTALL_HOOK = "tools/install-hook.sh"
INSTALL_HOOK_PATH_FLAGS = {
    "--dest": "run",
    "--source": "repo",
    "--manifest": "repo",
}
# `;|&$\`` y expansiones: peligrosos si alguien sourceara el valor.
_UNSAFE = re.compile(r"[\n\r;|&`$]|\$\(|&&|\|\|")


class StateError(Exception):
    """Violación de estado o aislamiento (exit 1)."""


def err(msg: str) -> None:
    print(f"control-summonaikit: {msg}", file=sys.stderr)


def lexical_safe(value: str, label: str) -> None:
    if not value:
        raise StateError(f"{label}: ruta vacía")
    if _UNSAFE.search(value):
        raise StateError(f"{label}: ruta con metacaracteres de shell")
    if ".." in Path(value).parts:
        raise StateError(f"{label}: ruta con .. escape")


def assert_no_symlink(path: Path, label: str) -> None:
    # Solo el path pedido: /tmp → /private/tmp en macOS no es un escape.
    if path.is_symlink():
        raise StateError(f"symlink escape: {label}")


def assert_under(child: Path, root: Path, label: str) -> None:
    try:
        child.resolve().relative_to(root.resolve())
    except ValueError as e:
        raise StateError(f"escape: {label} fuera del run") from e


def assert_run_member(path: Path, roots: Sequence[Path], label: str) -> None:
    lexical_safe(str(path), label)
    assert_no_symlink(path, label)
    if not roots:
        raise StateError(f"escape: {label} fuera del run")
    for root in roots:
        try:
            assert_under(path, root, label)
            return
        except StateError:
            continue
    raise StateError(f"escape: {label} fuera del run")


def read_marker(home: Path) -> tuple[str, str] | None:
    marker = home / MARKER_NAME
    if marker.is_symlink() or not marker.is_file():
        return None
    data: dict[str, str] = {}
    try:
        text = marker.read_text(encoding="utf-8")
    except OSError:
        return None
    for line in text.splitlines():
        if "=" not in line:
            continue
        key, _, val = line.partition("=")
        data[key.strip()] = val
    run_id = data.get("run_id")
    token = data.get("token")
    if run_id and token:
        return run_id, token
    return None


def assert_owned(home: Path, run_id: str, token: str, label: str) -> None:
    got = read_marker(home)
    if got != (run_id, token):
        raise StateError(f"{label} no es propio de este run (token/marker)")


def assert_assigned(path_str: str, label: str, *, mutate: str | None) -> Path:
    if mutate != "skip_physical_path":
        lexical_safe(path_str, label)
        assert_no_symlink(Path(path_str), label)
    return Path(path_str)


def legacy_env(state_dir: Path) -> Path:
    return state_dir / "env"


def reject_legacy(state_dir: Path) -> None:
    if legacy_env(state_dir).is_file():
        raise StateError(
            "legacy .run/env — re-lanzar: borrar solo el archivo env "
            "(nunca su HOME) y correr launch"
        )


def load_json_file(path: Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as e:
        raise StateError(f"JSON truncado o mal formado: {e}") from e
    except OSError as e:
        raise StateError(f"no se pudo leer state.json: {e}") from e


def validate_payload(
    data: Any,
    *,
    state_dir: Path,
    artifacts: Path,
    mutate: str | None,
    mode: str,
) -> dict[str, Any]:
    if not isinstance(data, dict):
        raise StateError("JSON inválido: se esperaba un objeto")
    missing = [k for k in REQUIRED if k not in data]
    if missing:
        raise StateError(f"JSON inválido: faltan campos {missing}")
    if data.get("schema_version") != SCHEMA_VERSION:
        raise StateError("JSON inválido: schema_version")
    if not isinstance(data.get("owned_temps"), list):
        raise StateError("JSON inválido: owned_temps")
    if not isinstance(data.get("host_dests"), dict):
        raise StateError("JSON inválido: host_dests")

    skip_phys = mutate == "skip_physical_path"
    skip_own = mutate == "skip_cleanup_ownership" and mode == "cleanup"

    path_fields = (
        "repo",
        "verify_home",
        "dest",
        "state_dir",
        "artifacts_dir",
        "tmpdir",
    )
    for key in path_fields:
        val = data[key]
        if not isinstance(val, str):
            raise StateError(f"JSON inválido: {key}")
        if not skip_phys:
            lexical_safe(val, key)

    for item in data["owned_temps"]:
        if not isinstance(item, str):
            raise StateError("JSON inválido: owned_temps")
        if not skip_phys:
            lexical_safe(item, "owned_temps")
    for host, dest in data["host_dests"].items():
        if not isinstance(dest, str):
            raise StateError(f"JSON inválido: host_dests.{host}")
        if not skip_phys:
            lexical_safe(dest, f"host_dests.{host}")

    for opt in ("git_common_dir", "disposable_repo"):
        val = data.get(opt)
        if val:
            if not isinstance(val, str):
                raise StateError(f"JSON inválido: {opt}")
            if not skip_phys:
                lexical_safe(val, opt)

    if skip_phys:
        return data

    home = Path(data["verify_home"])
    dest = Path(data["dest"])
    tmpdir = Path(data["tmpdir"])
    assert_no_symlink(home, "verify_home")
    assert_no_symlink(Path(data["state_dir"]), "state_dir")
    assert_no_symlink(Path(data["artifacts_dir"]), "artifacts_dir")
    roots = [home]
    for item in data["owned_temps"]:
        roots.append(Path(item))
    assert_run_member(tmpdir, roots, "tmpdir")
    assert_run_member(dest, roots, "dest")
    for host, dest_s in data["host_dests"].items():
        assert_run_member(Path(dest_s), roots, f"host_dests.{host}")

    if mode != "cleanup" or not skip_own:
        if mode == "cleanup" and skip_own:
            pass
        else:
            assert_owned(home, str(data["run_id"]), str(data["token"]), "verify_home")

    if mode == "cleanup" and skip_own:
        return data
    if mode != "cleanup":
        # doctor/drive/cli: pertenencia obligatoria (ya assert_owned)
        pass
    return data


def cmd_preflight(args: argparse.Namespace) -> int:
    mutate = args.mutate or None
    state_dir = Path(args.state_dir)
    artifacts = Path(args.artifacts)
    try:
        reject_legacy(state_dir)
        if (state_dir / "state.json").is_file() or (state_dir / ".active").is_dir():
            raise StateError("run activo — run cleanup first")
        assert_assigned(str(state_dir), "STATE", mutate=mutate)
        assert_assigned(str(artifacts), "artifacts", mutate=mutate)
    except StateError as e:
        err(str(e))
        return 1
    return 0


def cmd_load(args: argparse.Namespace) -> int:
    mutate = args.mutate or None
    state_dir = Path(args.state_dir)
    artifacts = Path(args.artifacts)
    try:
        reject_legacy(state_dir)
        path = state_dir / "state.json"
        if not path.is_file():
            raise StateError("no active instance — run: control-summonaikit launch")
        data = load_json_file(path)
        data = validate_payload(
            data,
            state_dir=state_dir,
            artifacts=artifacts,
            mutate=mutate,
            mode=args.mode,
        )
    except StateError as e:
        err(str(e))
        return 1
    json.dump(data, sys.stdout, ensure_ascii=False)
    sys.stdout.write("\n")
    return 0


def cmd_save(args: argparse.Namespace) -> int:
    try:
        data = load_json_file(Path(args.payload))
        if not isinstance(data, dict) or data.get("schema_version") != SCHEMA_VERSION:
            raise StateError("JSON inválido al guardar")
        state_dir = Path(args.state_dir)
        state_dir.mkdir(parents=True, exist_ok=True)
        dest = state_dir / "state.json"
        tmp = state_dir / "state.json.tmp"
        tmp.write_text(
            json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
        )
        os.chmod(tmp, 0o600)
        tmp.replace(dest)
    except StateError as e:
        err(str(e))
        return 1
    except OSError as e:
        err(f"no se pudo escribir state.json: {e}")
        return 1
    return 0


def public_tools(catalog: dict[str, Any]) -> set[str]:
    out: set[str] = set()
    for path, meta in (catalog.get("surfaces") or {}).items():
        if isinstance(meta, dict) and meta.get("kind") == "asset":
            continue
        out.add(path)
    return out


def resolve_cli_path(raw: str, base: Path) -> Path:
    p = Path(raw)
    if not p.is_absolute():
        p = base / p
    return p


def iter_flag_values(argv: list[str], names: Sequence[str]) -> list[tuple[str, str]]:
    out: list[tuple[str, str]] = []
    i = 1
    while i < len(argv):
        a = argv[i]
        matched = False
        for name in names:
            if a == name:
                if i + 1 >= len(argv) or argv[i + 1].startswith("-"):
                    raise StateError(f"cli: {name} exige un valor")
                out.append((name, argv[i + 1]))
                i += 2
                matched = True
                break
            prefix = name + "="
            if a.startswith(prefix):
                val = a[len(prefix) :]
                if not val:
                    raise StateError(f"cli: {name} exige un valor")
                out.append((name, val))
                i += 1
                matched = True
                break
        if not matched:
            i += 1
    return out


def normalize_tool(arg: str, repo: Path) -> str | None:
    s = arg
    if s.startswith("./"):
        s = s[2:]
    raw = Path(s)
    if raw.is_absolute():
        try:
            s = raw.resolve().relative_to(repo.resolve()).as_posix()
        except ValueError:
            return None
    if ".." in Path(s).parts:
        return None
    return s


def cmd_cli_ok(args: argparse.Namespace) -> int:
    mutate = args.mutate or None
    argv = list(args.argv)
    try:
        if not argv:
            raise StateError("cli: falta entrada del catálogo público")
        catalog = load_json_file(Path(args.catalog))
        if not isinstance(catalog, dict):
            raise StateError("catálogo inválido")
        allowed = public_tools(catalog)
        repo = Path(args.repo)
        tool = normalize_tool(argv[0], repo)
        if tool is None or tool not in allowed:
            raise StateError(
                "cli no admite comandos fuera del catálogo público"
            )
        for extra in argv[1:]:
            if extra.startswith("-"):
                continue
            if _UNSAFE.search(extra):
                raise StateError("cli: argumento con metacaracteres de shell")
            if ".." in Path(extra).parts:
                raise StateError("cli: argumento con .. escape")
        if tool == INSTALL_HOOK and mutate != "skip_physical_path":
            pairs = iter_flag_values(argv, tuple(INSTALL_HOOK_PATH_FLAGS))
            if pairs:
                if not args.home:
                    raise StateError("cli: falta --home para validar dest")
                home = Path(args.home)
                run_roots = [home]
                for item in args.owned_temp or []:
                    if item:
                        run_roots.append(Path(item))
                for flag, raw in pairs:
                    kind = INSTALL_HOOK_PATH_FLAGS[flag]
                    if kind == "run":
                        assert_run_member(
                            resolve_cli_path(raw, home), run_roots, f"cli {flag}"
                        )
                    else:
                        assert_run_member(
                            resolve_cli_path(raw, repo), [repo], f"cli {flag}"
                        )
        if tool in WRITE_TOOLS and mutate != "skip_cwd_isolation":
            cwd = Path(args.cwd).resolve()
            repo_r = repo.resolve()
            disposable = args.disposable
            disp_ok = False
            if disposable:
                try:
                    disp_ok = cwd == Path(disposable).resolve()
                except OSError:
                    disp_ok = False
            on_checkout = cwd == repo_r or repo_r in cwd.parents
            if on_checkout or not disp_ok:
                raise StateError(
                    "tools de escritura requieren repo desechable; "
                    "checkout de trabajo rechazado"
                )
        print(tool)
    except StateError as e:
        err(str(e))
        return 1
    return 0


def cmd_member(args: argparse.Namespace) -> int:
    mutate = args.mutate or None
    if mutate == "skip_physical_path":
        return 0
    try:
        path = Path(args.path)
        roots = [Path(r) for r in (args.root or []) if r]
        if roots:
            assert_run_member(path, roots, args.label)
        else:
            lexical_safe(str(path), args.label)
            assert_no_symlink(path, args.label)
    except StateError as e:
        err(str(e))
        return 1
    return 0


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    sub = ap.add_subparsers(dest="cmd", required=True)

    p = sub.add_parser("preflight")
    p.add_argument("--state-dir", required=True)
    p.add_argument("--artifacts", required=True)
    p.add_argument("--mutate", default="")
    p.set_defaults(func=cmd_preflight)

    p = sub.add_parser("load")
    p.add_argument("--state-dir", required=True)
    p.add_argument("--artifacts", required=True)
    p.add_argument("--repo", default="")
    p.add_argument("--mode", default="drive", choices=["drive", "doctor", "cli", "cleanup"])
    p.add_argument("--mutate", default="")
    p.set_defaults(func=cmd_load)

    p = sub.add_parser("save")
    p.add_argument("--state-dir", required=True)
    p.add_argument("--payload", required=True)
    p.set_defaults(func=cmd_save)

    p = sub.add_parser("cli-ok")
    p.add_argument("--catalog", required=True)
    p.add_argument("--repo", required=True)
    p.add_argument("--cwd", required=True)
    p.add_argument("--disposable", default="")
    p.add_argument("--home", default="")
    p.add_argument("--owned-temp", action="append", default=[])
    p.add_argument("--mutate", default="")
    p.add_argument("argv", nargs=argparse.REMAINDER)
    p.set_defaults(func=cmd_cli_ok)

    p = sub.add_parser("member")
    p.add_argument("--path", required=True)
    p.add_argument("--root", action="append", default=[])
    p.add_argument("--label", default="path")
    p.add_argument("--mutate", default="")
    p.set_defaults(func=cmd_member)

    args = ap.parse_args(argv)
    if args.cmd == "cli-ok" and args.argv and args.argv[0] == "--":
        args.argv = args.argv[1:]
    try:
        return int(args.func(args))
    except StateError as e:
        err(str(e))
        return 1


if __name__ == "__main__":
    sys.exit(main())
