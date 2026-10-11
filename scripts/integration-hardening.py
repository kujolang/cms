#!/usr/bin/env python3
"""Behavior regressions for the October hardening pass; stdlib only."""
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
               CMS_PLUGIN_HOOK_ALLOW_HTTP='true', CMS_RATE_MAX_REQUESTS='1000', CMS_STRUCTURED_LOGS='false', CMS_AUDIT_LOG='true')
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

        finally:
            server.terminate()
            server.wait(timeout=10)
print('Hardening integration passed')
