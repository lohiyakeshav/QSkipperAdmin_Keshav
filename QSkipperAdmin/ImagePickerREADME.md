# Image Picker Components in QSkipperAdmin

This project uses multiple image picker components with different implementations to handle various needs.

## Available Image Pickers

1. **ImagePicker** (in `Views/ImagePicker.swift`)
   - The main image picker component
   - Provides a button UI and handles both camera and photo library selection
   - Usage: `ImagePicker(image: $yourImageBinding, onImageSelected: { yourCallbackHere })`

2. **PHImagePicker** (in `Views/Components/PHImagePicker.swift`)
   - Uses the newer PhotosUI framework with PHPickerViewController
   - Bare implementation with no UI - just the picker itself
   - Usage: `PHImagePicker(image: $yourImageBinding)`

3. **UIKitImagePicker** (in `Components/UIKitImagePicker.swift`)
   - Legacy implementation using UIImagePickerController
   - Preserved for backward compatibility
   - Usage: `UIKitImagePicker(selectedImage: $yourImageBinding)`

## Recommended Usage

Always prefer using the main `ImagePicker` from `Views/ImagePicker.swift` for new code as it:
- Has a consistent UI
- Properly handles both camera and photo library
- Includes the callback for image selection
- Doesn't cause stringsdata conflicts

## Avoiding Build Errors

The project previously had build errors related to duplicate stringsdata files caused by:
1. Having multiple components named "ImagePicker"
2. Having localization files for each

We've fixed this by:
- Renaming the component in `Views/Components/` to `PHImagePicker`
- Using a consistent localization approach
- Disabling string catalogs in the project settings

If you encounter stringsdata errors again, run:
```
./QSkipperAdmin/Resources/fix_strings_catalog.sh
```

Then clean and rebuild your project. 