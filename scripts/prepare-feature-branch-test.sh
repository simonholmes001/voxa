#!/usr/bin/env bash
set -euo pipefail

ENVIRONMENT="${1:-dev}"
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
COMMON_GIT_DIR="$(git -C "$ROOT_DIR" rev-parse --path-format=absolute --git-common-dir)"
PRIMARY_ROOT="$(dirname "$COMMON_GIT_DIR")"
BRANCH="$(git -C "$ROOT_DIR" branch --show-current)"

if [[ "$BRANCH" == "main" || -z "$BRANCH" ]]; then
  echo "Run this script from a feature worktree, not main." >&2
  exit 1
fi

SOURCE_CONFIG="$PRIMARY_ROOT/ios/Voxa/Config/Debug.local.xcconfig"
TARGET_CONFIG="$ROOT_DIR/ios/Voxa/Config/Debug.local.xcconfig"
if [[ -f "$SOURCE_CONFIG" ]]; then
  mkdir -p "$(dirname "$TARGET_CONFIG")"
  cp "$SOURCE_CONFIG" "$TARGET_CONFIG"
  echo "Copied local iOS backend configuration into this worktree."
else
  echo "Missing $SOURCE_CONFIG; create it from Debug.local.xcconfig.example first." >&2
  exit 1
fi

export GITHUB_REF="refs/heads/$BRANCH"
export GITHUB_FEDERATED_CREDENTIAL_NAME="github-${BRANCH//\//-}"

echo
echo "Feature-branch test configuration:"
echo "  branch: $BRANCH"
echo "  environment: $ENVIRONMENT"
echo "  GITHUB_REF=$GITHUB_REF"
echo "  GITHUB_FEDERATED_CREDENTIAL_NAME=$GITHUB_FEDERATED_CREDENTIAL_NAME"
echo "  iOS config: $TARGET_CONFIG"
echo
echo "To configure the feature-branch Azure federated credential, run:"
echo "  AZURE_SUBSCRIPTION_ID=\$(az account show --query id --output tsv)"
echo "  GITHUB_REF=$GITHUB_REF"
echo "  GITHUB_FEDERATED_CREDENTIAL_NAME=$GITHUB_FEDERATED_CREDENTIAL_NAME"
echo "  ./scripts/setup-azure-auth-for-pipeline.sh $ENVIRONMENT"
