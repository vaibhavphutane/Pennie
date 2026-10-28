#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p .build/checks docs/evidence
swiftc -swift-version 5 -D CORE_CHECKS -parse-as-library \
    Sources/WriteDockCore/*.swift Tests/WriteDockCoreTests/CoreChecks.swift \
    -o .build/checks/writedock-core-checks
.build/checks/writedock-core-checks > docs/evidence/core-checks.txt
cat docs/evidence/core-checks.txt
