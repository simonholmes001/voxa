#!/usr/bin/env bash
set -euo pipefail

required=(VOXA_API_BASE_URL VOXA_PRIVACY_POLICY_URL)

for key in "${required[@]}"; do
  value="${!key:-}"
  if [ -z "$value" ]; then
    echo "${key} must be configured for a release build." >&2
    exit 1
  fi

  case "$value" in
    http://*|https://*) ;;
    *)
      echo "${key} must be an absolute HTTP(S) URL." >&2
      exit 1
      ;;
  esac

  case "$value" in
    *\<*|*\>*|*TODO*|*todo*|*example.com*)
      echo "${key} contains a placeholder value." >&2
      exit 1
      ;;
  esac
done

echo "Release configuration validation passed."
