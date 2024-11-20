#!/usr/bin/env bash

set -e -o pipefail

type gh > /dev/null 2>&1 || { echo >&2 'ERROR: Script requires "gh" (see https://cli.github.com)'; exit 1; }
type go-coverage-report > /dev/null 2>&1 || { echo >&2 'ERROR: Script requires "go-coverage-report" binary in PATH'; exit 1; }

USAGE="$0: Execute go-coverage-report as GitHub action.

This script is meant to be used as a GitHub action and makes use of Workflow commands as
described in https://docs.github.com/en/actions/using-workflows/workflow-commands-for-github-actions

Usage:
    $0 github_repository github_pull_request_number github_run_id app_name

Example:
    $0 fgrosse/prioqueue 12 8221109494 testApp

You can largely rely on the default environment variables set by GitHub Actions. The script should be invoked like
this in the workflow file:

    -name: Code coverage report
     run: github-action.sh \${{ github.repository }} \${{ github.event.pull_request.number }} \${{ github.run_id }} \${{ inputs.app-name }}
     env: …

You can use the following environment variables to configure the script:
- GITHUB_BASELINE_WORKFLOW: The name of the GitHub actions Workflow that produces the baseline coverage (default: CI)
- COVERAGE_ARTIFACT_NAME: The name of the artifact containing the code coverage results (default: code-coverage)
- COVERAGE_FILE_NAME: The name of the file containing the code coverage results (default: coverage.txt)
- CHANGED_FILES_PATH: The path to the file containing the list of changed files (default: .github/outputs/all_modified_files.json)
- ROOT_PACKAGE: The import path of the tested repository to add as a prefix to all paths of the changed files (optional)
- TRIM_PACKAGE: Trim a prefix in the \"Impacted Packages\" column of the markdown report (optional)
- SKIP_COMMENT: Skip creating or updating the pull request comment (default: false)
"

if [[ $# != 4 ]]; then
  echo -e "Error: script requires exactly four arguments\n"
  echo "$USAGE"
  exit 1
fi

GITHUB_REPOSITORY=$1
GITHUB_PULL_REQUEST_NUMBER=$2
GITHUB_RUN_ID=$3
APP_NAME=$4
GITHUB_BASELINE_WORKFLOW=${GITHUB_BASELINE_WORKFLOW:-CI}
COVERAGE_ARTIFACT_NAME=${COVERAGE_ARTIFACT_NAME:-code-coverage}
COVERAGE_FILE_NAME=${COVERAGE_FILE_NAME:-coverage.txt}

OLD_COVERAGE_PATH=.github/outputs/old-coverage.txt
NEW_COVERAGE_PATH=.github/outputs/new-coverage.txt
COVERAGE_COMMENT_PATH=.github/outputs/coverage-comment.md
CHANGED_FILES_PATH=${CHANGED_FILES_PATH:-.github/outputs/all_modified_files.json}
SKIP_COMMENT=${SKIP_COMMENT:-false}

if [[ -z ${GITHUB_REPOSITORY+x} ]]; then
    echo "Missing github_repository argument"
    exit 1
fi

if [[ -z ${GITHUB_PULL_REQUEST_NUMBER+x} ]]; then
    echo "Missing github_pull_request_number argument"
    exit 1
fi

if [[ -z ${GITHUB_RUN_ID+x} ]]; then
    echo "Missing github_run_id argument"
    exit 1
fi

if [[ -z ${APP_NAME+x} ]]; then
    echo "Missing app_name argument"
    exit 1
fi

if [[ -z ${GITHUB_OUTPUT+x} ]]; then
    echo "Missing GITHUB_OUTPUT environment variable"
    exit 1
fi

export GH_REPO="$GITHUB_REPOSITORY"

start_group(){
    echo "::group::$*"
    { set -x; return; } 2>/dev/null
}

end_group(){
    { set +x; return; } 2>/dev/null
    echo "::endgroup::"
}

start_group "Compare code coverage results"
go-coverage-report \
    -root="$ROOT_PACKAGE" \
    -trim="$TRIM_PACKAGE" \
    "$OLD_COVERAGE_PATH" \
    "$NEW_COVERAGE_PATH" \
    "$APP_NAME" \
    "$CHANGED_FILES_PATH" \
  > $COVERAGE_COMMENT_PATH
end_group

if [ ! -s $COVERAGE_COMMENT_PATH ]; then
  echo "::notice::No coverage report to output"
  exit 0
fi

if grep -q "will \*\*not change\*\*" "$COVERAGE_COMMENT_PATH"; then
  echo "::notice::No coverage change detected"
  exit 0
fi

# Output the coverage report as a multiline GitHub output parameter
echo "Writing GitHub output parameter to \"$GITHUB_OUTPUT\""
{
  echo "coverage_report<<END_OF_COVERAGE_REPORT"
  cat "$COVERAGE_COMMENT_PATH"
  echo "END_OF_COVERAGE_REPORT"
} >> "$GITHUB_OUTPUT"

if [ "$SKIP_COMMENT" = "true" ]; then
  echo "Skipping pull request comment (\$SKIP_COMMENT=true))"
  exit 0
fi

start_group "Comment on pull request"
COMMENT_ID=$(gh api "repos/${GITHUB_REPOSITORY}/issues/${GITHUB_PULL_REQUEST_NUMBER}/comments" -q '.[] | select(.user.login=="github-actions[bot]" and (.body | test("'$APP_NAME' coverage")) ) | .id' | head -n 1)
if [ -z "$COMMENT_ID" ]; then
  echo "Creating new coverage report comment"
else
  echo "Replacing old coverage report comment"
  gh api -X DELETE "repos/${GITHUB_REPOSITORY}/issues/comments/${COMMENT_ID}"
fi

gh pr comment "$GITHUB_PULL_REQUEST_NUMBER" --body-file=$COVERAGE_COMMENT_PATH
end_group
