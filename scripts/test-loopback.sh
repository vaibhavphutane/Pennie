#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p .build/checks docs/evidence
swiftc -swift-version 5 -D LOOPBACK_CHECKS -parse-as-library \
    Sources/WriteDockCore/*.swift Tests/WriteDockCoreTests/LoopbackChecks.swift \
    -o .build/checks/writedock-loopback-checks
fixture_dir=$(mktemp -d "${TMPDIR:-/tmp}/writedock-loopback.XXXXXX")
python3 scripts/mock_backend.py --port 0 --port-file "$fixture_dir/port" > "$fixture_dir/server.log" 2>&1 &
fixture_pid=$!
cleanup() {
    # Terminate only the child started by this script, never by process name or port.
    kill "$fixture_pid" 2>/dev/null || true
    wait "$fixture_pid" 2>/dev/null || true
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' HUP TERM
attempt=0
while [ ! -s "$fixture_dir/port" ]; do
    if ! kill -0 "$fixture_pid" 2>/dev/null; then
        cat "$fixture_dir/server.log"
        exit 1
    fi
    attempt=$((attempt + 1))
    if [ "$attempt" -gt 50 ]; then
        echo "Loopback fixture did not become ready." >&2
        exit 1
    fi
    sleep 0.1
done
fixture_port=$(cat "$fixture_dir/port")
.build/checks/writedock-loopback-checks "$fixture_port" > docs/evidence/loopback-checks.txt
cat docs/evidence/loopback-checks.txt
