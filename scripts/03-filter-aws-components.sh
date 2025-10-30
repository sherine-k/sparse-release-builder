#!/bin/bash
set -euo pipefail

# Script to filter AWS-related components from image-references

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="${SCRIPT_DIR}/../work"
REFERENCES_FILE="${WORK_DIR}/image-references.json"
AWS_COMPONENTS_FILE="${WORK_DIR}/aws-components.json"

echo "==> Filtering AWS-related components"

# Check if image-references file exists
if [ ! -f "${REFERENCES_FILE}" ]; then
    echo "Error: Image references file not found: ${REFERENCES_FILE}"
    echo "Please run 02-extract-references.sh first"
    exit 1
fi

# Filter for AWS components
# Looking for components that contain 'aws' in their name
jq '.spec.tags | map(select(.name | contains("aws")))' "${REFERENCES_FILE}" > "${AWS_COMPONENTS_FILE}"

echo "==> AWS components extracted to: ${AWS_COMPONENTS_FILE}"
echo ""
echo "Found components:"
jq -r '.[].name' "${AWS_COMPONENTS_FILE}"
echo ""
echo "Total AWS components:" $(jq 'length' "${AWS_COMPONENTS_FILE}")
