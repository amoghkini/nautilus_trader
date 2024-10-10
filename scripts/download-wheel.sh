#!/bin/bash

# Set variables
REPO="nautechsystems/nautilus_trader"
PYTHON_VERSION="cp311"  # Specify Python version (either "cp311" or "cp312")
WORKFLOW_NAME="build-wheels.yml"
GITHUB_API_URL="https://api.github.com"
TOKEN="${GITHUB_TOKEN}"  # Assumes you have a GitHub PAT set in the 'GITHUB_TOKEN' env var

# Check if TOKEN is set
if [[ -z "$TOKEN" ]]; then
  echo "Error: The 'GITHUB_TOKEN' environment variable is not set. Set it with a GitHub personal access token."
  exit 1
fi

# Fetch the latest successful workflow run for the specified workflow
workflow_run_id=$(curl -s -H "Authorization: token $TOKEN" "${GITHUB_API_URL}/repos/${REPO}/actions/workflows/${WORKFLOW_NAME}/runs?status=success" |
  grep '"id":' | head -n 1 | awk '{print $2}' | tr -d ',')

if [[ -z "$workflow_run_id" ]]; then
  echo "Error: No successful workflow run found."
  exit 1
fi

echo "Latest successful workflow run ID: $workflow_run_id"

# Fetch the list of artifacts for the latest successful workflow run and print all artifact names
echo "Fetching artifacts for workflow run $workflow_run_id..."

artifacts=$(curl -s -H "Authorization: token $TOKEN" "${GITHUB_API_URL}/repos/${REPO}/actions/runs/${workflow_run_id}/artifacts")
echo "Artifacts returned by API:"
echo "$artifacts" | grep '"name":'

# Try to find the artifact matching the specified Python version
artifact_name=$(echo "$artifacts" | grep "\"name\": \"nautilus_trader-.*-${PYTHON_VERSION}-.*whl\"" | awk -F'"' '{print $4}')

# Debugging: Print the artifact name that we're trying to find
echo "Trying to find artifact with name matching: nautilus_trader-.*-${PYTHON_VERSION}-.*whl"
echo "Found artifact: $artifact_name"

# Fetch the archive_download_url directly from the artifacts response
artifact_url=$(echo "$artifacts" | grep -A 5 "\"name\": \"$artifact_name\"" | grep '"archive_download_url":' | awk -F'"' '{print $4}')

if [[ -z "$artifact_url" ]]; then
  echo "Error: No artifact URL found for artifact $artifact_name."
  exit 1
fi

echo "Artifact URL: $artifact_url"

# Download the artifact as a zip file
echo "Downloading artifact as zip: $artifact_name.zip"
curl -L -H "Authorization: token $TOKEN" -o "$artifact_name.zip" "$artifact_url"

echo "Downloaded artifact to $artifact_name.zip"