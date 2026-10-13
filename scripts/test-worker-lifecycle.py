#!/usr/bin/env python3
"""Check timer reaping and TERM cleanup with explicit readiness, without sleeps."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='worker-life-', dir=ROOT / 'results') as directory:
    temp = Path(directory)
    fifo = temp / 'ready'
    os.mkfifo(fifo)
    shim = temp / 'sleep'
    shim.write_text('#!/usr/bin/env bash\nprintf "%s\\n" "$$" >&3\nexec "${REAL_SLEEP}" "$@"\n')
    shim.chmod(0o755)
    env = dict(os.environ, PATH=str(temp) + os.pathsep + os.environ['PATH'], REAL_SLEEP=shutil.which('sleep'))
    helper = ROOT / 'scripts/worker-lifecycle.sh'
    # Readiness comes from the timer itself, then stop must close captured FDs too.
    subprocess.run(['bash', '-c', '''set -euo pipefail
exec 3<>"$2"
source "$1"
CLAIM_TTL_SEC=900
start_worker_heartbeat background_jobs 1 "$$"
read -r timer <&3
stop_worker_heartbeat
if kill -0 "$timer" 2>/dev/null; then echo 'timer survived' >&2; exit 1; fi
''', '--', str(helper), str(fifo)], env=env, check=True, capture_output=True, timeout=5)
    print('PASS heartbeat stop reaps timer and closes captured output')

    inherited_output = temp / 'inherited-job-output'
    subprocess.run(['bash', '-c', '''set -euo pipefail
source "$1"
worker_output_file="$2"
printf fixture > "$worker_output_file"
(trap - EXIT INT TERM; exit 0)
test -f "$worker_output_file"
worker_output_file=""
rm -f "$2"
''', '--', str(helper), str(inherited_output)], check=True, capture_output=True, timeout=5)
    print('PASS inherited EXIT trap does not remove owner output')

    output = temp / 'job-output'
    pidfile = temp / 'job-pid'
    result = subprocess.run(['bash', '-c', '''set -euo pipefail
exec 3<>"$2"
source "$1"
worker_output_file="$3"
printf fixture > "$worker_output_file"
sleep 300 &
worker_job_pid=$!
read -r timer <&3
printf '%s' "$timer" > "$4"
kill -TERM "$$"
''', '--', str(helper), str(fifo), str(output), str(pidfile)], env=env, capture_output=True, timeout=5)
    assert result.returncode == 143, (result.returncode, result.stderr.decode())
    assert not output.exists(), 'TERM retained job output file'
    try:
        os.kill(int(pidfile.read_text()), 0)
    except ProcessLookupError:
        pass
    else:
        raise AssertionError('TERM retained owned child')
    print('PASS worker TERM reaps child and removes temporary output')
print('Worker lifecycle regressions passed')
