import SwiftUI
import UIKit
import PhotosUI

struct UIKitImagePicker: UIViewControllerRepresentable {
    @Binding var selectedImage: UIImage?
    @Environment(\.presentationMode) private var presentationMode
    
    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 1
        config.preferredAssetRepresentationMode = .current
        
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        
        // Apply green theme to the picker
        if let navigationBar = picker.navigationController?.navigationBar {
            let appearance = UINavigationBarAppearance()
            appearance.configureWithOpaqueBackground()
            
            if let primaryGreen = UIColor(hex: "#34C759") {
                navigationBar.tintColor = primaryGreen
                appearance.titleTextAttributes = [.foregroundColor: primaryGreen]
                appearance.buttonAppearance.normal.titleTextAttributes = [.foregroundColor: primaryGreen]
            }
            
            navigationBar.standardAppearance = appearance
            navigationBar.scrollEdgeAppearance = appearance
        }
        
        return picker
    }
    
    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {
        // Nothing to update
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: UIKitImagePicker
        
        init(_ parent: UIKitImagePicker) {
            self.parent = parent
        }
        
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            // Dismiss the picker
            parent.presentationMode.wrappedValue.dismiss()
            
            // Get the selected image
            guard let provider = results.first?.itemProvider else { return }
            
            if provider.canLoadObject(ofClass: UIImage.self) {
                provider.loadObject(ofClass: UIImage.self) { [weak self] image, error in
                    DispatchQueue.main.async {
                        guard let self = self, let image = image as? UIImage else { return }
                        
                        // Process the image (resize if needed)
                        let processedImage = self.processImage(image)
                        self.parent.selectedImage = processedImage
                    }
                }
            }
        }
        
        // Process and resize image if needed
        private func processImage(_ image: UIImage) -> UIImage {
            // If the image is extremely large, resize it while maintaining quality
            let maxSize: CGFloat = 1500  // Increased from 1200 for better quality
            
            if max(image.size.width, image.size.height) > maxSize {
                let scale = maxSize / max(image.size.width, image.size.height)
                let newWidth = image.size.width * scale
                let newHeight = image.size.height * scale
                let newSize = CGSize(width: newWidth, height: newHeight)
                
                // Use a higher scale factor (2.0) for better quality resizing
                UIGraphicsBeginImageContextWithOptions(newSize, false, 2.0)
                image.draw(in: CGRect(origin: .zero, size: newSize))
                let resizedImage = UIGraphicsGetImageFromCurrentImageContext() ?? image
                UIGraphicsEndImageContext()
                
                DebugLogger.shared.log("Image resized from \(Int(image.size.width))x\(Int(image.size.height)) to \(Int(newWidth))x\(Int(newHeight))", category: .app)
                return resizedImage
            }
            
            // If image is already reasonably sized, just return it
            DebugLogger.shared.log("Image is already appropriate size: \(Int(image.size.width))x\(Int(image.size.height))", category: .app)
            return image
        }
    }
} 