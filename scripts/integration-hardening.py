#!/usr/bin/env python3
"""Behavior regressions for the October hardening pass; stdlib only."""
import base64
import io
import zipfile
import datetime
import json
import http.server
import threading
import os
from pathlib import Path
import shutil
import socket
import sqlite3
import subprocess
import tempfile
import time
import urllib.error
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
TOKEN = 'hardening-local-fixture-token'
port = int(os.environ.get('CMS_TEST_PORT', '49407'))
with socket.socket() as probe:
    probe.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    probe.bind(('127.0.0.1', port))
base = f'http://127.0.0.1:{port}'

def request(method, path, body=None, headers=None, status=200):
    supplied = {'Authorization': f'Bearer {TOKEN}', 'Content-Type': 'application/json'} if headers is None else headers
    req = urllib.request.Request(base + path, data=None if body is None else json.dumps(body).encode(), headers=supplied, method=method)
    try:
        response = urllib.request.urlopen(req, timeout=10)
    except urllib.error.HTTPError as error:
        response = error
    with response:
        raw = response.read()
        assert response.status == status, (path, response.status, raw.decode())
        return json.loads(raw)

with tempfile.TemporaryDirectory(prefix='hardening-', dir=ROOT / 'results') as directory:
    db = Path(directory) / 'cms.db'
    env = dict(os.environ, CMS_API_PORT=str(port), CMS_DB_PATH=str(db), CMS_API_TOKEN=TOKEN,
               CMS_PLUGIN_HOOK_ALLOW_HTTP='true', CMS_RATE_MAX_REQUESTS='1000', CMS_RATE_LIMIT_MODE='sqlite',
               CMS_EXTENSION_INBOX_DIR=str(Path(directory)/'inbox'), CMS_EXTENSION_STORE_DIR=str(Path(directory)/'installed'),
               CMS_MEDIA_INBOX_DIR=str(Path(directory)/'media-inbox'), CMS_MEDIA_STORE_DIR=str(Path(directory)/'media-store'), CMS_STRUCTURED_LOGS='false', CMS_AUDIT_LOG='true')
    with open(ROOT / 'results/hardening-integration.log', 'w') as log:
        server = subprocess.Popen([os.environ.get('KUJO_BIN') or shutil.which('kujo'), 'run', '--interpreter', 'backend/runtime/main.kujo'], cwd=ROOT, env=env, stdout=log, stderr=subprocess.STDOUT)
        try:
            deadline = time.monotonic() + 15
            while True:
                assert server.poll() is None, 'CMS exited; see results/hardening-integration.log'
                try:
                    request('GET', '/health')
                    break
                except (urllib.error.URLError, ConnectionError):
                    if time.monotonic() >= deadline:
                        raise
                    time.sleep(.1)
            for expiry in [int(time.time() * 1000) - 60000, (datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(minutes=1)).isoformat()]:
                token = request('POST', '/v1/auth/tokens', {'label': 'expired', 'role_key': 'editor', 'expires_at': expiry}, status=201)['data']['token_secret']
                request('POST', '/v1/content-types', {'type_key': 'denied', 'label': 'Denied'}, {'Authorization': f'Bearer {token}'}, status=401)
            print('PASS realistic epoch and ISO bearer expiry')
            taxonomy = request('POST', '/v1/taxonomies', {'taxonomy_key': 'hardening', 'label': 'Hardening', 'hierarchical': True}, status=201)['data']['id']
            path = f'/v1/taxonomies/{taxonomy}/terms/bulk'
            terms = request('POST', path, {'terms': [{'name': 'Alpha', 'slug': 'alpha'}, {'name': 'Bravo', 'slug': 'bravo'}]})['data']['terms']
            ids = {term['slug']: term['id'] for term in terms}
            request('POST', path, {'terms': [{'name': 'Changed', 'slug': 'alpha', 'parent_id': ids['alpha']}]}, status=400)
            request('POST', path, {'terms': [{'name': 'Changed', 'slug': 'alpha', 'parent_id': ids['bravo']}, {'name': 'Bravo', 'slug': 'bravo', 'parent_id': ids['alpha']}]}, status=400)
            with sqlite3.connect(db) as connection:
                assert connection.execute('SELECT name, parent_id FROM taxonomy_terms WHERE id=?', (ids['alpha'],)).fetchone() == ('Alpha', None)
            print('PASS self/batch cycles rejected with atomic rollback')
            request('POST', '/v1/content-types', {'type_key': 'hardening', 'label': 'Hardening', 'singular_label': 'Item'}, status=201)
            user = request('POST', '/v1/users', {'email': 'hardening@example.test', 'username': 'hardening', 'display_name': 'Hardening', 'role_key': 'editor', 'status': 'active', 'password_hash': 'fixture-derived-hash-' + '0' * 64, 'password_salt': 'fixture-salt-00000000'}, status=201)['data']
            session = request('POST', '/v1/auth/sessions', {'user_id': user['id']}, status=201)['data']['session']['token']
            request('POST', '/v1/entries', {'content_type_key': 'hardening', 'title': 'Session draft', 'slug': 'session-draft', 'body': 'Private body', 'status': 'draft'}, {'X-CMS-Session': session, 'Content-Type': 'application/json'}, status=201)
            with sqlite3.connect(db) as connection:
                actor, details = connection.execute("SELECT actor, details_json FROM audit_log WHERE action='entry.create' ORDER BY id DESC LIMIT 1").fetchone()
                assert actor == f'user:{user["id"]}', actor
                assert json.loads(details)['request_id']
            metrics = request('GET', '/metrics')['data']['metrics']
            assert metrics['requests_total'] > 10 and metrics['unauthorized_total'] >= 2, metrics
            print('PASS persisted session audit identity, request ID and live metrics')
            entry = request('POST', '/v1/entries', {'content_type_key': 'hardening', 'title': 'Compose version', 'slug': 'compose-version', 'body': 'Body', 'status': 'draft'}, status=201)['data']
            compose_path = f'/v1/entries/{entry["id"]}/compose'
            composed = request('PATCH', compose_path, {'expected_updated_at': entry['updated_at'], 'term_ids': [ids['alpha']]})['data']['entry']
            assert str(composed['updated_at']) != str(entry['updated_at']), 'term-only compose retained stale version'
            request('PATCH', compose_path, {'expected_updated_at': entry['updated_at'], 'term_ids': [ids['bravo']]}, status=409)
            second = request('PATCH', compose_path, {'expected_updated_at': composed['updated_at'], 'entry': {'title': 'Second compose'}})['data']['entry']
            assert str(second['updated_at']) != str(composed['updated_at']), 'rapid compose reused version'
            with sqlite3.connect(db) as connection:
                details = json.loads(connection.execute("SELECT details_json FROM audit_log WHERE action='entry.compose' ORDER BY id DESC LIMIT 1").fetchone()[0])
                assert details['slug'] == 'compose-version' and details['content_type_key'] == 'hardening'
                connection.execute("INSERT INTO plugins (plugin_key,name,version,status,capabilities_json,config_json,created_at,updated_at) VALUES ('compose_hook','Compose hook','1.0.0','active','[]','{}',0,0)")
                plugin_id = connection.execute("SELECT id FROM plugins WHERE plugin_key='compose_hook'").fetchone()[0]
                connection.execute("INSERT INTO plugin_hooks (plugin_id,hook_name,handler_url,shared_secret,enabled,created_at,updated_at) VALUES (?, 'entry.updated','https://example.test/hook','fixture-secret',1,0,0)", (plugin_id,))
            subprocess.run(['bash', 'scripts/enqueue-webhook-outbox.sh'], cwd=ROOT, env=env, check=True, stdout=subprocess.DEVNULL)
            with sqlite3.connect(db) as connection:
                assert connection.execute("SELECT COUNT(*) FROM webhook_outbox WHERE event_type='entry.updated'").fetchone()[0] == 2
            subprocess.run(['bash', 'scripts/enqueue-webhook-outbox.sh'], cwd=ROOT, env=env, check=True, stdout=subprocess.DEVNULL)
            with sqlite3.connect(db) as connection:
                assert connection.execute("SELECT COUNT(*) FROM webhook_outbox WHERE event_type='entry.updated'").fetchone()[0] == 2
            print('PASS compose versions, stale-write rejection and webhook enqueue deduplication')
            archive = io.BytesIO()
            manifest = json.loads((ROOT / 'examples/extensions/starter-plugin/kujo-plugin.json').read_text())
            manifest['key'] = 'cleanup_probe'
            with zipfile.ZipFile(archive, 'w') as package:
                package.writestr('kujo-plugin.json', json.dumps(manifest))
                package.writestr('nested/asset.txt', 'fixture')
            payload = {'data_base64': base64.b64encode(archive.getvalue()).decode()}
            installed = request('POST', '/v1/extensions/packages/upload', payload)['data']
            old_root = Path(installed['storage']['install_root'])
            victim = Path(directory) / 'victim'
            victim.mkdir()
            sentinel = victim / 'sentinel.txt'
            sentinel.write_text('must survive')
            forged = str(old_root) + '/../../victim'
            request('PATCH', f'/v1/plugins/{installed["extension"]["id"]}', {'config': {'storage': {'install_root': forged}}})
            replacement = request('POST', '/v1/extensions/packages/upload', payload)['data']
            assert sentinel.exists(), 'client-controlled cleanup deleted an outside file'
            legit_root = Path(replacement['storage']['install_root'])
            assert legit_root.parent == old_root.parent and legit_root != old_root, 'replacement reused client-controlled storage path'
            with sqlite3.connect(db) as connection:
                saved_config = json.loads(connection.execute('SELECT config_json FROM plugins WHERE id=?', (installed['extension']['id'],)).fetchone()[0])
                assert saved_config['storage']['install_root'] == str(legit_root), 'persisted replacement storage differs from receipt'
            request('POST', '/v1/extensions/packages/upload', payload)
            assert not legit_root.exists(), 'legitimate owned package replacement did not clean up'
            linked_root = Path(directory) / 'installed' / ('package-' + 'a' * 32)
            linked_root.symlink_to(victim, target_is_directory=True)
            request('PATCH', f'/v1/plugins/{installed["extension"]["id"]}', {'config': {'storage': {'install_root': str(linked_root)}}})
            request('POST', '/v1/extensions/packages/upload', payload)
            assert sentinel.exists(), 'cleanup followed a package symlink'

            for kind, key in [('plugin', 'another_plugin'), ('theme', 'cleanup_probe')]:
                other_manifest = json.loads((ROOT / f'examples/extensions/starter-{kind}/kujo-{kind}.json').read_text())
                other_manifest['key'] = key
                other_archive = io.BytesIO()
                with zipfile.ZipFile(other_archive, 'w') as package:
                    package.writestr(f'kujo-{kind}.json', json.dumps(other_manifest))
                protected = request('POST', '/v1/extensions/packages/upload', {'data_base64': base64.b64encode(other_archive.getvalue()).decode()})['data']
                protected_root = Path(protected['storage']['install_root'])
                request('PATCH', f'/v1/plugins/{installed["extension"]["id"]}', {'config': {'storage': {'install_root': str(protected_root)}}})
                request('POST', '/v1/extensions/packages/upload', payload)
                assert (protected_root / f'kujo-{kind}.json').exists(), 'cleanup crossed extension ownership'
            legacy_root = Path(directory) / 'installed' / ('package-' + 'b' * 32)
            legacy_root.mkdir()
            (legacy_root / 'legacy.txt').write_text('unproven ownership')
            request('PATCH', f'/v1/plugins/{installed["extension"]["id"]}', {'config': {'storage': {'install_root': str(legacy_root)}}})
            request('POST', '/v1/extensions/packages/upload', payload)
            assert (legacy_root / 'legacy.txt').exists(), 'unmarked legacy tree was deleted'
            print('PASS forged package cleanup containment and legitimate replacement')


            class Sink(http.server.BaseHTTPRequestHandler):
                hits = 0
                def do_GET(self):
                    Sink.hits += 1
                    self.send_response(200)
                    self.end_headers()
                    self.wfile.write(b'{}')
                def log_message(self, *_):
                    pass
            with http.server.HTTPServer(('127.0.0.1', 0), Sink) as sink:
                thread = threading.Thread(target=sink.serve_forever, daemon=True)
                thread.start()
                try:
                    manifest = {'schema': 'kujo.plugin/v1', 'key': 'egress_probe', 'name': 'Egress probe', 'abilities': [], 'connectors': [{'key': 'probe', 'label': 'Probe', 'mode': 'plugin_runtime'}]}
                    config = {'package_manifest': manifest, 'settings': {'service_url': f'http://localhost.:{sink.server_port}'}}
                    with sqlite3.connect(db) as connection:
                        connection.execute("INSERT INTO plugins (plugin_key,name,version,status,capabilities_json,config_json,created_at,updated_at) VALUES ('egress_probe','Egress probe','1.0.0','active','[]',?,0,0)", (json.dumps(config),))
                    request('POST', '/v1/ai/connectors/egress_probe-probe/health', {}, status=502)
                    assert Sink.hits == 0, 'private connector target was contacted'
                    print('PASS resolved private connector destination denied before transport')
                finally:
                    sink.shutdown()
                    thread.join()
            media = request('POST', '/v1/media/upload', {'filename': 'fixture.png', 'data_base64': 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jpZkAAAAASUVORK5CYII='})['data']
            object_key = json.loads(media['meta_json'])['object_key']
            media_path = '/v1/media/files/' + object_key
            request('GET', media_path, headers={})
            with sqlite3.connect(db) as connection:
                connection.execute('UPDATE rate_limit_buckets SET count=1000')
            request('GET', media_path, headers={}, status=429)
            print('PASS public media reads enforce request quota')


        finally:
            server.terminate()
            server.wait(timeout=10)
print('Hardening integration passed')
