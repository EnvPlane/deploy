#!/usr/bin/env python3
"""Require trusted main CI for exact immutable candidates, never publication CI."""
import argparse
import json
import re
import subprocess
import sys
from pathlib import Path

SHA = re.compile(r"[0-9a-f]{40}")
DIGEST = re.compile(r"sha256:[0-9a-f]{64}")
IMAGES = {
    "controlPlane": ("control-plane", "api"),
    "frontend": ("frontend", "frontend"),
    "agent": ("agent", "agent"),
    "runner": ("runner", "runner"),
    "webhook": ("webhook", "webhook"),
    "platformReconciler": ("deploy", "platform-reconciler"),
}
CHARTS = {"controlPlane": "envplane-control-plane", "frontend": "envplane-frontend",
          "agent": "envplane-agent", "runner": "envplane-runner",
          "webhook": "envplane-webhook", "e2eWorkload": "envplane-e2e-workload"}
REPOSITORIES = {"deploy", "contracts", "control-plane", "frontend", "agent",
                "runner", "webhook", "gitops", "bootstrap"}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def revision(value):
    require(isinstance(value, str) and SHA.fullmatch(value), "invalid candidate SHA")
    return value


def candidates(report):
    require(report.get("schemaVersion") == 1, "unsupported compatibility schema")
    deploy_sha = revision(report.get("sourceRevision"))
    result = {("deploy", deploy_sha)}
    require(isinstance(report.get("images"), dict) and set(report["images"]) == set(IMAGES),
            "missing or unknown image candidate")
    require(isinstance(report.get("charts"), dict) and set(report["charts"]) == set(CHARTS),
            "missing or unknown chart candidate")
    for component, (repository, image) in IMAGES.items():
        entry = report["images"][component]
        sha = revision(entry.get("sourceRevision"))
        require(entry.get("repository") == f"ghcr.io/envplane/{image}" and
                entry.get("tag") == f"sha-{sha}" and
                DIGEST.fullmatch(entry.get("digest", "")), f"invalid {component} immutable pin")
        result.add((repository, sha))
    for component, chart in CHARTS.items():
        entry = report["charts"][component]
        require(entry.get("repository") == f"oci://ghcr.io/envplane/{chart}" and
                revision(entry.get("sourceRevision")) == deploy_sha and
                re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", entry.get("version", "")) and
                DIGEST.fullmatch(entry.get("digest", "")), f"invalid {component} chart pin")
    return sorted(result)


def api(endpoint, paginate=False):
    command = ["gh", "api", "--hostname", "github.com", "-H", "Accept: application/vnd.github+json",
               "-H", "X-GitHub-Api-Version: 2022-11-28"]
    if paginate:
        command += ["--paginate", "--slurp"]
    try:
        completed = subprocess.run(command + [endpoint], capture_output=True, text=True,
                                   timeout=90, check=True)
        return json.loads(completed.stdout)
    except (OSError, subprocess.SubprocessError, json.JSONDecodeError) as error:
        # Never relay credential-bearing CLI diagnostics or response bodies.
        raise ValueError("GitHub CI status service unavailable or invalid response") from error


def collection(endpoint, key):
    pages = api(endpoint, paginate=True)
    require(isinstance(pages, list) and bool(pages), "missing CI status pages")
    rows = []
    for page in pages:
        require(isinstance(page, dict) and isinstance(page.get(key), list), "invalid CI status page")
        rows.extend(page[key])
    require(all(type(page.get("total_count")) is int and page["total_count"] == len(rows)
                for page in pages), "incomplete or changing CI status pagination")
    return rows


def verify(repository, sha):
    require(repository in REPOSITORIES, "unknown candidate repository")
    revision(sha)
    base = f"repos/envplane/{repository}/actions"
    runs = collection(f"{base}/workflows/ci.yaml/runs?head_sha={sha}&branch=main&event=push&per_page=100",
                      "workflow_runs")
    require(bool(runs), f"{repository}@{sha}: required CI missing")
    require(all(type(run.get("id")) is int for run in runs), "invalid CI run identity")
    # A newer failed/pending run must not be hidden behind an earlier success.
    run = api(f"{base}/runs/{max(run['id'] for run in runs)}")
    require(run.get("head_sha") == sha and run.get("head_branch") == "main" and
            run.get("event") == "push" and run.get("path") == ".github/workflows/ci.yaml" and
            run.get("head_repository", {}).get("full_name", "").lower() == f"envplane/{repository}",
            f"{repository}@{sha}: untrusted CI identity")
    require(run.get("status") == "completed" and run.get("conclusion") == "success",
            f"{repository}@{sha}: required CI not successful")
    attempt = run.get("run_attempt")
    require(type(attempt) is int and attempt > 0 and type(run.get("id")) is int,
            "missing CI attempt identity")
    jobs = collection(f"{base}/runs/{run['id']}/attempts/{attempt}/jobs?per_page=100", "jobs")
    required_job = "helm" if repository == "deploy" else "test"
    require(sum(job.get("name") == required_job for job in jobs) == 1,
            f"{repository}@{sha}: required job missing or ambiguous")
    require(all(job.get("head_sha") == sha and job.get("run_id") == run["id"] and
                # The documented attempt-specific endpoint establishes attempt
                # identity; job responses need not contain run_attempt.
                ("run_attempt" not in job or job["run_attempt"] == attempt) and
                job.get("status") == "completed" and
                job.get("conclusion") == "success" for job in jobs),
            f"{repository}@{sha}: CI jobs not successful for exact attempt")
    require(api(f"{base}/runs/{run['id']}") == run, "CI run changed during verification")
    refreshed = collection(f"{base}/workflows/ci.yaml/runs?head_sha={sha}&branch=main&event=push&per_page=100",
                           "workflow_runs")
    require(bool(refreshed) and max(row["id"] for row in refreshed) == run["id"],
            "new CI run appeared during verification")
    return {"repository": f"envplane/{repository}", "sha": sha, "runId": run["id"],
            "attempt": attempt, "requiredJob": required_job, "conclusion": "success"}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--report", type=Path)
    mode.add_argument("--candidate", action="append", help="trusted repository=full SHA")
    args = parser.parse_args()
    try:
        selected = candidates(json.loads(args.report.read_text())) if args.report else [
            tuple(item.split("=", 1)) for item in args.candidate]
        receipts = [verify(repository, sha) for repository, sha in sorted(set(selected))]
        print(json.dumps({"requiredCI": receipts}, sort_keys=True))
    except (ValueError, KeyError, TypeError, AttributeError, OSError) as error:
        print(f"release CI gate refused: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
