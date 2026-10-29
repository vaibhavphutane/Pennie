#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p .build/checks docs/evidence
swiftc -swift-version 5 -D CORE_CHECKS -parse-as-library \
    Sources/PennieCore/*.swift Tests/PennieCoreTests/CoreChecks.swift \
    -o .build/checks/pennie-core-checks
.build/checks/pennie-core-checks > docs/evidence/core-checks.txt
cat docs/evidence/core-checks.txt
