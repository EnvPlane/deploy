#!/usr/bin/env python3
"""Build native SQL adapter, actual Root helper and actual profile renderer; no push/load."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile


def snapshot(workspace):
    roots = ['runner/cmd', 'runner/internal', 'contracts/domain',
             'control-plane/internal/pvccopyonboarding', 'control-plane/apps/pvc-copy-source-profile']
    files = []
    for root in roots:
        files += sorted((workspace / root).rglob('*.go'))
    for name in ('runner', 'contracts', 'control-plane', 'gitops'):
        files += [workspace / name / 'go.mod', workspace / name / 'go.sum']
    return {str(p.relative_to(workspace)): hashlib.sha256(p.read_bytes()).hexdigest()
            for p in files if p.exists()}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--run-id', required=True)
    parser.add_argument('--output-dir', required=True)
    parser.add_argument('--refresh-adapters', action='store_true', help='rebuild host adapters only; preserve verified Root helper archive')
    args = parser.parse_args()
    scripts = Path(__file__).resolve().parent
    workspace = scripts.parents[1]
    output = Path(args.output_dir).resolve()
    before = snapshot(workspace)
    if not args.refresh_adapters:
        subprocess.run(['python3', str(scripts / 'pvc-copy-live-build.py'),
                        '--run-id', args.run_id, '--output-dir', str(output)], check=True)
    elif json.loads((output / 'build.json').read_text())['runID'] != args.run_id:
        raise ValueError('existing helper run identity mismatch')
    elif (output / 'source-snapshot.json').exists():
        prior = json.loads((output / 'source-snapshot.json').read_text())
        helper_sources = lambda files: {k: v for k, v in files.items() if k.startswith(('runner/', 'contracts/', 'gitops/'))}
        if helper_sources(prior) != helper_sources(before):
            raise RuntimeError('helper sources changed; build a fresh full snapshot/run, not adapters only')
    with tempfile.TemporaryDirectory(prefix='mysql-copy-native-build-') as directory:
        module = Path(directory)
        (module / 'main.go').write_bytes((scripts / 'mysql-copy-live-driver/main.go').read_bytes())
        replacements = '\n'.join(f'replace github.com/envplane/{name} => {workspace / name}'
                                  for name in ('runner', 'contracts', 'gitops', 'control-plane'))
        (module / 'go.mod').write_text('module github.com/envplane/runner/mysql-copy-live-driver\n\ngo 1.26.9\n\nrequire (\n github.com/envplane/runner v0.0.0\n github.com/envplane/control-plane v0.0.0\n)\n' + replacements + '\n')
        env = {**os.environ, 'GOWORK': 'off', 'GOPROXY': 'off', 'GOSUMDB': 'off', 'GOTOOLCHAIN': 'local',
               'GOCACHE': str(module / 'go-cache')}
        for binary, package in [('mysql-copy-live-driver', '.'),
                                ('source-profile-renderer', 'github.com/envplane/control-plane/apps/pvc-copy-source-profile')]:
            subprocess.run(['go', 'build', '-mod=mod', '-trimpath', '-o', str(output / binary), package],
                           cwd=module, env=env, check=True, timeout=300)
    record = json.loads((output / 'build.json').read_text())
    for binary in ('mysql-copy-live-driver', 'source-profile-renderer'):
        record[binary + 'SHA256'] = hashlib.sha256((output / binary).read_bytes()).hexdigest()
    record['suite'] = 'mysql-native-live'
    record['controlPlaneCommit'] = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=workspace / 'control-plane', text=True).strip()
    if snapshot(workspace) != before:
        raise RuntimeError('source changed during build; snapshot is not approved for live execution')
    record['sourceSnapshotSHA256'] = hashlib.sha256(json.dumps(before, sort_keys=True).encode()).hexdigest()
    (output / 'source-snapshot.json').write_text(json.dumps(before, indent=2) + '\n')
    (output / 'build.json').write_text(json.dumps(record, indent=2) + '\n')


if __name__ == '__main__':
    main()
