#!/usr/bin/env python3
"""Deterministically advance queue metadata between candidate selection and claim."""
import json
import os
from pathlib import Path
import re
import shutil
import sqlite3
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
SCRIPT_ROOT = Path(os.environ.get('CMS_WORKER_SCRIPT_ROOT', ROOT))
# Reuse the real initial schema; behavior assertions below exercise worker contracts.
schema = [json.loads(s) for s in re.findall(r'^\s*("(?:[^"\\]|\\.)*")', (ROOT / 'backend/core/database.kujo').read_text(), re.M)
          if json.loads(s).startswith('CREATE TABLE IF NOT EXISTS')]
with tempfile.TemporaryDirectory(prefix='worker-claims-', dir=ROOT / 'results') as directory:
    temp = Path(directory)
    shim = temp / 'sqlite3'
    shim.write_text('''#!/usr/bin/env python3
import os, sqlite3, subprocess, sys
result = subprocess.run([os.environ['REAL_SQLITE3'], *sys.argv[1:]], capture_output=True)
sql = sys.argv[-1]
table = os.environ['RACE_TABLE']
if sql.startswith('SELECT id') and f'FROM {table} WHERE' in sql:
    with sqlite3.connect(os.environ['CMS_DB_PATH']) as db:
        db.execute(f"UPDATE {table} SET attempt_count=2, max_attempts=3, status='retry'")
sys.stdout.buffer.write(result.stdout)
sys.stderr.buffer.write(result.stderr)
sys.exit(result.returncode)
''')
    shim.chmod(0o755)
    for table, script in [('background_jobs', 'process-background-jobs.sh'), ('webhook_outbox', 'process-webhook-outbox.sh')]:
        db = temp / f'{table}.db'
        with sqlite3.connect(db) as connection:
            for statement in schema:
                connection.execute(statement)
            if table == 'background_jobs':
                connection.execute("INSERT INTO background_jobs (job_type,payload_json,status,run_after,created_at,updated_at) VALUES ('unsupported.fixture','{}','pending',0,0,0)")
            else:
                connection.execute("INSERT INTO webhook_outbox (hook_id,event_id,event_type,payload_json,handler_url,shared_secret,status,next_attempt_at,created_at,updated_at) VALUES (1,'fixture','entry.updated','{}','http://127.0.0.1/blocked','fixture','pending',0,0,0)")
        env = dict(os.environ, PATH=str(temp) + os.pathsep + os.environ['PATH'], REAL_SQLITE3=shutil.which('sqlite3'), RACE_TABLE=table,
                   CMS_DB_PATH=str(db), CMS_PLUGIN_HOOK_ALLOW_HTTP='false')
        subprocess.run(['bash', str(SCRIPT_ROOT / 'scripts' / script)], env=env, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=15)
        with sqlite3.connect(db) as connection:
            row = connection.execute(f'SELECT status,attempt_count,claim_token,claim_expires_at FROM {table}').fetchone()
            assert row == ('dead_letter', 3, None, None), (table, row)
        print(f'PASS {table}: claimed metadata governs retry budget')
print('Worker claim regressions passed')
