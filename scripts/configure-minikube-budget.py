#!/usr/bin/env python3
"""Bound this local node's scheduler budget by its Docker container limits."""
import argparse
import json
from pathlib import Path
import re
import subprocess
import tempfile
import time

MARKER = "# envplane local scheduling budget"


def run(command):
    return subprocess.run(command, capture_output=True, text=True, check=True, timeout=60).stdout


def reservation(node, container):
    if node["metadata"]["name"] != "envplane" or container["Name"] != "/envplane" or not container["State"]["Running"]:
        raise ValueError("target identity does not match the isolated envplane profile")
    limits = container["HostConfig"]
    cpu = limits["NanoCpus"] // 1_000_000
    memory = limits["Memory"] // 1024
    if cpu <= 200 or memory <= 512 * 1024:
        raise ValueError("finite Docker CPU and memory limits are required")
    capacity = node["status"]["capacity"]
    if not re.fullmatch(r"[0-9]+", capacity["cpu"]) or not re.fullmatch(r"[0-9]+Ki", capacity["memory"]):
        raise ValueError("unsupported node capacity units")
    reserve_cpu = int(capacity["cpu"]) * 1000 - cpu + 200
    reserve_memory = int(capacity["memory"][:-2]) - memory + 512 * 1024
    if reserve_cpu < 0 or reserve_memory < 0:
        raise ValueError("reported capacity is smaller than the container budget")
    return {"systemReserved": {"cpu": f"{reserve_cpu}m", "memory": f"{reserve_memory}Ki"},
            "expectedAllocatable": {"cpuMilli": cpu - 200, "memoryKi": memory - 512 * 1024},
            "dockerLimits": {"cpuMilli": cpu, "memoryKi": memory}}


def configured(original, budget):
    original = original.replace("\r\n", "\n")
    if MARKER in original:
        original = original.split(MARKER, 1)[0]
    if re.search(r"^(systemReserved|kubeReserved):", original, re.M):
        raise ValueError("unmanaged kubelet reservations exist; review before changing them")
    values = budget["systemReserved"]
    return original.rstrip() + f"\n{MARKER}\nsystemReserved:\n  cpu: {values['cpu']}\n  memory: {values['memory']}\n"


def matches_budget(allocatable, expected):
    # Kubernetes canonicalizes equivalent binary quantities (e.g. Ki -> Mi).
    memory = re.fullmatch(r"([0-9]+)(Ki|Mi|Gi)", allocatable.get("memory", ""))
    cpu = re.fullmatch(r"([0-9]+)(m?)", allocatable.get("cpu", ""))
    if not memory or not cpu:
        return False
    memory_ki = int(memory[1]) * {"Ki": 1, "Mi": 1024, "Gi": 1024 * 1024}[memory[2]]
    cpu_milli = int(cpu[1]) * (1 if cpu[2] == "m" else 1000)
    return memory_ki == expected["memoryKi"] and cpu_milli == expected["cpuMilli"]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--kubeconfig", type=Path, required=True)
    parser.add_argument("--kubectl", default="kubectl")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args()
    base = [args.kubectl, "--kubeconfig", str(args.kubeconfig.resolve()), "--context", "envplane"]
    node = json.loads(run(base + ["get", "node", "envplane", "-o", "json"]))
    container = json.loads(run(["docker", "inspect", "envplane"]))[0]
    budget = reservation(node, container)
    original = run(["minikube", "-p", "envplane", "ssh", "--", "sudo cat /var/lib/kubelet/config.yaml"])
    content = configured(original, budget)
    print(json.dumps(budget, indent=2))
    if args.apply and original.replace("\r\n", "\n") != content:
        with tempfile.TemporaryDirectory(prefix="envplane-kubelet-") as temporary:
            path = Path(temporary) / "config.yaml"
            path.write_text(content)
            run(["minikube", "-p", "envplane", "cp", str(path), "envplane:/tmp/envplane-kubelet-budget.yaml"])
            run(["minikube", "-p", "envplane", "ssh", "--",
                 "sudo cp -n /var/lib/kubelet/config.yaml /var/lib/kubelet/config.yaml.before-envplane-budget && "
                 "sudo install -m 600 /tmp/envplane-kubelet-budget.yaml /var/lib/kubelet/config.yaml && "
                 "sudo rm /tmp/envplane-kubelet-budget.yaml && sudo systemctl restart kubelet"])
        budget["applied"] = True
    else:
        budget["applied"] = args.apply
        budget["unchanged"] = args.apply
    if args.apply:
        deadline = time.monotonic() + 90
        while time.monotonic() < deadline:
            observed = json.loads(run(base + ["get", "node", "envplane", "-o", "json"]))
            ready = any(c["type"] == "Ready" and c["status"] == "True"
                        for c in observed["status"]["conditions"])
            if ready and matches_budget(observed["status"]["allocatable"], budget["expectedAllocatable"]):
                budget["verifiedAllocatable"] = observed["status"]["allocatable"]
                budget["nodeReady"] = True
                break
            time.sleep(2)
        else:
            raise RuntimeError("expected scheduler budget and Ready state were not observed")
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(budget, indent=2) + "\n")


if __name__ == "__main__":
    main()
