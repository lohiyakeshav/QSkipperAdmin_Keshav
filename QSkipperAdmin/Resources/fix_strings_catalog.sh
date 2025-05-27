#!/bin/bash

# Script to definitively solve the stringsdata issue by modifying project settings

echo "===== DISABLING STRING CATALOGS FOR THIS PROJECT ====="

# Find the project file by looking in parent directories
CURRENT_DIR="$(pwd)"
PARENT_DIR="$(dirname "$CURRENT_DIR")"
PBXPROJ_PATH=$(find "$PARENT_DIR" -name "*.xcodeproj" -type d | head -n 1)

if [ -n "$PBXPROJ_PATH" ]; then
    PBXPROJ_FILE="$PBXPROJ_PATH/project.pbxproj"
    echo "Found project file at: $PBXPROJ_FILE"
    
    # Backup the project file
    cp "$PBXPROJ_FILE" "${PBXPROJ_FILE}.bak"
    
    # Disable string catalogs by setting LOCALIZATION_PREFERS_STRING_CATALOGS = NO
    sed -i '' 's/LOCALIZATION_PREFERS_STRING_CATALOGS = YES/LOCALIZATION_PREFERS_STRING_CATALOGS = NO/g' "$PBXPROJ_FILE"
    
    # Disable Swift string localization 
    sed -i '' 's/SWIFT_EMIT_LOC_STRINGS = YES/SWIFT_EMIT_LOC_STRINGS = NO/g' "$PBXPROJ_FILE"
    
    echo "✅ Project settings updated to disable string catalogs"
else
    echo "❌ Could not find project.pbxproj file"
fi

# Force clean DerivedData for this project
DERIVED_DATA_PATH="${HOME}/Library/Developer/Xcode/DerivedData"
PROJECT_NAME="QSkipperAdmin"

echo "Cleaning DerivedData for $PROJECT_NAME..."
find "$DERIVED_DATA_PATH" -path "*$PROJECT_NAME*" -delete
rm -rf "$DERIVED_DATA_PATH"/*$PROJECT_NAME*

echo "✅ DerivedData cleaned"

# Create marker file to show this ran
touch "${TMPDIR}/qskipperadmin_strings_fixed"

echo "✅ String catalog fix completed"
echo "Please clean and rebuild the project in Xcode" 