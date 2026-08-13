#!/bin/zsh
set -euo pipefail

if (( $# != 1 )); then
    print -u2 -r -- "usage: $0 <path-to-app>"
    exit 2
fi

app="$1"
executable="$app/Contents/MacOS/Drift"
grace_seconds="${STARTUP_GRACE_SECONDS:-2}"

[[ -d "$app" ]] || { print -u2 -r -- "app bundle does not exist: $app"; exit 2; }
[[ -x "$executable" ]] || { print -u2 -r -- "app executable does not exist: $executable"; exit 2; }

log_file="$(mktemp "${TMPDIR:-/tmp}/drift-startup.XXXXXX")"
trap 'rm -f "$log_file"' EXIT

python3 - "$executable" "$grace_seconds" "$log_file" <<'PY'
import subprocess
import sys
import time

executable = sys.argv[1]
grace_seconds = float(sys.argv[2])
log_path = sys.argv[3]
process = None

try:
    with open(log_path, "wb") as log:
        process = subprocess.Popen(
            [executable],
            stdout=log,
            stderr=subprocess.STDOUT,
        )
        deadline = time.monotonic() + grace_seconds
        while time.monotonic() < deadline:
            exit_code = process.poll()
            if exit_code is not None:
                log.flush()
                print(
                    f"Drift exited during startup with status {exit_code}",
                    file=sys.stderr,
                )
                with open(log_path, "rb") as diagnostics:
                    sys.stderr.buffer.write(diagnostics.read())
                raise SystemExit(1)
            time.sleep(0.02)

        exit_code = process.poll()
        if exit_code is not None:
            log.flush()
            print(
                f"Drift exited during startup with status {exit_code}",
                file=sys.stderr,
            )
            with open(log_path, "rb") as diagnostics:
                sys.stderr.buffer.write(diagnostics.read())
            raise SystemExit(1)
finally:
    if process is not None and process.poll() is None:
        process.terminate()
        try:
            process.wait(timeout=2)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()
PY
