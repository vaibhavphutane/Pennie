#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/checks docs/evidence
swiftc -swift-version 5 -D WIDGET_CHECKS -parse-as-library Sources/PennieCore/FloatingPlacement.swift Tests/PennieCoreTests/WidgetPlacementChecks.swift -o .build/checks/widget-checks
.build/checks/widget-checks | tee docs/evidence/widget-checks.txt
