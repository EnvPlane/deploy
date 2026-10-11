#!/usr/bin/env python3
"""Local QA only: recover a dead kubectl forward, never replay application writes."""

import argparse
import http.client
import re
import signal
import subprocess
import threading
import time


def transport_alive(port):
    connection = http.client.HTTPConnection("127.0.0.1", port, timeout=2)
    try:
        # Do not follow redirects, attach credentials or log bodies. Any HTTP
        # status proves forwarding works; API/auth failures are not restarts.
        connection.request("GET", "/", headers={"Host": "envplane.local", "Connection": "close"})
        connection.getresponse()
        return True
    except (OSError, http.client.HTTPException):
        return False
    finally:
        connection.close()


def monitor(child, port, stop, grace=20, interval=2, failed_limit=3):
    started = time.monotonic()
    failures = 0
    while not stop.is_set():
        if child.poll() is not None:
            return "forward exited"
        alive = transport_alive(port)
        failures = 0 if alive else failures + 1
        if time.monotonic() - started >= grace and failures >= failed_limit:
            return "forward transport unavailable"
        stop.wait(interval)
    return "stopped"


def stop_child(child):
    if child.poll() is None:
        child.terminate()
        try:
            child.wait(timeout=5)
        except subprocess.TimeoutExpired:
            child.kill()
            child.wait()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--kubectl", default="kubectl")
    parser.add_argument("--kubeconfig", required=True)
    parser.add_argument("--context", required=True)
    parser.add_argument("--namespace", required=True)
    parser.add_argument("--service", required=True)
    parser.add_argument("--local-port", type=int, default=3000)
    parser.add_argument("--remote-port", type=int, default=3000)
    args = parser.parse_args()
    for name in (args.namespace, args.service):
        if not re.fullmatch(r"[a-z0-9](?:[a-z0-9-]*[a-z0-9])?", name):
            parser.error("namespace/service must be explicit Kubernetes names")
    if not all(1 <= port <= 65535 for port in (args.local_port, args.remote_port)):
        parser.error("ports must be between 1 and 65535")
    stop = threading.Event()
    for sig in (signal.SIGINT, signal.SIGTERM):
        signal.signal(sig, lambda *_: stop.set())
    command = [args.kubectl, "--kubeconfig", args.kubeconfig, "--context", args.context,
               "-n", args.namespace, "port-forward", "service/" + args.service,
               f"{args.local_port}:{args.remote_port}", "--address", "127.0.0.1"]
    while not stop.is_set():
        # Only this child is stopped. No process-name/port-based global kill.
        child = subprocess.Popen(command, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        try:
            reason = monitor(child, args.local_port, stop)
        finally:
            stop_child(child)
        if not stop.is_set():
            print(reason + "; restarting local forward (no request replay)", flush=True)
            stop.wait(2)


if __name__ == "__main__":
    main()
