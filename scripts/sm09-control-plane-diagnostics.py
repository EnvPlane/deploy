#!/usr/bin/env python3
"""Bounded pod/startup classifications; never emit raw log or error values."""
import argparse
import json
import re
import subprocess

STARTUP = {
    "failed to load runtime config": "runtime_config",
    "failed to create data directory": "data_directory",
    "failed to open postgres": "postgres_open",
    "failed to ping postgres": "postgres_connect",
    "failed to apply postgres migrations": "postgres_migrations",
    "failed to initialise redis queue": "redis_open",
    "failed to ping redis": "redis_connect",
    "failed to open isolated FinOps database connection": "ledger_open",
    "isolated ledger provisioning failed": "ledger_provisioning",
    "failed to initialise offline license store": "license_store",
}
REASONS = {"Error", "OOMKilled", "Completed", "ContainerCannotRun",
           "CrashLoopBackOff", "CreateContainerConfigError", "ImagePullBackOff",
           "ErrImagePull", "ContainerCreating", "PodInitializing"}
CONFIG_CHECKS = {
    "read install-flow compatibility manifest:": "compatibility_manifest_read",
    "decode install-flow compatibility manifest:": "compatibility_manifest_decode",
    "install-flow compatibility manifest is invalid": "compatibility_manifest_invalid",
    "install-flow compatibility manifest has no complete contract": "compatibility_contract_incomplete",
    "conflicts with signed install-flow compatibility manifest": "compatibility_contract_mismatch",
    "conflicts with signed compatibility manifest": "compatibility_rollout_mismatch",
    "ENVPLANE_CREDENTIAL_ENCRYPTION_KEY": "credential_key_validation",
    "ENVPLANE_OAUTH_SESSION_SECRET": "oauth_session_validation",
    "ENVPLANE_PUBLIC_URL": "public_url_validation",
    "installation_identity_in_use": "installation_identity_in_use",
    "installation_identity_custody_unavailable": "installation_identity_custody_unavailable",
    "installation_identity_state_invalid": "installation_identity_state_invalid",
}


def startup_records(raw):
    records = set()
    for line in raw.splitlines():
        try:
            entry = json.loads(line)
        except (ValueError, TypeError):
            if line.startswith("panic:"):
                records.add(("panic", "", ()))
            continue
        if not isinstance(entry, dict):
            continue
        message = entry.get("message", entry.get("msg", ""))
        category = STARTUP.get(message) if isinstance(message, str) else None
        if category is None:
            if entry.get("level") not in ("ERROR", "FATAL"):
                continue
            category = "unclassified_error"
        # SQLSTATE is a fixed public code, unlike the surrounding free-form
        # error, which may contain a DSN or credential. Do not emit that text.
        match = re.search(r"\bSQLSTATE ([0-9A-Z]{5})\b", str(entry.get("error", "")))
        checks = tuple(sorted(code for text, code in CONFIG_CHECKS.items()
                              if text in str(entry.get("error", ""))))
        records.add((category, match.group(1) if match else "", checks))
    return [{"category": category, "sqlstate": code,
             **({"configChecks": list(checks)} if checks else {})}
            for category, code, checks in sorted(records)[:20]]


def collect(context, namespace, run=subprocess.run):
    base = ["kubectl", "--context", context, "-n", namespace]

    def call(args):
        try:
            result = run(base + args, capture_output=True, text=True, timeout=15,
                         check=False)
        except (OSError, subprocess.TimeoutExpired):
            return None
        if result.returncode or len(result.stdout) > 2 * 1024 * 1024:
            return None
        return result.stdout

    raw = call(["get", "pods", "-l", "app.kubernetes.io/name=envplane-control-plane", "-o", "json"])
    if raw is None:
        return [{"diagnostics": "pod_inventory_unavailable"}]
    try:
        pods = json.loads(raw or "{}").get("items", [])
    except (ValueError, AttributeError):
        return [{"diagnostics": "pod_inventory_unavailable"}]
    if not isinstance(pods, list):
        return [{"diagnostics": "pod_inventory_unavailable"}]
    output = []
    for pod in pods[:20]:
        name = pod.get("metadata", {}).get("name", "")
        if not isinstance(name, str) or not re.fullmatch(r"[a-z0-9][a-z0-9.-]{0,252}", name):
            continue
        statuses = pod.get("status", {}).get("containerStatuses", [])
        for status in statuses:
            if status.get("name") != "api":
                continue
            state = status.get("state", {})
            metadata = {"pod": name, "ready": status.get("ready") is True}
            for key in ("waiting", "terminated"):
                reason = state.get(key, {}).get("reason")
                if reason:
                    metadata[key] = reason if reason in REASONS else "other"
            for key in ("restartCount",):
                value = status.get(key)
                if type(value) is int and 0 <= value <= 100000:
                    metadata[key] = value
            for source in ("state", "lastState"):
                code = status.get(source, {}).get("terminated", {}).get("exitCode")
                if type(code) is int and 0 <= code <= 255:
                    metadata[source + "ExitCode"] = code
            image = status.get("imageID", "")
            if isinstance(image, str) and re.fullmatch(r"[a-zA-Z0-9./:_@-]+", image):
                metadata["imageID"] = image
            output.append(metadata)
        for previous in (False, True):
            args = ["logs", name, "-c", "api", "--tail=200", "--limit-bytes=65536"]
            if previous:
                args.append("--previous")
            for record in startup_records(call(args) or ""):
                output.append({"pod": name, "log": "previous" if previous else "current", **record})
    return output


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--context", required=True)
    parser.add_argument("--namespace", required=True)
    args = parser.parse_args()
    for record in collect(args.context, args.namespace):
        print(json.dumps(record, sort_keys=True))
