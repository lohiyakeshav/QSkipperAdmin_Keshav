#!/bin/bash

# Script to fix localization issues in QSkipperAdmin

echo "===== Fixing string catalog issues ====="

# Define paths
PROJECT_DIR="${SRCROOT}"
BUILD_DIR="${BUILT_PRODUCTS_DIR}"
DERIVED_DIR="${DERIVED_FILE_DIR}"

echo "Project directory: ${PROJECT_DIR}"
echo "Build directory: ${BUILD_DIR}"
echo "Derived directory: ${DERIVED_DIR}"

# Remove any stringsdata files that might be causing conflicts
find "${DERIVED_DIR}" -name "*.stringsdata" -delete
find "${BUILD_DIR}" -name "*.stringsdata" -delete

# Create a marker file to indicate the script has run
touch "${DERIVED_DIR}/localization_fixed"

echo "✅ Localization fix completed"
exit 0 