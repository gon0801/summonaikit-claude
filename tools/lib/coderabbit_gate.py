"""Require CodeRabbit's completed review and status for the PR's current head."""

import json
import subprocess
import sys


def gh_json(path, *flags):
    result = subprocess.run(
        ["gh", "api", path, *flags], capture_output=True, text=True, check=False
    )
    if result.returncode:
        raise ValueError(f"gh api {path} fallo")
    try:
        return json.loads(result.stdout)
    except json.JSONDecodeError as exc:
        raise ValueError(f"gh api {path} no devolvio JSON valido") from exc


def check(repo, pr, sha, receipt_date):
    pages = gh_json(f"repos/{repo}/pulls/{pr}/reviews?per_page=100", "--paginate", "--slurp")
    if not isinstance(pages, list) or any(not isinstance(page, list) for page in pages):
        raise ValueError("revisiones de CodeRabbit con formato invalido")
    reviews = [review for page in pages for review in page]
    bot_reviews = [
        review for review in reviews
        if isinstance(review, dict)
        and isinstance(review.get("user"), dict)
        and review["user"].get("login") == "coderabbitai[bot]"
    ]
    if not bot_reviews:
        raise ValueError("CodeRabbit no reviso este PR")
    latest_review = max(bot_reviews, key=lambda item: (item.get("submitted_at") or "", item.get("id") or 0))
    if latest_review.get("commit_id") != sha:
        raise ValueError("la ultima revision de CodeRabbit no corresponde al head actual")
    if latest_review.get("state") not in ("COMMENTED", "APPROVED"):
        raise ValueError("la ultima revision de CodeRabbit no esta completada")
    if not latest_review.get("submitted_at"):
        raise ValueError("la revision de CodeRabbit no trae fecha de envio")

    combined = gh_json(f"repos/{repo}/commits/{sha}/status")
    statuses = combined.get("statuses") if isinstance(combined, dict) else None
    if not isinstance(statuses, list):
        raise TypeError("estados de CodeRabbit con formato invalido")
    rabbit = [status for status in statuses if isinstance(status, dict) and status.get("context") == "CodeRabbit"]
    if not rabbit:
        raise ValueError("falta el estado CodeRabbit del head actual")
    latest_status = max(rabbit, key=lambda item: (item.get("created_at") or "", item.get("id") or 0))
    # El estado real de la GitHub App viene con creator=null. Un usuario con
    # permiso de escritura puede publicar el mismo contexto con su cuenta.
    if latest_status.get("creator") is not None:
        raise ValueError("el estado vigente de CodeRabbit fue creado por otra cuenta")
    if latest_status.get("state") != "success":
        raise ValueError("el estado vigente de CodeRabbit no es success")
    if not latest_status.get("created_at"):
        raise ValueError("el estado de CodeRabbit no trae fecha")
    if (latest_status.get("created_at") or "") < (latest_review.get("submitted_at") or ""):
        raise ValueError("el estado de CodeRabbit precede su ultima revision")

    if not receipt_date or receipt_date < latest_review.get("submitted_at"):
        raise ValueError("el recibo del lead debe adjudicar la ultima revision de CodeRabbit")


if __name__ == "__main__":
    try:
        check(*sys.argv[1:])
    except (TypeError, ValueError) as exc:
        print(f"CodeRabbit: {exc}", file=sys.stderr)
        sys.exit(1)
