#!/usr/bin/env python3
"""Bounded fixture-only native MySQL verification. Never reads existing databases.

Metadata/proofs only are retained; credential material and SQL payloads stay in
memory/stdin. All created resources are UID tracked; no existing object adoption.
"""
import argparse
import copy
import datetime
import hashlib
import json
import re
import secrets
import subprocess
import time
from pathlib import Path

CONTEXT = 'kind-envplane-readiness-682'
CLUSTER_UID = '49918e1f-d1f7-4aba-9afb-a4cea4187822'
MYSQL_PARENT = 'docker.io/library/mysql@sha256:ca3f0494c0f1fc86eb45f5e4786a1bb9f64d2f85b562cc74a9595046f6519a42'
KINDS = {'Namespace': 'namespaces', 'ServiceAccount': 'serviceaccounts', 'Secret': 'secrets',
         'ConfigMap': 'configmaps', 'PersistentVolumeClaim': 'persistentvolumeclaims',
         'Service': 'services', 'StatefulSet': 'statefulsets', 'Pod': 'pods',
         'Role': 'roles', 'RoleBinding': 'rolebindings', 'ClusterRole': 'clusterroles',
         'ClusterRoleBinding': 'clusterrolebindings', 'ValidatingAdmissionPolicy': 'validatingadmissionpolicies',
         'ValidatingAdmissionPolicyBinding': 'validatingadmissionpolicybindings'}


def metadata_hash(value):
    # Go encoding/json escapes HTML; CEL strings can contain operators (<, >, &).
    raw = json.dumps(value, sort_keys=True, separators=(',', ':'), ensure_ascii=False)
    for char, escaped in [('&', '\\u0026'), ('<', '\\u003c'), ('>', '\\u003e'),
                          ('\u2028', '\\u2028'), ('\u2029', '\\u2029')]:
        raw = raw.replace(char, escaped)
    return hashlib.sha256(raw.encode()).hexdigest()


def obj(kind, name, ns='', spec=None, **extra):
    api = 'v1'
    if kind == 'StatefulSet':
        api = 'apps/v1'
    elif 'Role' in kind:
        api = 'rbac.authorization.k8s.io/v1'
    elif kind.startswith('ValidatingAdmission'):
        api = 'admissionregistration.k8s.io/v1'
    result = {'apiVersion': api, 'kind': kind, 'metadata': {'name': name}}
    if ns:
        result['metadata']['namespace'] = ns
    if spec is not None:
        result['spec'] = spec
    return {**result, **extra}


