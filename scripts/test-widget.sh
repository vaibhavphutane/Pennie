#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/checks docs/evidence
swiftc -swift-version 5 -D WIDGET_CHECKS -parse-as-library Sources/WriteDockCore/FloatingPlacement.swift Tests/WriteDockCoreTests/WidgetPlacementChecks.swift -o .build/checks/widget-checks
.build/checks/widget-checks | tee docs/evidence/widget-checks.txt
