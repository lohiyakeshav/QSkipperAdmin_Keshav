#!/bin/bash

# Script to remove all stringsdata files causing build conflicts

echo "===== AGGRESSIVE CLEANUP OF STRINGSDATA FILES ====="

# Define search paths
DERIVED_DATA="${HOME}/Library/Developer/Xcode/DerivedData"
PROJECT_NAME="QSkipperAdmin"

# Run cleanup even if project not found
echo "Cleaning all stringsdata files..."

# 1. Find and remove all stringsdata files in DerivedData
find "${DERIVED_DATA}" -name "*.stringsdata" -type f -print -delete

# 2. If we have build environment variables, use them too
if [ -n "${DERIVED_FILE_DIR}" ]; then
    find "${DERIVED_FILE_DIR}" -name "*.stringsdata" -type f -print -delete
fi

if [ -n "${BUILT_PRODUCTS_DIR}" ]; then
    find "${BUILT_PRODUCTS_DIR}" -name "*.stringsdata" -type f -print -delete
fi

# 3. Create dummy stringsdata files with different timestamps
mkdir -p "${DERIVED_DATA}/${PROJECT_NAME}/dummy_stringsdata"
touch "${DERIVED_DATA}/${PROJECT_NAME}/dummy_stringsdata/ImagePicker.stringsdata"
touch "${DERIVED_DATA}/${PROJECT_NAME}/dummy_stringsdata/UIKitImagePicker.stringsdata"

echo "✅ Cleanup completed"
exit 0 