#!/usr/bin/env bash
set -euo pipefail

: "${GH_TOKEN:?GH_TOKEN is required}"
: "${RELEASE_HEAD_SHA:?RELEASE_HEAD_SHA is required}"
: "${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is required}"

api_path="repos/${GITHUB_REPOSITORY}/actions/runs?head_sha=${RELEASE_HEAD_SHA}&per_page=100"
required_workflows=("CI")

# Infrastructure deployment is only expected when the push changed paths that
# trigger that workflow. This avoids blocking an iOS-only release on a run
# that GitHub correctly did not schedule. `diff-tree --root -m` handles root
# commits and reports changes against every parent of a merge commit; relying
# on `${sha}^1` would abort when that parent is unavailable or inspect only one
# side of a merge.
if ! git cat-file -e "${RELEASE_HEAD_SHA}^{commit}" 2>/dev/null; then
  echo "::error::Release commit ${RELEASE_HEAD_SHA} is not available in the checkout. Fetch the full history before running the release gate." >&2
  exit 1
fi

if ! changed_files="$(git diff-tree --root --no-commit-id --name-only -r -m "${RELEASE_HEAD_SHA}")"; then
  echo "::error::Unable to compute changed files for release commit ${RELEASE_HEAD_SHA}. Verify the commit and its parent history are available." >&2
  exit 1
fi

# Backend CI and iOS CI use push path filters, so a workflow run is not
# expected for every main commit. Mirror those filters here; otherwise an
# iOS-only merge would wait forever for a Backend CI run GitHub intentionally
# did not schedule.
if grep -Eq '^(backend/|docs/api-contracts\.md$|global\.json$|\.github/workflows/backend-ci\.yaml$)' <<<"${changed_files}"; then
  required_workflows+=("Backend CI")
fi
if grep -Eq '^(ios/|docs/api-contracts\.md$|\.github/workflows/ios-ci\.yaml$)' <<<"${changed_files}"; then
  required_workflows+=("iOS CI")
fi
if grep -Eq '^(backend/|functions/|infrastructure/|\.github/workflows/(infrastructure|iac-lint))' <<<"${changed_files}"; then
  required_workflows+=("Azure Infrastructure Deploy")
fi
if grep -Eq '^(infrastructure/|\.github/workflows/iac-lint\.yaml$)' <<<"${changed_files}"; then
  required_workflows+=("Azure IaC Lint")
fi

echo "Release gate for ${RELEASE_HEAD_SHA}"
printf 'Required workflows: %s\n' "${required_workflows[*]}"

# iOS CI can take longer than ten minutes on a cold macOS runner. Keep the
# budget configurable for diagnostics, but give normal releases enough time
# to finish without producing a false failed Release run.
max_attempts="${RELEASE_GATE_MAX_ATTEMPTS:-60}"
poll_seconds="${RELEASE_GATE_POLL_SECONDS:-20}"
echo "Polling required workflows every ${poll_seconds}s for up to ${max_attempts} attempts."

for attempt in $(seq 1 "${max_attempts}"); do
  runs="$(gh api "${api_path}")"
  waiting=0
  failed=0

  for workflow in "${required_workflows[@]}"; do
    run="$(jq -c --arg name "${workflow}" '[.workflow_runs[] | select(.name == $name)] | sort_by(.created_at) | last // empty' <<<"${runs}")"
    if [[ -z "${run}" ]]; then
      echo "${workflow}: not reported yet (attempt ${attempt}/${max_attempts})"
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

  sleep "${poll_seconds}"
done

echo "::error::Timed out waiting for required workflows for ${RELEASE_HEAD_SHA}."
exit 1
