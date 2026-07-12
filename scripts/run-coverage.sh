#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESULTS_ROOT="${PROJECT_ROOT}/TestResults/Coverage"
PROJECT="xBill.xcodeproj"
SCHEME="xBill"
DESTINATION="platform=iOS Simulator,name=iPhone 17"
MODE="unit"
TIMESTAMP="$(date +"%Y.%m.%d_%H-%M-%S")"

usage() {
  cat <<'USAGE'
Usage:
  scripts/run-coverage.sh [unit|full|regression-ui] [--destination DESTINATION]

Modes:
  unit           Run xBillTests only. Fastest reliable coverage signal. Default.
  full           Run the full xBill scheme, including UI tests.
  regression-ui  Run xBillUITests/RegressionUITests only.

Examples:
  scripts/run-coverage.sh
  scripts/run-coverage.sh unit
  scripts/run-coverage.sh full
  scripts/run-coverage.sh regression-ui
  scripts/run-coverage.sh unit --destination 'platform=iOS Simulator,name=iPhone 17'

Outputs:
  TestResults/Coverage/<timestamp>-<mode>.xcresult
  TestResults/Coverage/<timestamp>-<mode>-report.txt
  TestResults/Coverage/<timestamp>-<mode>-report.json
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    unit|full|regression-ui)
      MODE="$1"
      shift
      ;;
    --destination)
      if [[ $# -lt 2 ]]; then
        echo "error: --destination requires a value" >&2
        exit 2
      fi
      DESTINATION="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "error: unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

mkdir -p "${RESULTS_ROOT}"

RESULT_BUNDLE="${RESULTS_ROOT}/${TIMESTAMP}-${MODE}.xcresult"
TEXT_REPORT="${RESULTS_ROOT}/${TIMESTAMP}-${MODE}-report.txt"
JSON_REPORT="${RESULTS_ROOT}/${TIMESTAMP}-${MODE}-report.json"

XCODEBUILD_ARGS=(
  test
  -project "${PROJECT}"
  -scheme "${SCHEME}"
  -destination "${DESTINATION}"
  -enableCodeCoverage YES
  -resultBundlePath "${RESULT_BUNDLE}"
)

case "${MODE}" in
  unit)
    XCODEBUILD_ARGS+=(-only-testing:xBillTests)
    ;;
  regression-ui)
    XCODEBUILD_ARGS+=(-only-testing:xBillUITests/RegressionUITests)
    ;;
  full)
    ;;
esac

cd "${PROJECT_ROOT}"

echo "Running ${MODE} coverage..."
echo "Destination: ${DESTINATION}"
echo "Result bundle: ${RESULT_BUNDLE}"
echo

xcodebuild "${XCODEBUILD_ARGS[@]}"

echo
echo "Writing coverage reports..."
xcrun xccov view --report "${RESULT_BUNDLE}" > "${TEXT_REPORT}"
xcrun xccov view --report --json "${RESULT_BUNDLE}" > "${JSON_REPORT}"

echo
echo "Coverage summary:"
awk 'NR <= 3 || /^[^[:space:]-]/ { print }' "${TEXT_REPORT}"

echo
echo "Coverage artifacts:"
echo "  Result bundle: ${RESULT_BUNDLE}"
echo "  Text report:   ${TEXT_REPORT}"
echo "  JSON report:   ${JSON_REPORT}"