class Fixture:
    def __init__(self, args):
        self.args = args
        self.run = args.run_id
        if not re.fullmatch('[a-f0-9]{16}', self.run) or args.authorize_fixture != self.run:
            raise ValueError('explicit exact fixture run authorization required')
        self.src = f'mysqlcopy-live-{self.run}-src'
        self.dst = f'mysqlcopy-live-{self.run}-dst'
        self.build_dir = Path(args.build_record).resolve().parent
        self.build = json.loads(Path(args.build_record).read_text())
        mysql_record = json.loads(Path(args.mysql_image_record).read_text())
        if (mysql_record['runID'] != self.run or mysql_record['parentImage'] != MYSQL_PARENT
                or not mysql_record.get('filesystemLayersUnchanged') or not mysql_record.get('existingAliasesUnchanged')
                or mysql_record.get('clusterUID') != CLUSTER_UID
                or not mysql_record.get('singletonIndexVerified')
                or mysql_record['image'].split('@')[1] != mysql_record['indexDigest']
                or not re.fullmatch(re.escape(f'docker.io/aaa-envplane-fixture/mysqlcopy-{self.run}') + r'@sha256:[a-f0-9]{64}', mysql_record['image'])):
            raise ValueError('unique MySQL fixture image provenance missing')
        self.mysql = mysql_record['image']
        if self.build['runID'] != self.run or self.build.get('suite') != 'mysql-native-live' or not self.build['archiveBinaryVerified']:
            raise ValueError('build provenance mismatch')
        for binary in ('mysql-copy-live-driver', 'source-profile-renderer'):
            if hashlib.sha256((self.build_dir / binary).read_bytes()).hexdigest() != self.build[binary + 'SHA256']:
                raise ValueError('host binary changed')
        self.ledger = {'runID': self.run, 'context': CONTEXT, 'clusterUID': CLUSTER_UID,
                       'mysqlImage': self.mysql, 'mysqlImageProvenance': mysql_record, 'helperImage': self.build['image'], 'created': [],
                       'checks': [], 'commands': [], 'cleaned': [], 'livePassed': False}
        self.path = self.build_dir / 'sql-ledger.json'
        if self.path.exists():
            raise ValueError('run already has a ledger; never adopt/reexecute')
        self.refs = {}

    def save(self):
        self.path.write_text(json.dumps(self.ledger, indent=2) + '\n')
        self.path.chmod(0o600)

    def kube(self, args, payload=None, as_runner=False, allow_fail=False):
        prefix = ['kubectl', '--kubeconfig', self.args.kubeconfig, '--context', CONTEXT]
        if as_runner:
            prefix += ['--as', f'system:serviceaccount:{self.dst}:copy-runner']
        # Do not retain exec argv or stdin: it may contain fixture SQL/credentials.
        safe = args if args[0] != 'exec' else ['exec', '[fixture SQL argv redacted]']
        proc = subprocess.run(prefix + args, input=payload, text=True, capture_output=True, timeout=60)
        self.ledger['commands'].append({'args': safe, 'asFixtureRunner': as_runner,
                                        'success': proc.returncode == 0, 'payload': 'not retained'})
        self.save()
        if proc.returncode and not allow_fail:
            # Admission errors are metadata-only, all other arbitrary stderr is discarded.
            if args[0] == 'create' and '--dry-run=server' in args:
                self.ledger['admissionError'] = proc.stderr[:16000]
                self.save()
            raise RuntimeError(f'fixture kubectl {args[0]} failed (payload redacted)')
        return proc

    def get(self, kind, name, ns=''):
        args = ['get', kind, name, '-o', 'json']
        if ns:
            args += ['-n', ns]
        return json.loads(self.kube(args).stdout)

    def create(self, value):
        m = value['metadata']
        ns = m.get('namespace', '')
        existing = self.kube(['get', KINDS[value['kind']], m['name'], *(['-n', ns] if ns else []),
                              '--ignore-not-found', '-o', 'json'])
        if existing.stdout.strip():
            raise RuntimeError('foreign/preexisting fixture object; never adopt')
        # Profile canonical metadata must not be changed after rendering.
        if not value['kind'].startswith('ValidatingAdmission') and 'envplane.io/pvc-copy-onboarding-owner' not in m.get('annotations', {}):
            m.setdefault('labels', {})['envplane.io/mysql-copy-live-run'] = self.run
        created = json.loads(self.kube(['create', '-f', '-', '-o', 'json'], json.dumps(value)).stdout)
        cm = created['metadata']
        record = {'kind': value['kind'], 'apiVersion': value['apiVersion'],
                  'namespace': ns, 'name': cm['name'], 'uid': cm['uid']}
        self.ledger['created'].append(record)
        self.refs[(value['kind'], ns, cm['name'])] = cm['uid']
        self.save()
        return created

    def ref(self, kind, name, ns):
        return {'Namespace': ns, 'Name': name, 'UID': self.refs[(kind, ns, name)]}

    def wait_ready(self, name, ns):
        deadline = time.monotonic() + 240
        while time.monotonic() < deadline:
            p = self.kube(['get', 'pod', name, '-n', ns, '--ignore-not-found', '-o', 'json'])
            if p.stdout.strip():
                pod = json.loads(p.stdout)
                status = pod.get('status', {})
                if any(c.get('type') == 'Ready' and c.get('status') == 'True' for c in status.get('conditions', [])):
                    self.ledger['checks'].append({'readyPod': name, 'uid': pod['metadata']['uid'],
                                                  'imageIDs': [s.get('imageID') for s in status.get('containerStatuses', [])]})
                    self.save()
                    return pod
                # Capture safe event reasons, not logs/config/SQL.
                waiting = [c.get('state', {}).get('waiting', {}).get('reason') for c in status.get('containerStatuses', [])]
                if 'ImagePullBackOff' in waiting or 'CrashLoopBackOff' in waiting:
                    self.ledger['blocker'] = {'pod': name, 'waitingReasons': waiting}
                    self.save()
                    raise RuntimeError('fixture container not ready')
            time.sleep(2)
        raise TimeoutError('fixture pod readiness deadline')

    def bootstrap(self):
        uid = self.get('namespace', 'kube-system')['metadata']['uid']
        if uid != CLUSTER_UID:
            raise RuntimeError('cluster identity mismatch')
        # Both namespaces checked BEFORE either one is created.
        for ns in (self.src, self.dst):
            if self.kube(['get', 'namespace', ns, '--ignore-not-found', '-o', 'json']).stdout.strip():
                raise RuntimeError('namespace exists; never adopt')
        for ns in (self.src, self.dst):
            self.create(obj('Namespace', ns))
        self.create(obj('ServiceAccount', 'copy-runner', self.dst, automountServiceAccountToken=False))
        dns = f'mysql.{self.src}.svc'
        cert = json.loads(subprocess.check_output([str(self.build_dir / 'mysql-copy-live-driver'), 'certificates', dns], text=True))
        passwords = {k: secrets.token_hex(24) for k in ('app', 'backup', 'root', 'writer', 'target', 'targetroot')}
        for name, values in [('source-app', {'password': passwords['app']}),
                             ('source-backup', {'password': passwords['backup']}),
                             ('source-root', {'password': passwords['root']}),
                             ('source-writer', {'password': passwords['writer']}),
                             ('public-ca', {'ca.pem': cert['ca']}),
                             ('private-server-tls', {'ca.pem': cert['ca'], 'server.pem': cert['cert'], 'server.key': cert['key']})]:
            self.create(obj('Secret', name, self.src, type='Opaque', stringData=values))
        self.create(obj('Secret', 'generated-target', self.dst, type='Opaque',
                        stringData={'password': passwords['target'], 'MYSQL_ROOT_PASSWORD': passwords['targetroot']}))
        self.create(obj('Secret', 'invalid-root-target', self.dst, type='Opaque',
                        stringData={'password': passwords['target'], 'MYSQL_ROOT_PASSWORD': passwords['target']}))
        self.create(obj('Secret', 'public-ca', self.dst, type='Opaque', stringData={'ca.pem': cert['ca']}))
        sql = f"""REVOKE ALL PRIVILEGES, GRANT OPTION FROM 'appread'@'%';
GRANT SELECT, SHOW VIEW ON fixturedb.* TO 'appread'@'%';
CREATE USER 'backupadmin'@'%' IDENTIFIED BY '{passwords['backup']}' REQUIRE SSL;
GRANT BACKUP_ADMIN, SHOW_ROUTINE ON *.* TO 'backupadmin'@'%';
GRANT SELECT, SHOW VIEW, TRIGGER, EVENT ON fixturedb.* TO 'backupadmin'@'%';
CREATE USER 'writer'@'%' IDENTIFIED BY '{passwords['writer']}' REQUIRE SSL;
GRANT INSERT ON fixturedb.* TO 'writer'@'%';
ALTER USER 'appread'@'%' REQUIRE SSL;
USE fixturedb;
CREATE TABLE records(id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY, payload VARBINARY(128) NOT NULL) ENGINE=InnoDB;
INSERT INTO records(payload) VALUES ('fixture-marker-{self.run}');
"""
        # Enough snapshot work for active writer/DDL probes, with strictly bounded rows.
        sql += "INSERT INTO records(payload) SELECT REPEAT('x',128) FROM records;\n" * 12
        self.create(obj('Secret', 'fixture-init', self.src, type='Opaque', stringData={'01-fixture.sql': sql}))
        del passwords, sql, cert
        self.create(obj('ConfigMap', 'fixture-config', self.src, data={'fixture.cnf':
            '[mysqld]\nrequire_secure_transport=ON\nssl-ca=/tls/ca.pem\nssl-cert=/tls/server.pem\nssl-key=/tls/server.key\n'}))
        self.create(obj('PersistentVolumeClaim', 'source', self.src,
                        {'accessModes': ['ReadWriteOnce'], 'storageClassName': 'standard', 'volumeMode': 'Filesystem',
                         'resources': {'requests': {'storage': '1Gi'}}}))
        self.create(obj('PersistentVolumeClaim', 'filesystem-probe', self.src,
                        {'accessModes': ['ReadWriteOnce'], 'storageClassName': 'standard', 'volumeMode': 'Filesystem',
                         'resources': {'requests': {'storage': '64Mi'}}}))
        self.create(obj('Service', 'mysql', self.src, {'selector': {'fixture': self.run},
                        'ports': [{'port': 3306, 'targetPort': 3306, 'name': 'mysql'}]}))
        def envsecret(key, name):
            return {'name': key, 'valueFrom': {'secretKeyRef': {'name': name, 'key': 'password'}}}
        container = {'name': 'mysql', 'image': self.mysql, 'imagePullPolicy': 'IfNotPresent',
            'env': [{'name': 'MYSQL_DATABASE', 'value': 'fixturedb'}, {'name': 'MYSQL_USER', 'value': 'appread'},
                    envsecret('MYSQL_PASSWORD', 'source-app'), envsecret('MYSQL_ROOT_PASSWORD', 'source-root'),
                    {'name': 'MYSQL_ROOT_HOST', 'value': '%'}],
            'ports': [{'containerPort': 3306}],
            'volumeMounts': [{'name': 'data', 'mountPath': '/var/lib/mysql'},
                             {'name': 'tls', 'mountPath': '/tls', 'readOnly': True},
                             {'name': 'config', 'mountPath': '/etc/mysql/conf.d', 'readOnly': True},
                             {'name': 'init', 'mountPath': '/docker-entrypoint-initdb.d', 'readOnly': True}],
            'readinessProbe': {'tcpSocket': {'port': 3306}, 'periodSeconds': 2},
            'resources': {'requests': {'cpu': '100m', 'memory': '256Mi'}, 'limits': {'cpu': '2', 'memory': '1Gi'}}}
        self.create(obj('StatefulSet', 'mysql', self.src, {'replicas': 1, 'serviceName': 'mysql',
            'selector': {'matchLabels': {'fixture': self.run}},
            'template': {'metadata': {'labels': {'fixture': self.run, 'envplane.io/mysql-copy-live-run': self.run}},
                         'spec': {'automountServiceAccountToken': False, 'containers': [container],
                                  'volumes': [{'name': 'data', 'persistentVolumeClaim': {'claimName': 'source'}},
                                              {'name': 'tls', 'secret': {'secretName': 'private-server-tls', 'defaultMode': 292}},
                                              {'name': 'config', 'configMap': {'name': 'fixture-config'}},
                                              {'name': 'init', 'secret': {'secretName': 'fixture-init'}}]}}}))
        self.wait_ready('mysql-0', self.src)
        pod = self.get('pod', 'mysql-0', self.src)
        actual = pod['status']['containerStatuses'][0]['imageID']
        if actual != self.mysql:
            self.ledger['blocker'] = {'requestedMySQLImage': self.mysql, 'actualImageID': actual}
            self.save()
            raise RuntimeError('exact running MySQL fixture imageID mismatch')
        self.client('writer', 'source-writer', 'writer', writer=True)
        self.client('diagnostics', 'source-root', 'root', writer=False)

    def client(self, name, secret, user, writer, namespace=None, password_key='password'):
        ns = namespace or self.src
        volumes = [{'name': n, 'emptyDir': {'medium': 'Memory'}} for n in ('config', 'tmp', 'run')]
        volumes += [{'name': 'credentials', 'projected': {'defaultMode': 256, 'sources': [
            {'secret': {'name': secret, 'items': [{'key': password_key, 'path': 'password'}]}},
            {'secret': {'name': 'public-ca', 'items': [{'key': 'ca.pem', 'path': 'ca.pem', 'mode': 292}]}}]}}]
        mounts = [{'name': 'config', 'mountPath': '/config'}, {'name': 'tmp', 'mountPath': '/tmp'},
                  {'name': 'run', 'mountPath': '/run/mysqld'}, {'name': 'credentials', 'mountPath': '/credentials', 'readOnly': True}]
        sqlargs = f"--defaults-extra-file=/config/app.cnf --host=mysql.{self.src}.svc --ssl-mode=VERIFY_IDENTITY --ssl-ca=/credentials/ca.pem"
        command = ['sleep', '900']
        if writer:
            command = ['sh', '-c', f"while true; do mysql {sqlargs} -e \"INSERT INTO fixturedb.records(payload) VALUES ('active-writer')\" || exit 1; sleep 0.2; done"]
        spec = {'restartPolicy': 'Never', 'activeDeadlineSeconds': 900, 'automountServiceAccountToken': False,
            'initContainers': [{'name': 'config', 'image': self.build['image'], 'command': ['envplane-runner'],
                'args': ['mysql-client-config', user, '/credentials/password', '/config/app.cnf'],
                'securityContext': {'runAsUser': 0, 'runAsGroup': 0, 'allowPrivilegeEscalation': False,
                                    'capabilities': {'drop': ['ALL'], 'add': ['CHOWN', 'FOWNER', 'DAC_OVERRIDE']}},
                'volumeMounts': mounts}],
            'containers': [{'name': 'mysql', 'image': self.mysql, 'command': command,
                            'securityContext': {'runAsUser': 999, 'runAsGroup': 999, 'runAsNonRoot': True,
                                'allowPrivilegeEscalation': False, 'readOnlyRootFilesystem': True,
                                'capabilities': {'drop': ['ALL']}}, 'volumeMounts': mounts}], 'volumes': volumes}
        self.create(obj('Pod', name, ns, spec))
        self.wait_ready(name, ns)

    def query(self, sql, allow_fail=False):
        return self.kube(['exec', 'diagnostics', '-n', self.src, '-c', 'mysql', '--', 'mysql',
            '--defaults-extra-file=/config/app.cnf', f'--host=mysql.{self.src}.svc',
            '--ssl-mode=VERIFY_IDENTITY', '--ssl-ca=/credentials/ca.pem', '--batch', '--skip-column-names', '-e', sql], allow_fail=allow_fail)

    def profile(self):
        s = {'tenantId': 'fixture', 'namespace': self.src, 'pvcName': 'source',
             'pvcUid': self.ref('PersistentVolumeClaim', 'source', self.src)['UID'],
             'workloadKind': 'StatefulSet', 'workloadName': 'mysql',
             'workloadUid': self.ref('StatefulSet', 'mysql', self.src)['UID'],
             'container': 'mysql', 'database': 'fixturedb', 'username': 'appread',
             'secretName': 'source-app', 'secretUid': self.ref('Secret', 'source-app', self.src)['UID'],
             'passwordKey': 'password', 'sourceImage': self.mysql, 'storageClass': 'standard',
             'accessModes': ['ReadWriteOnce'], 'requestedBytes': 1 << 30, 'environmentClass': 'test',
             'service': 'mysql', 'serviceUid': self.ref('Service', 'mysql', self.src)['UID'], 'port': 3306,
             'backupAdminSecretRef': {'namespace': self.src, 'name': 'source-backup',
                'uid': self.ref('Secret', 'source-backup', self.src)['UID'], 'username': 'backupadmin', 'passwordKey': 'password'},
             'tls': {'caSecretName': 'public-ca', 'caSecretUid': self.ref('Secret', 'public-ca', self.src)['UID'],
                     'caKey': 'ca.pem', 'serverName': f'mysql.{self.src}.svc'}}
        value = {'tenantId': 'fixture', 'projectId': self.run, 'clusterId': 'isolated-kind', 'clusterUid': CLUSTER_UID,
                 'runnerNamespace': self.dst, 'runnerServiceAccount': 'copy-runner', 'runnerImage': self.build['image'],
                 'mysqlSources': [s], 'mysqlRestoreHelperImage': self.build['image'], 'mysqlRestoreTargetImages': [self.mysql],
                 'allowRootHelpers': True, 'mysqlRestoreAllowRootInit': True,
                 'filesystemSources': [{'tenantId': 'fixture', 'namespace': self.src, 'name': 'filesystem-probe',
                    'uid': self.ref('PersistentVolumeClaim', 'filesystem-probe', self.src)['UID'],
                    'storageClass': 'standard', 'accessModes': ['ReadWriteOnce'], 'requestedBytes': 64 << 20,
                    'volumeMode': 'Filesystem', 'environmentClass': 'test'}]}
        proc = subprocess.run([str(self.build_dir / 'source-profile-renderer'), '-format', 'review'],
                              input=json.dumps(value), text=True, capture_output=True, timeout=20)
        if proc.returncode:
            self.ledger['profileError'] = proc.stderr[:4000]
            self.save()
            raise RuntimeError('native SQL profile renderer refused fixture metadata')
        review = json.loads(proc.stdout)
        (self.build_dir / 'sql-profile-review.json').write_text(json.dumps(review, indent=2) + '\n')
        created = [self.create(copy.deepcopy(o)) for o in review['objects']]
        policies = [o for o in created if o['kind'] == 'ValidatingAdmissionPolicy']
        if len(policies) != 1:
            raise RuntimeError('expected one combined source policy')
        policy = policies[0]
        deadline = time.monotonic() + 30
        while time.monotonic() < deadline:
            live = self.get('validatingadmissionpolicy', policy['metadata']['name'])
            status = live.get('status', {})
            if status.get('observedGeneration') == live['metadata']['generation'] and 'typeChecking' in status:
                if status['typeChecking'].get('expressionWarnings'):
                    self.ledger['CELTypeErrors'] = status['typeChecking']['expressionWarnings']
                    self.save()
                    raise RuntimeError('actual SQL CEL type-check warnings')
                policy = live
                break
            time.sleep(1)
        else:
            raise RuntimeError('SQL policy generation was not typechecked')
        bindings = [o for o in created if o['kind'] == 'ValidatingAdmissionPolicyBinding' and o['spec']['policyName'] == policy['metadata']['name']]
        if len(bindings) != 1 or bindings[0]['spec']['validationActions'] != ['Deny']:
            raise RuntimeError('expected exact Deny binding')
        binding = self.get('validatingadmissionpolicybinding', bindings[0]['metadata']['name'])
        self.ledger['checks'].append({'policy': policy['metadata']['name'], 'generation': policy['metadata']['generation'],
                                      'observedGeneration': policy['status']['observedGeneration'], 'typeChecking': policy['status']['typeChecking']})
        self.save()
        # Target namespace authority is a finite fixture Role, not cluster-admin.
        self.create(obj('Role', 'target', self.dst, rules=[
            {'apiGroups': [''], 'resources': ['pods', 'persistentvolumeclaims', 'configmaps'], 'verbs': ['get', 'list', 'create', 'delete']},
            {'apiGroups': [''], 'resources': ['pods/exec'], 'verbs': ['create']},
            {'apiGroups': [''], 'resources': ['secrets'], 'resourceNames': ['generated-target', 'invalid-root-target'], 'verbs': ['get']}]))
        self.create(obj('RoleBinding', 'target', self.dst, roleRef={'apiGroup': 'rbac.authorization.k8s.io', 'kind': 'Role', 'name': 'target'},
            subjects=[{'kind': 'ServiceAccount', 'namespace': self.dst, 'name': 'copy-runner'}]))
        reader = 'mysqlcopy-live-' + self.run + '-target-ns'
        self.create(obj('ClusterRole', reader, rules=[{'apiGroups': [''], 'resources': ['namespaces'],
                                                     'resourceNames': [self.dst], 'verbs': ['get']}]))
        self.create(obj('ClusterRoleBinding', reader,
            roleRef={'apiGroup': 'rbac.authorization.k8s.io', 'kind': 'ClusterRole', 'name': reader},
            subjects=[{'kind': 'ServiceAccount', 'namespace': self.dst, 'name': 'copy-runner'}]))
        self.fences = [{'Namespace': self.src, 'PolicyName': policy['metadata']['name'], 'PolicyUID': policy['metadata']['uid'],
            'PolicySpecSHA256': metadata_hash(policy['spec']), 'BindingName': binding['metadata']['name'],
            'BindingUID': binding['metadata']['uid'], 'BindingSpecSHA256': metadata_hash(binding['spec'])}]
        config = self.config(self.plan('copy-positive'), 'positive')
        pod = json.loads(subprocess.check_output([str(self.build_dir / 'mysql-copy-live-driver'), 'source-probe'],
                            input=json.dumps(config), text=True))
        for challenge in ('allowed', 'secret', 'pvc', 'fsGroup', 'selinux', 'command', 'unrelated'):
            probe = copy.deepcopy(pod)
            spec = probe['spec']
            if challenge == 'secret':
                spec['volumes'][-1]['projected']['sources'][0]['secret']['name'] = 'private-server-tls'
            elif challenge == 'pvc':
                spec['volumes'].append({'name': 'forbidden', 'persistentVolumeClaim': {'claimName': 'source', 'readOnly': True}})
            elif challenge == 'fsGroup':
                spec['securityContext']['fsGroup'] = 999
            elif challenge == 'selinux':
                spec['securityContext']['seLinuxOptions'] = {'level': 's0'}
            elif challenge == 'command':
                spec['initContainers'][0]['command'] = ['sh']
            elif challenge == 'unrelated':
                probe['metadata']['name'] = 'unrelated'
            result = self.kube(['create', '--dry-run=server', '-f', '-', '-o', 'json'],
                               json.dumps(probe), as_runner=True, allow_fail=True)
            if challenge == 'allowed':
                if result.returncode:
                    self.ledger['admissionError'] = result.stderr[:16000]
                    self.save()
                    raise RuntimeError('mixed source policy denied actual SQL helper')
            else:
                expected = policy['spec']['validations'][0]['message']
                if result.returncode == 0 or expected not in result.stderr or policy['metadata']['name'] not in result.stderr or binding['metadata']['name'] not in result.stderr:
                    self.ledger['admissionError'] = result.stderr[:16000]
                    self.save()
                    raise RuntimeError(f'actual mixed source Deny not proven: {challenge}')
            self.ledger['checks'].append({'mixedAdmissionChallenge': challenge, 'passed': True})
            self.save()
        # Positive filesystem exception in the SAME effective mixed policy. This
        # is admission-only; no Pod is persisted or source data mounted/read.
        identity = f"{self.src}/filesystem-probe/{self.ref('PersistentVolumeClaim', 'filesystem-probe', self.src)['UID']}"
        fs_pod = obj('Pod', 'pvccopy-source-' + hashlib.sha256(identity.encode()).hexdigest()[:24], self.src,
            {'serviceAccountName': 'default', 'automountServiceAccountToken': False, 'restartPolicy': 'Never',
             'activeDeadlineSeconds': 60, 'terminationGracePeriodSeconds': 5,
             'securityContext': {'runAsNonRoot': True, 'runAsUser': 10001, 'runAsGroup': 10001, 'seccompProfile': {'type': 'RuntimeDefault'}},
             'containers': [{'name': 'copy', 'image': self.build['image'], 'command': ['sleep'], 'args': ['60'],
                'securityContext': {'allowPrivilegeEscalation': False, 'readOnlyRootFilesystem': True, 'capabilities': {'drop': ['ALL']}},
                'volumeMounts': [{'name': 'data', 'mountPath': '/data', 'readOnly': True, 'recursiveReadOnly': 'Enabled'}]}],
             'volumes': [{'name': 'data', 'persistentVolumeClaim': {'claimName': 'filesystem-probe', 'readOnly': True}}]})
        fs_pod['metadata']['labels'] = {'app.kubernetes.io/component': 'pvccopy-helper'}
        self.kube(['create', '--dry-run=server', '-f', '-', '-o', 'json'], json.dumps(fs_pod), as_runner=True)
        self.ledger['checks'].append({'mixedAdmissionChallenge': 'filesystem-allowed', 'passed': True})
        self.save()

    def plan(self, target):
        digest = 'sha256:' + hashlib.sha256(self.run.encode()).hexdigest()
        credential = lambda name, user, ns: {'Ref': self.ref('Secret', name, ns), 'Username': user, 'PasswordKey': 'password'}
        return {'Binding': f'{self.run}-{target}', 'Tenant': 'fixture', 'Project': self.run, 'Environment': target,
            'EnvironmentCreatedAt': self.created_at, 'DomainPlanDigest': digest, 'SecretMaterializationPlanDigest': digest,
            'Source': {'PVC': self.ref('PersistentVolumeClaim', 'source', self.src), 'StatefulSet': self.ref('StatefulSet', 'mysql', self.src),
                'Container': 'mysql', 'Image': self.mysql, 'Service': 'mysql', 'ServiceUID': self.ref('Service', 'mysql', self.src)['UID'],
                'Port': 3306, 'Database': 'fixturedb', 'Credentials': credential('source-app', 'appread', self.src),
                'BackupAdminSecretRef': credential('source-backup', 'backupadmin', self.src),
                'TLSCASecret': self.ref('Secret', 'public-ca', self.src), 'TLSCAKey': 'ca.pem', 'TLSServerName': f'mysql.{self.src}.svc'},
            'Target': {'Namespace': self.dst, 'PVCName': target, 'StorageClass': 'standard', 'Image': self.mysql, 'Database': 'fixturedb',
                'RequestedBytes': 1 << 30, 'Credentials': credential('generated-target', 'featureapp', self.dst), 'RootPasswordKey': 'MYSQL_ROOT_PASSWORD'},
            'ConfigImage': self.build['image'], 'DDLMode': 'backup_lock', 'MaxBytes': 16 << 20, 'MaxStatementBytes': 4 << 20,
            'MaxTables': 10, 'MaxRows': 50000, 'Timeout': 180000000000}

    def config(self, plan, mode):
        return {'RunID': self.run, 'Kubeconfig': self.args.kubeconfig, 'ClusterUID': CLUSTER_UID,
                  'SourceNamespaceUID': self.ref('Namespace', self.src, '')['UID'],
                  'TargetNamespaceUID': self.ref('Namespace', self.dst, '')['UID'],
                  'Plan': plan, 'Fences': self.fences, 'Mode': mode,
                  'Journal': str(self.build_dir / 'sql-native-commands.jsonl')}
    def native(self, plan, mode):
        config = self.config(plan, mode)
        (self.build_dir / f'sql-plan-{mode}.json').write_text(json.dumps(config, indent=2) + '\n')
        p = subprocess.run([str(self.build_dir / 'mysql-copy-live-driver')], input=json.dumps(config),
                           text=True, capture_output=True, timeout=300)
        result = json.loads(p.stdout) if p.stdout.strip() else {'success': False, 'error': 'native adapter returned no metadata'}
        self.ledger['checks'].append({'nativeMode': mode, 'result': result})
        self.save()
        return result

    def execute(self):
        self.created_at = datetime.datetime.now(datetime.timezone.utc).isoformat().replace('+00:00', 'Z')
        self.bootstrap()
        before = self.query('SELECT COUNT(*), MAX(id), @@server_uuid FROM fixturedb.records').stdout.strip()
        schema_query = "SELECT COLUMN_NAME,COLUMN_TYPE,IS_NULLABLE,COLUMN_KEY,EXTRA FROM information_schema.COLUMNS WHERE TABLE_SCHEMA='fixturedb' AND TABLE_NAME='records' ORDER BY ORDINAL_POSITION"
        schema_before = self.query(schema_query).stdout
        self.profile()
        # Exact private source secrets must not be readable by the copy principal.
        for name in ('source-root', 'source-writer', 'private-server-tls', 'fixture-init'):
            p = self.kube(['get', 'secret', name, '-n', self.src, '-o', 'name'], as_runner=True, allow_fail=True)
            if p.returncode == 0 or 'Forbidden' not in p.stderr:
                raise RuntimeError('source private credential isolation failed')
        stale = self.plan('copy-uid-negative')
        stale['Source']['PVC']['UID'] = 'stale-fixture-source-uid'
        result = self.native(stale, 'positive')
        if result['success'] or not result.get('sourceUIDMismatchObserved') or result.get('restoreAttempted') or self.kube(['get', 'pvc', 'copy-uid-negative', '-n', self.dst, '--ignore-not-found', '-o', 'name']).stdout.strip():
            raise RuntimeError('actual stale source UID did not fail before target writes')
        self.ledger['checks'].append({'sourceUIDDriftRefusedBeforeTarget': True, 'method': 'stale plan UID vs actual current GET UID; source not replaced'})
        root_duplicate = self.plan('copy-root-negative')
        root_duplicate['Target']['Credentials']['Ref'] = self.ref('Secret', 'invalid-root-target', self.dst)
        result = self.native(root_duplicate, 'positive')
        if result['success'] or result.get('errorCode') != 'safety_refusal' or result.get('restoreAttempted') or self.kube(['get', 'pvc', 'copy-root-negative', '-n', self.dst, '--ignore-not-found', '-o', 'name']).stdout.strip():
            raise RuntimeError('duplicate root/app target credentials did not fail before target writes')
        self.ledger['checks'].append({'duplicateTargetRootRefusedBeforeTarget': True})
        # Real authentication challenge uses a fresh client Pod, never existing
        # source Pod exec. Target root credential must NOT authenticate at source.
        self.client('target-root-probe', 'generated-target', 'root', writer=False, namespace=self.dst, password_key='MYSQL_ROOT_PASSWORD')
        challenge = self.kube(['exec', 'target-root-probe', '-n', self.dst, '-c', 'mysql', '--', 'mysql',
            '--defaults-extra-file=/config/app.cnf', f'--host=mysql.{self.src}.svc', '--ssl-mode=VERIFY_IDENTITY',
            '--ssl-ca=/credentials/ca.pem', '-e', 'SELECT 1'], allow_fail=True)
        if challenge.returncode == 0 or 'ERROR 1045' not in challenge.stderr:
            raise RuntimeError('target root isolation real authentication challenge not proven')
        self.ledger['checks'].append({'targetRootCannotAuthenticateSource': True, 'mysqlError': 1045})
        # Config ownership and helper binary checks are metadata only.
        root_hash = self.kube(['exec', 'target-root-probe', '-n', self.dst, '-c', 'mysql', '--',
                              'stat', '-c', '%u:%g:%a', '/config/app.cnf']).stdout.strip()
        if root_hash != '999:999:600':
            raise RuntimeError('actual tmpfs client config ownership mismatch')
        self.ledger['checks'].append({'targetClientConfigOwnership': root_hash})
        positive = self.native(self.plan('copy-positive'), 'positive')
        if not positive['success']:
            raise RuntimeError('real native positive copy refused; see ledger')
        retry = self.native(self.plan('copy-positive'), 'retry')
        if not retry['success'] or retry['receipt'] != positive['receipt']:
            raise RuntimeError('completed restart retry proof differs')
        cancelled = self.native(self.plan('copy-cancel'), 'cancel')
        if cancelled['success'] or cancelled.get('cancelInputBytes', 0) < 1024:
            raise RuntimeError('actual restore cancellation not proven')
        if cancelled.get('errorCode') != 'cancelled' or cancelled.get('cleanupError') or cancelled.get('cleanupContextError') or 'release_ddl' in cancelled.get('failureStages', []):
            raise RuntimeError('cancellation included an unexpected release/cleanup failure; not accepted')
        partial = self.native(self.plan('copy-cancel'), 'retry')
        if partial['success'] or partial.get('errorCode') != 'partial_target' or partial.get('restoreAttempted'):
            raise RuntimeError('partial target retry not fail-closed')
        after = self.query('SELECT COUNT(*), MAX(id), @@server_uuid FROM fixturedb.records').stdout.strip()
        self.ledger['checks'].append({'sourceBefore': before, 'sourceAfter': after})
        if self.query(schema_query).stdout != schema_before:
            raise RuntimeError('source schema changed across copy/negative probes')
        marker = self.query(f"SELECT COUNT(*) FROM fixturedb.records WHERE payload='fixture-marker-{self.run}'").stdout.strip()
        if marker != '1' or self.get('pvc', 'source', self.src)['metadata']['uid'] != self.ref('PersistentVolumeClaim', 'source', self.src)['UID']:
            raise RuntimeError('source marker or PVC UID changed')
        self.ledger['checks'].append({'sourceSchemaPreservedSHA256': hashlib.sha256(schema_before.encode()).hexdigest(),
                                      'sourceMarkerCount': 1, 'sourcePVCUIDPreserved': True})
        if int(after.split('\t')[0]) <= int(before.split('\t')[0]) or after.split('\t')[2] != before.split('\t')[2]:
            raise RuntimeError('source writer continuity/server identity not proven')
        if not positive.get('DDLBlockedByBackupLock'):
            raise RuntimeError('in-hold real DDL challenge missing')
        self.ledger['nativeCopyPassed'] = True
        self.ledger['checksPassed'] = True
        self.save()

    def cleanup(self):
        errors = []
        volumes = []
        # Track only PVs bound to claims inside the exact new UID-owned namespaces.
        for ns in (self.src, self.dst):
            if ('Namespace', '', ns) not in self.refs:
                continue
            try:
                if self.get('namespace', ns)['metadata']['uid'] != self.ref('Namespace', ns, '')['UID']:
                    raise RuntimeError('fixture namespace UID changed before storage ledger')
                claims = json.loads(self.kube(['get', 'pvc', '-n', ns, '-o', 'json']).stdout)['items']
                for claim in claims:
                    name = claim.get('spec', {}).get('volumeName')
                    if not name:
                        continue
                    pv = self.get('pv', name)
                    if pv['spec']['claimRef']['uid'] != claim['metadata']['uid'] or pv['spec'].get('persistentVolumeReclaimPolicy') != 'Delete':
                        raise RuntimeError('fixture PV ownership/reclaim policy mismatch')
                    volumes.append({'name': name, 'uid': pv['metadata']['uid'], 'claimUID': claim['metadata']['uid']})
            except Exception:
                errors.append({'storageLedgerFailed': ns})
        self.ledger['ownedVolumes'] = volumes
        self.save()
        # Namespace deletion cleans only newly-created fixture descendants; cluster
        # grants/policies are individually removed using exact UID preconditions.
        for r in reversed(self.ledger['created']):
            if r['namespace']:
                continue
            api = r['apiVersion']
            prefix = '/api/v1' if api == 'v1' else '/apis/' + api
            endpoint = f"{prefix}/{KINDS[r['kind']]}/{r['name']}"
            options = {'apiVersion': 'v1', 'kind': 'DeleteOptions', 'preconditions': {'uid': r['uid']}, 'propagationPolicy': 'Foreground'}
            p = self.kube(['delete', '--raw', endpoint, '-f', '-'], json.dumps(options), allow_fail=True)
            if p.returncode:
                errors.append(r)
            else:
                self.ledger['cleaned'].append(r)
        deadline = time.monotonic() + 120
        for ns in (self.src, self.dst):
            if ('Namespace', '', ns) not in self.refs:
                continue
            while time.monotonic() < deadline:
                p = self.kube(['get', 'namespace', ns, '--ignore-not-found', '-o', 'name'])
                if not p.stdout.strip():
                    break
                time.sleep(2)
            else:
                errors.append({'namespaceStillPresent': ns})
        self.ledger['cleanupErrors'] = errors
        for volume in volumes:
            deadline = time.monotonic() + 90
            while time.monotonic() < deadline:
                p = self.kube(['get', 'pv', volume['name'], '--ignore-not-found', '-o', 'json'])
                if not p.stdout.strip():
                    self.ledger.setdefault('reclaimedVolumes', []).append(volume)
                    break
                if json.loads(p.stdout)['metadata']['uid'] != volume['uid']:
                    errors.append({'foreignPVReplacement': volume['name']})
                    break
                time.sleep(2)
            else:
                errors.append({'PVNotReclaimed': volume['name']})
        self.ledger['cleanupErrors'] = errors
        self.save()
        if errors:
            raise RuntimeError('fixture cleanup incomplete; exact UIDs retained')


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--run-id', required=True)
    p.add_argument('--kubeconfig', required=True)
    p.add_argument('--build-record', required=True)
    p.add_argument('--mysql-image-record', required=True, help='verified unique fixture mysql-load.json')
    p.add_argument('--authorize-fixture', required=True)
    args = p.parse_args()
    fixture = Fixture(args)
    try:
        fixture.execute()
    except Exception as error:
        fixture.ledger['error'] = str(error)
        fixture.save()
        raise
    finally:
        fixture.cleanup()
    fixture.ledger['livePassed'] = fixture.ledger.get('checksPassed', False) and fixture.ledger['cleanupErrors'] == []
    fixture.save()
    print(json.dumps({'ledger': str(fixture.path), 'livePassed': fixture.ledger['livePassed']}))


if __name__ == '__main__':
    main()
