#!/usr/bin/env bash
set -euo pipefail

: "${GH_TOKEN:?GH_TOKEN is required}"
: "${RELEASE_HEAD_SHA:?RELEASE_HEAD_SHA is required}"
: "${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is required}"

api_path="repos/${GITHUB_REPOSITORY}/actions/runs?head_sha=${RELEASE_HEAD_SHA}&per_page=100"
required_workflows=("CI" "Backend CI" "iOS CI")

# Infrastructure deployment is only expected when the push changed paths that
# trigger that workflow. This avoids blocking an iOS-only release on a run
# that GitHub correctly did not schedule.
changed_files="$(git diff --name-only "${RELEASE_HEAD_SHA}^1" "${RELEASE_HEAD_SHA}")"
if grep -Eq '^(backend/|functions/|infrastructure/|\.github/workflows/(infrastructure|iac-lint))' <<<"${changed_files}"; then
  required_workflows+=("Azure Infrastructure Deploy")
fi
if grep -Eq '^(infrastructure/|\.github/workflows/iac-lint\.yaml$)' <<<"${changed_files}"; then
  required_workflows+=("Azure IaC Lint")
fi

echo "Release gate for ${RELEASE_HEAD_SHA}"
printf 'Required workflows: %s\n' "${required_workflows[*]}"

for attempt in $(seq 1 30); do
  runs="$(gh api "${api_path}")"
  waiting=0
  failed=0

  for workflow in "${required_workflows[@]}"; do
    run="$(jq -c --arg name "${workflow}" '[.workflow_runs[] | select(.name == $name)] | sort_by(.created_at) | last // empty' <<<"${runs}")"
    if [[ -z "${run}" ]]; then
      echo "${workflow}: not reported yet (attempt ${attempt}/30)"
      waiting=1
      continue
    fi

    status="$(jq -r '.status' <<<"${run}")"
    conclusion="$(jq -r '.conclusion // ""' <<<"${run}")"
    echo "${workflow}: ${status}/${conclusion}"

    if [[ "${status}" != "completed" ]]; then
      waiting=1
    elif [[ "${conclusion}" != "success" ]]; then
      echo "::error::${workflow} did not succeed for ${RELEASE_HEAD_SHA}."
      failed=1
    fi
  done

  if (( failed == 1 )); then
    exit 1
  fi
  if (( waiting == 0 )); then
    echo "All required workflows succeeded for ${RELEASE_HEAD_SHA}."
    exit 0
  fi

  sleep 20
done

echo "::error::Timed out waiting for required workflows for ${RELEASE_HEAD_SHA}."
exit 1
