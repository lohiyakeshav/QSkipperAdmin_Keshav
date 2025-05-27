# How to Fix the Localization Build Issues

## Option 1: Add a Run Script Build Phase

1. Open your Xcode project
2. Select the QSkipperAdmin target
3. Go to the "Build Phases" tab
4. Click the "+" button in the upper left corner
5. Select "New Run Script Phase"
6. Drag this new script phase to be the FIRST phase in the list
7. Paste the following script:

```bash
#!/bin/bash
echo "===== Cleaning up stringsdata files ====="
find "${DERIVED_FILE_DIR}" -name "*.stringsdata" -delete
find "${BUILT_PRODUCTS_DIR}" -name "*.stringsdata" -delete
echo "✅ Cleanup completed"
```

8. Build the project

## Option 2: Exclude Files from Build

1. Open your Xcode project
2. In the Project Navigator, find the Resources/en.lproj folder
3. Select the problematic strings files (ImagePicker.strings, UIKitImagePicker.strings)
4. In the File Inspector (right panel), under Target Membership, UNCHECK the box for the QSkipperAdmin target
5. Build the project

## Option 3: Clean DerivedData and Rebuild

1. Quit Xcode
2. Open Terminal
3. Run this command to remove DerivedData:
```bash
rm -rf ~/Library/Developer/Xcode/DerivedData/*QSkipperAdmin*
```
4. Reopen Xcode
5. Clean the build folder (Shift+Cmd+K)
6. Build the project (Cmd+B)

If problems persist, try each option in sequence. 