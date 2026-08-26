#!/usr/bin/env bash
set -euo pipefail

PROJECT_PATH="${VOXA_XCODE_PROJECT:-}"
WORKSPACE_PATH="${VOXA_XCODE_WORKSPACE:-}"
SCHEME="${VOXA_XCODE_SCHEME:-}"
MANIFEST_PATH="${VOXA_PRIVACY_MANIFEST_PATH:-ios/VoxaApp/PrivacyInfo.xcprivacy}"
INFO_PLIST_PATH="${VOXA_INFO_PLIST_PATH:-ios/Voxa/Info.plist}"

if [ -z "$SCHEME" ]; then
  echo "VOXA_XCODE_SCHEME is required" >&2
  exit 1
fi

if [ -n "$PROJECT_PATH" ] && [ -n "$WORKSPACE_PATH" ]; then
  echo "Set only one of VOXA_XCODE_PROJECT or VOXA_XCODE_WORKSPACE" >&2
  exit 1
fi

if [ -z "$PROJECT_PATH" ] && [ -z "$WORKSPACE_PATH" ]; then
  echo "Either VOXA_XCODE_PROJECT or VOXA_XCODE_WORKSPACE must be set" >&2
  exit 1
fi

if [ -n "$PROJECT_PATH" ]; then
  [ -d "$PROJECT_PATH" ] || { echo "Xcode project not found: $PROJECT_PATH" >&2; exit 1; }
  LIST_JSON="$(xcodebuild -project "$PROJECT_PATH" -list -json)"
else
  [ -d "$WORKSPACE_PATH" ] || { echo "Xcode workspace not found: $WORKSPACE_PATH" >&2; exit 1; }
  LIST_JSON="$(xcodebuild -workspace "$WORKSPACE_PATH" -list -json)"
fi

echo "$LIST_JSON" | jq -e --arg scheme "$SCHEME" '.project.schemes // .workspace.schemes | index($scheme) != null' >/dev/null || {
  echo "Scheme not found: $SCHEME" >&2
  exit 1
}

[ -f "$MANIFEST_PATH" ] || { echo "Missing privacy manifest: $MANIFEST_PATH" >&2; exit 1; }
[ -f "$INFO_PLIST_PATH" ] || { echo "Missing app Info.plist: $INFO_PLIST_PATH" >&2; exit 1; }

if command -v plutil >/dev/null 2>&1; then
  plutil -lint "$MANIFEST_PATH" >/dev/null
  plutil -lint "$INFO_PLIST_PATH" >/dev/null
  plutil -extract NSPrivacyTracking raw "$MANIFEST_PATH" >/dev/null
  plutil -extract NSPrivacyCollectedDataTypes xml1 -o - "$MANIFEST_PATH" >/dev/null
  plutil -extract NSPrivacyAccessedAPITypes xml1 -o - "$MANIFEST_PATH" >/dev/null
  plutil -extract NSMicrophoneUsageDescription raw "$INFO_PLIST_PATH" >/dev/null
  plutil -extract NSSpeechRecognitionUsageDescription raw "$INFO_PLIST_PATH" >/dev/null
else
  python3 - "$MANIFEST_PATH" "$INFO_PLIST_PATH" <<'PY'
import plistlib
import sys

manifest_path = sys.argv[1]
info_path = sys.argv[2]

with open(manifest_path, "rb") as f:
    manifest = plistlib.load(f)

with open(info_path, "rb") as f:
    info = plistlib.load(f)

for key in ["NSPrivacyTracking", "NSPrivacyCollectedDataTypes", "NSPrivacyAccessedAPITypes"]:
    if key not in manifest:
        raise SystemExit(f"Missing required privacy key: {key}")

for key in ["NSMicrophoneUsageDescription", "NSSpeechRecognitionUsageDescription"]:
    if key not in info or not str(info[key]).strip():
        raise SystemExit(f"Missing required usage description key: {key}")
PY
fi

echo "iOS/iPadOS project and privacy manifest validation passed."
