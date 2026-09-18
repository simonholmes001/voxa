#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/validate-release-config.sh"

run_expect_failure() {
  if "$@" >/dev/null 2>&1; then
    echo "Expected command to fail: $*" >&2
    exit 1
  fi
}

VOXA_API_BASE_URL="https://api.example.test" \
VOXA_PRIVACY_POLICY_URL="https://privacy.example.test/policy" \
  bash "$SCRIPT" >/dev/null

run_expect_failure env \
  VOXA_API_BASE_URL="" \
  VOXA_PRIVACY_POLICY_URL="https://privacy.example.test/policy" \
  bash "$SCRIPT"

run_expect_failure env \
  VOXA_API_BASE_URL="http://localhost:7071" \
  VOXA_PRIVACY_POLICY_URL="not-a-url" \
  bash "$SCRIPT"

run_expect_failure env \
  VOXA_API_BASE_URL="https://api.example.test" \
  VOXA_PRIVACY_POLICY_URL="https://example.com/privacy" \
  bash "$SCRIPT"

echo "validate-release-config tests passed."
