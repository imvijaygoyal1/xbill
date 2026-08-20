#!/bin/bash
# Scores the shipped receipt-scan pipeline against the labelled corpus in
# xBillTests/ReceiptCorpus/ (git-ignored). Prints a report and writes it to TestResults/.
#
# This is a measurement, not a gate — it asserts nothing about accuracy.
set -euo pipefail
cd "$(dirname "$0")/.."

SIM="${XBILL_SIM:-DA97985A-F7CC-44F6-8281-9DD24C22B978}"
CORPUS="xBillTests/ReceiptCorpus"

if [ ! -d "$CORPUS/images" ]; then
  echo "No corpus at $CORPUS/images — nothing to measure."; exit 0
fi
echo "Corpus: $(ls "$CORPUS/images" | wc -l | tr -d ' ') images, $(ls "$CORPUS/labels" | wc -l | tr -d ' ') labels"

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project xBill.xcodeproj -scheme xBill \
  -destination "id=$SIM" \
  -only-testing:xBillTests/ReceiptBenchmark \

  2>&1 | sed -n '/RECEIPT SCAN BENCHMARK/,/^$/p'
