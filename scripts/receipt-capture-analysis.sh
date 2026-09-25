#!/bin/bash
# SCAN-ML-01 step 3 — why the receipt pipeline is wrong, as opposed to how much (that is
# receipt-benchmark.sh). Classifies every ground-truth item row by what the OCR actually captured,
# so capture limits are separated from defects a parser or a model could fix.
#
# Asserts nothing. Writes a report to xBillTests/ReceiptCorpus/reports/line-capture-*.txt.
set -euo pipefail
cd "$(dirname "$0")/.."

SIM="${XBILL_SIM:-DA97985A-F7CC-44F6-8281-9DD24C22B978}"
CORPUS="xBillTests/ReceiptCorpus"

if [ ! -d "$CORPUS/images" ]; then
  echo "No corpus at $CORPUS/images — nothing to analyse."; exit 0
fi

XBILL_CAPTURE_ANALYSIS=1 \
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project xBill.xcodeproj -scheme xBill \
  -destination "id=$SIM" \
  -only-testing:xBillTests/LineCaptureAnalysis >/dev/null 2>&1 || true

REPORT=$(ls -t "$CORPUS"/reports/line-capture-*.txt 2>/dev/null | head -1)
if [ -n "$REPORT" ]; then cat "$REPORT"; else echo "No report produced."; exit 1; fi
