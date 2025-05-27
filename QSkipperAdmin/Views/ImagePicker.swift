import SwiftUI
import UIKit

// Simple wrapper for image picking functionality without PHPicker dependency
struct ImagePicker: View {
    @Binding var image: UIImage?
    var onImageSelected: (() -> Void)? = nil
    @State private var showImageSourceSelection = false
    @State private var showCameraPicker = false
    @State private var showLibraryPicker = false
    
    var body: some View {
        Button(action: {
            showImageSourceSelection = true
        }) {
            Text(LocalizedStringKey("select_image"))
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color(AppColors.primaryGreen))
                .foregroundColor(.white)
                .cornerRadius(8)
        }
        .actionSheet(isPresented: $showImageSourceSelection) {
            ActionSheet(
                title: Text(LocalizedStringKey("select_photo_source")),
                buttons: [
                    .default(Text(LocalizedStringKey("photo_library"))) {
                        showLibraryPicker = true
                    },
                    .default(Text(LocalizedStringKey("camera"))) {
                        showCameraPicker = true
                    },
                    .cancel(Text(LocalizedStringKey("cancel")))
                ]
            )
        }
        .sheet(isPresented: $showLibraryPicker) {
            CustomImagePicker(selectedImage: $image, sourceType: .photoLibrary, onImageSelected: {
                onImageSelected?()
                showLibraryPicker = false
            })
        }
        .sheet(isPresented: $showCameraPicker) {
            CustomImagePicker(selectedImage: $image, sourceType: .camera, onImageSelected: {
                onImageSelected?()
                showCameraPicker = false
            })
        }
    }
}

// Internal UIKit wrapper that doesn't rely on localization strings
struct CustomImagePicker: UIViewControllerRepresentable {
    @Binding var selectedImage: UIImage?
    var sourceType: UIImagePickerController.SourceType
    var onImageSelected: (() -> Void)? = nil
    
    @Environment(\.presentationMode) private var presentationMode
    
    class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: CustomImagePicker
        
        init(_ parent: CustomImagePicker) {
            self.parent = parent
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let image = info[.editedImage] as? UIImage {
                parent.selectedImage = image
            } else if let image = info[.originalImage] as? UIImage {
                parent.selectedImage = image
            }
            
            parent.onImageSelected?()
            parent.presentationMode.wrappedValue.dismiss()
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.presentationMode.wrappedValue.dismiss()
        }
    }
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.allowsEditing = true
        
        // Only set camera source if available
        if sourceType == .camera && UIImagePickerController.isSourceTypeAvailable(.camera) {
            picker.sourceType = .camera
        } else {
            picker.sourceType = .photoLibrary
        }
        
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
} 