#!/usr/bin/env python3
"""Check the five-machine lab through its Keepalived VIP."""

import json
import pathlib
import subprocess
import time
import urllib.request

VIP = 'http://192.168.56.100'
KEY = '/tmp/otus10/id_ed25519'
results = {'verified': False, 'checks': {}}


def ssh(host, command):
    return subprocess.check_output([
        'ssh', '-i', KEY, '-o', 'IdentitiesOnly=yes',
        '-o', 'StrictHostKeyChecking=no', '-o', 'UserKnownHostsFile=/dev/null',
        f'ubuntu@192.168.56.{host}', command,
    ], text=True, stderr=subprocess.DEVNULL).strip()


def get(path='/health'):
    with urllib.request.urlopen(VIP + path, timeout=8) as response:
        body = response.read()
        assert response.status == 200, response.status
        return response.headers['X-Frontend'], response.headers.get('X-Backend'), body


def wait_for(predicate, label, tries=35):
    for _ in range(tries):
        try:
            data = get()
            if predicate(data):
                return data
        except (OSError, AssertionError):
            pass
        time.sleep(2)
    raise AssertionError(f'Timed out waiting for {label}')


try:
    initial = wait_for(lambda r: r[0] == 'nginx1', 'primary frontend')
    body = json.loads(initial[2])
    assert body['database'] == 'ok' and body['static'] == 'gfs2', body
    results['checks']['initial'] = {'frontend': initial[0], 'backend': body['backend']}

    static = get('/static/index.html')
    assert b'Shared GFS2 static page' in static[2]
    results['checks']['shared_static'] = static[1]

    for host in ('21', '22'):
        assert ssh(host, 'findmnt -n -o FSTYPE /srv/otus-static') == 'gfs2'
        assert 'Shared GFS2 static page' in ssh(host, 'cat /srv/otus-static/index.html')
    results['checks']['gfs2_on_both_backends'] = True

    ssh('21', 'sudo systemctl stop otus-app')
    for _ in range(6):
        row = wait_for(lambda r: json.loads(r[2])['backend'] == 'app2', 'app2')
        assert json.loads(row[2])['backend'] == 'app2'
    results['checks']['backend_failover'] = True
    ssh('21', 'sudo systemctl start otus-app')
    seen = set()
    for _ in range(30):
        seen.add(json.loads(wait_for(lambda r: True, 'backend response')[2])['backend'])
        if seen == {'app1', 'app2'}:
            break
        time.sleep(1)
    assert seen == {'app1', 'app2'}, seen
    results['checks']['backend_recovery'] = sorted(seen)

    ssh('11', 'sudo systemctl stop nginx')
    wait_for(lambda r: r[0] == 'nginx2', 'secondary frontend')
    for _ in range(6):
        assert wait_for(lambda r: r[0] == 'nginx2', 'secondary frontend')[0] == 'nginx2'
    results['checks']['frontend_failover'] = 'nginx2'
    ssh('11', 'sudo systemctl start nginx')
    results['checks']['frontend_recovery'] = wait_for(
        lambda r: r[0] == 'nginx1', 'restored primary frontend'
    )[0]

    count = int(ssh('30', "sudo -u postgres psql -d otusapp -tAc 'SELECT count(*) FROM requests'"))
    assert count >= 14, count
    results['checks']['database_requests'] = count
    results['verified'] = True
finally:
    for host, service in [('21', 'otus-app'), ('11', 'nginx')]:
        subprocess.run(['ssh', '-i', KEY, '-o', 'StrictHostKeyChecking=no',
                        '-o', 'UserKnownHostsFile=/dev/null', f'ubuntu@192.168.56.{host}',
                        f'sudo systemctl start {service}'], capture_output=True, timeout=20,
                       check=False)
    evidence = pathlib.Path('evidence/ci-lab-results.json')
    evidence.parent.mkdir(exist_ok=True)
    evidence.write_text(json.dumps(results, indent=2) + '\n')
    print(evidence.read_text())
