#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/checks docs/evidence
swiftc -swift-version 5 -parse-as-library Sources/Pennie/AccessibilityBridge.swift scripts/accessibility-checks.swift -o .build/checks/accessibility-checks
.build/checks/accessibility-checks | tee docs/evidence/accessibility-checks.txt
