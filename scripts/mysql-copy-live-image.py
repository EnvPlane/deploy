#!/usr/bin/env python3
"""Build/load a unique immutable MySQL fixture image; no existing aliases changed."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import tarfile

PARENT = 'docker.io/library/mysql@sha256:ca3f0494c0f1fc86eb45f5e4786a1bb9f64d2f85b562cc74a9595046f6519a42'
CLUSTER_UID = '49918e1f-d1f7-4aba-9afb-a4cea4187822'
NODE = 'envplane-readiness-682-control-plane'
REPOSITORY = 'ghcr.io/envplane/mysqlcopy-fixture'


def index_proof(path, platform_digest):
    with tarfile.open(path) as archive:
        raw = archive.extractfile('index.json').read()
    index = json.loads(raw)
    if index.get('mediaType') != 'application/vnd.oci.image.index.v1+json' or len(index.get('manifests', [])) != 1:
        raise ValueError('approved fixture index must have one descriptor')
    descriptor = index['manifests'][0]
    if descriptor['digest'] != platform_digest or descriptor.get('platform') != {'architecture': 'arm64', 'os': 'linux'}:
        raise ValueError('approved singleton index platform/manifest mismatch')
    return {'indexDigest': sha(raw), 'indexDescriptor': descriptor, 'singletonIndexVerified': True}


def sha(data):
    return 'sha256:' + hashlib.sha256(data).hexdigest()


def command(args):
    return subprocess.check_output(args, timeout=300, text=True).strip()


def verified_blob(archive, digest):
    if not re.fullmatch('sha256:[a-f0-9]{64}', digest):
        raise ValueError('invalid OCI descriptor')
    data = archive.extractfile('blobs/sha256/' + digest.split(':')[1]).read()
    if sha(data) != digest:
        raise ValueError('OCI content digest mismatch')
    return data


def inspect_archive(path, digest, run_id, parent):
    with tarfile.open(path) as archive:
        manifest = json.loads(verified_blob(archive, digest))
        config_raw = verified_blob(archive, manifest['config']['digest'])
        config = json.loads(config_raw)
        if config['architecture'] != 'arm64' or config['os'] != 'linux':
            raise ValueError('fixture image architecture mismatch')
        labels = config['config']['Labels']
        if labels.get('envplane.io/mysql-copy-live-run') != run_id or labels.get('envplane.io/mysql-copy-parent') != PARENT:
            raise ValueError('fixture image provenance labels mismatch')
        if [x['digest'] for x in manifest['layers']] != [x['digest'] for x in parent['layers']]:
            raise ValueError('fixture changed parent filesystem layer digests')
        # Verify all layers, not merely their descriptors. No output extraction.
        for layer in manifest['layers']:
            verified_blob(archive, layer['digest'])
        return {'configDigest': manifest['config']['digest'], 'layerDigests': [x['digest'] for x in manifest['layers']],
                'rootfsDiffIDs': config['rootfs']['diff_ids'], 'mysqlEntrypoint': config['config']['Entrypoint'],
                'mysqlCmd': config['config']['Cmd'], 'filesystemLayersUnchanged': True}


def build(args):
    output = Path(args.output_dir).resolve()
    output.mkdir(mode=0o700, parents=True, exist_ok=False)
    # Content-addressed official platform manifest, no tag resolution or credentials.
    raw = subprocess.check_output(['docker', 'buildx', 'imagetools', 'inspect', '--raw', PARENT], timeout=90)
    if sha(raw) != PARENT.split('@')[1]:
        raw = raw.rstrip(b'\n')
    if sha(raw) != PARENT.split('@')[1]:
        raise ValueError('trusted parent manifest digest mismatch')
    parent = json.loads(raw)
    if 'layers' not in parent:
        raise ValueError('parent must be exact platform manifest, not index')
    (output / 'parent-manifest.json').write_bytes(raw)
    (output / 'Dockerfile').write_text(f'FROM {PARENT}\nLABEL envplane.io/mysql-copy-live-run="{args.run_id}" envplane.io/mysql-copy-parent="{PARENT}"\n')
    tag = f'{REPOSITORY}:mysqlcopy-live-{args.run_id}'
    subprocess.run(['docker', 'buildx', 'build', '--network=none', '--pull=false', '--platform', 'linux/arm64',
                    '--provenance=false', '--sbom=false', '--tag', tag, '--metadata-file', str(output / 'metadata.json'),
                    '--output', f'type=oci,dest={output / "mysql.oci.tar"}', str(output)], check=True, timeout=300)
    digest = json.loads((output / 'metadata.json').read_text())['containerimage.digest']
    if digest == PARENT.split('@')[1]:
        raise ValueError('fixture image is not uniquely identified')
    proof = inspect_archive(output / 'mysql.oci.tar', digest, args.run_id, parent)
    index = index_proof(output / 'mysql.oci.tar', digest)
    # A new uniquely named fixture repository precedes the synthetic import
    # alias in CRI metadata ordering. Both refer to this exact approved index;
    # no platform/index equivalence is accepted at runtime.
    index_repository = f'docker.io/aaa-envplane-fixture/mysqlcopy-{args.run_id}'
    record = {'runID': args.run_id, 'parentImage': PARENT, 'image': index_repository + '@' + index['indexDigest'],
              'platformImage': REPOSITORY + '@' + digest, 'platformDigest': digest,
              'localTag': tag, 'archive': 'mysql.oci.tar', 'archiveSHA256': hashlib.sha256((output / 'mysql.oci.tar').read_bytes()).hexdigest(),
              'pushed': False, 'loaded': False, **proof, **index}
    (output / 'mysql-image.json').write_text(json.dumps(record, indent=2) + '\n')
    print(json.dumps(record, indent=2))


def aliases(output):
    return {p[0]: p[2] for line in output.splitlines()[1:] if len(p := line.split()) >= 3}


def load(args):
    path = Path(args.image_record).resolve()
    record = json.loads(path.read_text())
    if record['runID'] != args.run_id or record['parentImage'] != PARENT or not record['filesystemLayersUnchanged']:
        raise ValueError('fixture provenance mismatch')
    if not re.fullmatch(re.escape(f'docker.io/aaa-envplane-fixture/mysqlcopy-{args.run_id}') + r'@sha256:[a-f0-9]{64}', record['image']) or record['localTag'] != f'{REPOSITORY}:mysqlcopy-live-{args.run_id}':
        raise ValueError('unexpected fixture image alias')
    archive = path.parent / 'mysql.oci.tar'
    if hashlib.sha256(archive.read_bytes()).hexdigest() != record['archiveSHA256']:
        raise ValueError('fixture archive changed')
    digest = record['platformDigest']
    inspect_archive(archive, digest, args.run_id, json.loads((path.parent / 'parent-manifest.json').read_text()))
    index = index_proof(archive, digest)
    if record['image'].split('@')[1] != index['indexDigest'] or record['indexDigest'] != index['indexDigest'] or not record['singletonIndexVerified']:
        raise ValueError('approved index content changed')
    uid = command(['kubectl', '--kubeconfig', args.kubeconfig, '--context', 'kind-envplane-readiness-682',
                   'get', 'namespace', 'kube-system', '-o', 'jsonpath={.metadata.uid}'])
    if uid != CLUSTER_UID or command(['kind', 'get', 'nodes', '--name', 'envplane-readiness-682']) != NODE:
        raise ValueError('approved isolated cluster identity mismatch')
    native = ['docker', 'exec', NODE, 'ctr', '--namespace', 'k8s.io', 'images']
    before = aliases(command(native + ['ls']))
    for ref in (record['image'], record['localTag']):
        if ref in before:
            raise ValueError('fixture alias already exists; never adopt/overwrite')
    command(['kind', 'load', 'image-archive', str(archive), '--name', 'envplane-readiness-682'])
    imported = aliases(command(native + ['ls']))
    if imported.get(record['localTag']) != digest:
        raise ValueError('imported fixture manifest mismatch')
    candidates = [ref for ref, target in imported.items() if ref not in before and target == record['indexDigest']
                  and re.fullmatch(r'import-\d{4}-\d{2}-\d{2}@sha256:[a-f0-9]{64}', ref)]
    if len(candidates) != 1:
        raise ValueError('exact newly owned fixture index import unavailable')
    command(native + ['tag', candidates[0], record['image']])
    after = aliases(command(native + ['ls']))
    if after.get(record['image']) != record['indexDigest'] or any(after.get(ref) != d for ref, d in before.items()):
        raise ValueError('fixture load changed existing aliases or failed immutable pin')
    record['loaded'] = True
    record['clusterUID'] = uid
    record['existingAliasesUnchanged'] = True
    record['ownedIndexImportAlias'] = candidates[0]
    cri = json.loads(command(['docker', 'exec', NODE, 'crictl', 'inspecti', record['image']]))
    record['CRIRepoDigests'] = cri['status']['repoDigests']
    if record['image'] not in record['CRIRepoDigests'] or cri['status']['id'] != record['configDigest']:
        raise ValueError('approved singleton index CRI provenance missing')
    (path.parent / 'mysql-load.json').write_text(json.dumps(record, indent=2) + '\n')
    print(json.dumps({'fixtureImage': record['image'], 'clusterUID': uid, 'existingAliasesUnchanged': True}))


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--run-id', required=True)
    sub = p.add_subparsers(dest='mode', required=True)
    b = sub.add_parser('build'); b.add_argument('--output-dir', required=True)
    l = sub.add_parser('load'); l.add_argument('--image-record', required=True)
    l.add_argument('--kubeconfig', required=True); l.add_argument('--authorize-fixture', required=True)
    args = p.parse_args()
    if not re.fullmatch('[a-f0-9]{16}', args.run_id):
        p.error('invalid isolated run ID')
    if args.mode == 'build':
        build(args)
    elif args.authorize_fixture == args.run_id:
        load(args)
    else:
        p.error('exact fixture authorization required')


if __name__ == '__main__':
    main()
